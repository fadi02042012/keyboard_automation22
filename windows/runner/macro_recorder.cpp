#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "macro_recorder.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <cwctype>
#include <map>

std::atomic<MacroRecorder*> MacroRecorder::active_recorder_{nullptr};

namespace {

constexpr int kMaxRecordedDelayMs = 60000;
constexpr int kDoubleClickWindowMs = 500;
constexpr int kDoubleClickDistance = 4;
constexpr auto kHookStartupTimeout = std::chrono::seconds(3);

HWND RootOwnerWindow(HWND window) {
  if (window == nullptr) return nullptr;
  HWND root = GetAncestor(window, GA_ROOTOWNER);
  return root != nullptr ? root : window;
}

std::wstring WindowClassName(HWND window) {
  wchar_t class_name[128]{};
  const int length = GetClassNameW(window, class_name,
                                   static_cast<int>(sizeof(class_name) / sizeof(class_name[0])));
  return length > 0 ? std::wstring(class_name, static_cast<size_t>(length))
                    : std::wstring{};
}

bool IsShellOrTaskbarWindow(HWND window) {
  const HWND root = RootOwnerWindow(window);
  if (root == nullptr) return true;
  const std::wstring class_name = WindowClassName(root);
  return class_name == L"Shell_TrayWnd" ||
         class_name == L"Shell_SecondaryTrayWnd" ||
         class_name == L"MSTaskSwWClass" ||
         class_name == L"MSTaskListWClass" ||
         class_name == L"TaskListThumbnailWnd" ||
         class_name == L"ThumbnailClass" ||
         class_name == L"TrayNotifyWnd" ||
         class_name == L"#32768" ||
         class_name == L"Windows.UI.Core.CoreWindow" ||
         class_name == L"Xaml_WindowedPopupClass";
}

HWND StableApplicationWindow(HWND window) {
  HWND root = RootOwnerWindow(window);
  if (root == nullptr || IsShellOrTaskbarWindow(root)) return nullptr;

  const LONG_PTR extended_style = GetWindowLongPtrW(root, GWL_EXSTYLE);
  if ((extended_style & WS_EX_TOOLWINDOW) != 0 &&
      (extended_style & WS_EX_APPWINDOW) == 0) {
    HWND owner = GetWindow(root, GW_OWNER);
    owner = RootOwnerWindow(owner);
    if (owner == nullptr || IsShellOrTaskbarWindow(owner)) return nullptr;
    root = owner;
  }

  return IsWindow(root) ? root : nullptr;
}

bool IsKeyDown(DWORD virtual_key) {
  return (GetAsyncKeyState(static_cast<int>(virtual_key)) & 0x8000) != 0;
}

int ElapsedMilliseconds(const std::chrono::steady_clock::time_point& start,
                        const std::chrono::steady_clock::time_point& end) {
  const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
  return static_cast<int>(std::clamp<long long>(elapsed, 0, kMaxRecordedDelayMs));
}

std::string Utf8FromWide(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                                       nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

}  // namespace

MacroRecorder::MacroRecorder(HWND ignored_window)
    : ignored_window_(ignored_window) {}

MacroRecorder::~MacroRecorder() {
  Cancel();
}

bool MacroRecorder::Start() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (recording_ || hook_thread_.joinable()) return false;
    events_.clear();
    ready_ = false;
    hooks_installed_ = false;
    has_last_mouse_ = false;
    last_mouse_button_.clear();
    last_window_title_.clear();
    recording_ = true;
    hook_thread_ = std::thread(&MacroRecorder::HookThreadMain, this);
  }

  std::unique_lock<std::mutex> lock(mutex_);
  const bool signaled = ready_condition_.wait_for(
      lock, kHookStartupTimeout, [this] { return ready_; });
  const bool success = signaled && hooks_installed_;
  if (!success) {
    recording_ = false;
    lock.unlock();
    StopThread();
    std::lock_guard<std::mutex> reset_lock(mutex_);
    ready_ = false;
    hooks_installed_ = false;
  } else {
    lock.unlock();
  }
  return success;
}

flutter::EncodableList MacroRecorder::Stop() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    recording_ = false;
  }
  StopThread();

  std::vector<RecordedEvent> snapshot;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    snapshot = events_;
    events_.clear();
  }

  flutter::EncodableList result;
  result.reserve(snapshot.size());
  for (const auto& event : snapshot) {
    flutter::EncodableMap map;
    map[flutter::EncodableValue("type")] = flutter::EncodableValue(event.kind);
    map[flutter::EncodableValue("delayMs")] = static_cast<int32_t>(event.delay_ms);
    if (!event.window_title.empty()) {
      map[flutter::EncodableValue("window")] = flutter::EncodableValue(event.window_title);
      map[flutter::EncodableValue("targetWindow")] = flutter::EncodableValue(event.window_title);
    }
    if (event.window_changed) {
      map[flutter::EncodableValue("windowChanged")] = true;
      if (!event.previous_window_title.empty()) {
        map[flutter::EncodableValue("previousWindow")] =
            flutter::EncodableValue(event.previous_window_title);
      }
    }
    if (event.kind == "key") {
      map[flutter::EncodableValue("key")] = flutter::EncodableValue(event.key);
      if (!event.text.empty()) {
        map[flutter::EncodableValue("text")] = flutter::EncodableValue(event.text);
      }
      flutter::EncodableList modifiers;
      for (const auto& modifier : event.modifiers) {
        modifiers.push_back(flutter::EncodableValue(modifier));
      }
      map[flutter::EncodableValue("modifiers")] = flutter::EncodableValue(modifiers);
    } else if (event.kind == "mouse") {
      map[flutter::EncodableValue("x")] = static_cast<int32_t>(event.x);
      map[flutter::EncodableValue("y")] = static_cast<int32_t>(event.y);
      map[flutter::EncodableValue("button")] = flutter::EncodableValue(event.button);
      map[flutter::EncodableValue("doubleClick")] = event.double_click;
    }
    result.push_back(flutter::EncodableValue(map));
  }
  return result;
}

void MacroRecorder::Cancel() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    recording_ = false;
  }
  StopThread();
  std::lock_guard<std::mutex> lock(mutex_);
  events_.clear();
}

bool MacroRecorder::IsRecording() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return recording_ && hooks_installed_;
}

void MacroRecorder::StopThread() {
  DWORD thread_id = 0;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    thread_id = hook_thread_id_;
  }
  if (thread_id != 0) {
    PostThreadMessageW(thread_id, WM_QUIT, 0, 0);
  }
  if (hook_thread_.joinable()) {
    hook_thread_.join();
  }
  std::lock_guard<std::mutex> lock(mutex_);
  hook_thread_id_ = 0;
}

void MacroRecorder::HookThreadMain() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    hook_thread_id_ = GetCurrentThreadId();
    // Creating the message queue before installing low-level hooks avoids a
    // race when Stop() posts WM_QUIT immediately after Start().
    MSG message{};
    PeekMessageW(&message, nullptr, WM_USER, WM_USER, PM_NOREMOVE);
    keyboard_hook_ = SetWindowsHookExW(WH_KEYBOARD_LL, &MacroRecorder::KeyboardHookProc,
                                       GetModuleHandleW(nullptr), 0);
    mouse_hook_ = SetWindowsHookExW(WH_MOUSE_LL, &MacroRecorder::MouseHookProc,
                                    GetModuleHandleW(nullptr), 0);
    hooks_installed_ = keyboard_hook_ != nullptr && mouse_hook_ != nullptr;
    if (hooks_installed_) {
      active_recorder_.store(this);
    }
    if (!hooks_installed_) {
      if (keyboard_hook_ != nullptr) UnhookWindowsHookEx(keyboard_hook_);
      if (mouse_hook_ != nullptr) UnhookWindowsHookEx(mouse_hook_);
      keyboard_hook_ = nullptr;
      mouse_hook_ = nullptr;
      active_recorder_.store(nullptr);
    }
    ready_ = true;
  }
  ready_condition_.notify_one();

  if (!IsRecording()) return;

  MSG message{};
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }

  active_recorder_.store(nullptr);
  std::lock_guard<std::mutex> lock(mutex_);
  if (keyboard_hook_ != nullptr) UnhookWindowsHookEx(keyboard_hook_);
  if (mouse_hook_ != nullptr) UnhookWindowsHookEx(mouse_hook_);
  keyboard_hook_ = nullptr;
  mouse_hook_ = nullptr;
  hooks_installed_ = false;
  ready_ = false;
}

LRESULT CALLBACK MacroRecorder::KeyboardHookProc(int code, WPARAM wparam, LPARAM lparam) {
  MacroRecorder* recorder = active_recorder_.load();
  if (code >= 0 && recorder != nullptr && lparam != 0) {
    const auto* event = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
    if ((event->flags & LLKHF_INJECTED) == 0) {
      recorder->CaptureKeyboard(wparam, *event);
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

LRESULT CALLBACK MacroRecorder::MouseHookProc(int code, WPARAM wparam, LPARAM lparam) {
  MacroRecorder* recorder = active_recorder_.load();
  if (code >= 0 && recorder != nullptr && lparam != 0) {
    const auto* event = reinterpret_cast<const MSLLHOOKSTRUCT*>(lparam);
    if ((event->flags & LLMHF_INJECTED) == 0) {
      recorder->CaptureMouse(wparam, *event);
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

void MacroRecorder::CaptureKeyboard(WPARAM message, const KBDLLHOOKSTRUCT& event) {
  if (message != WM_KEYDOWN && message != WM_SYSKEYDOWN) return;
  if (IsModifierVirtualKey(event.vkCode)) return;
  if (IsIgnoredKeyboardEvent()) return;
  const std::string key = KeyNameFromVirtualKey(event.vkCode);
  if (key.empty()) return;

  RecordedEvent recorded;
  recorded.kind = "key";
  recorded.key = key;
  recorded.modifiers = CurrentModifiers();
  recorded.text = TextFromKeyEvent(event.vkCode, event.scanCode);
  recorded.window_title = ActiveWindowTitle();
  AppendEvent(std::move(recorded));
}

void MacroRecorder::CaptureMouse(WPARAM message, const MSLLHOOKSTRUCT& event) {
  const std::string button = MouseButtonFromMessage(message);
  if (button.empty()) return;
  const auto now = std::chrono::steady_clock::now();
  const POINT point = event.pt;
  if (IsIgnoredMousePoint(point)) return;

  std::lock_guard<std::mutex> lock(mutex_);
  if (!recording_) return;

  if (has_last_mouse_ && last_mouse_button_ == button && !events_.empty()) {
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - last_mouse_time_).count();
    const bool near_previous = std::abs(point.x - last_mouse_point_.x) <= kDoubleClickDistance &&
                               std::abs(point.y - last_mouse_point_.y) <= kDoubleClickDistance;
    if (elapsed <= kDoubleClickWindowMs && near_previous && events_.back().kind == "mouse") {
      events_.back().double_click = true;
      last_mouse_time_ = now;
      last_mouse_point_ = point;
      return;
    }
  }

  RecordedEvent recorded;
  recorded.kind = "mouse";
  recorded.x = point.x;
  recorded.window_title = ActiveWindowTitle();
  if (recorded.window_title.empty()) {
    recorded.window_title = WindowTitleAtPoint(point);
  }
  recorded.y = point.y;
  recorded.button = button;
  // Mouse events are appended here (rather than through AppendEvent), so
  // apply the same window-transition bookkeeping while mutex_ is held.
  if (!recorded.window_title.empty() &&
      recorded.window_title != last_window_title_) {
    recorded.window_changed = !last_window_title_.empty();
    recorded.previous_window_title = last_window_title_;
    last_window_title_ = recorded.window_title;
  }
  if (events_.empty()) {
    recorded.delay_ms = 0;
  } else {
    recorded.delay_ms = ElapsedMilliseconds(last_event_time_, now);
  }
  events_.push_back(std::move(recorded));
  last_event_time_ = now;
  last_mouse_time_ = now;
  last_mouse_point_ = point;
  last_mouse_button_ = button;
  has_last_mouse_ = true;
}

void MacroRecorder::AppendEvent(RecordedEvent event) {
  const auto now = std::chrono::steady_clock::now();
  std::lock_guard<std::mutex> lock(mutex_);
  if (!recording_) return;
  event.delay_ms = events_.empty() ? 0 : ElapsedMilliseconds(last_event_time_, now);
  if (!event.window_title.empty() && event.window_title != last_window_title_) {
    event.window_changed = !last_window_title_.empty();
    event.previous_window_title = last_window_title_;
    last_window_title_ = event.window_title;
  }
  events_.push_back(std::move(event));
  last_event_time_ = now;
  has_last_mouse_ = false;
}

std::string MacroRecorder::WindowTitleForHandle(HWND window) {
  window = StableApplicationWindow(window);
  if (window == nullptr) return {};
  wchar_t title[512]{};
  const int length = GetWindowTextW(
      window, title, static_cast<int>(sizeof(title) / sizeof(title[0])));
  if (length <= 0) return {};
  return Utf8FromWide(std::wstring(title, static_cast<size_t>(length)));
}

std::string MacroRecorder::WindowTitleAtPoint(POINT point) {
  return WindowTitleForHandle(WindowFromPoint(point));
}

std::string MacroRecorder::ActiveWindowTitle() {
  return WindowTitleForHandle(GetForegroundWindow());
}

bool MacroRecorder::IsIgnoredKeyboardEvent() const {
  const HWND foreground_window = StableApplicationWindow(GetForegroundWindow());
  const HWND ignored_window = StableApplicationWindow(ignored_window_);
  if (foreground_window == nullptr) return true;
  return ignored_window != nullptr && foreground_window == ignored_window;
}

bool MacroRecorder::IsIgnoredMousePoint(POINT point) const {
  const HWND hit_window = StableApplicationWindow(WindowFromPoint(point));
  const HWND ignored_window = StableApplicationWindow(ignored_window_);
  if (hit_window == nullptr) return true;
  return ignored_window != nullptr && hit_window == ignored_window;
}

bool MacroRecorder::IsModifierVirtualKey(DWORD virtual_key) {
  switch (virtual_key) {
    case VK_SHIFT:
    case VK_LSHIFT:
    case VK_RSHIFT:
    case VK_CONTROL:
    case VK_LCONTROL:
    case VK_RCONTROL:
    case VK_MENU:
    case VK_LMENU:
    case VK_RMENU:
    case VK_LWIN:
    case VK_RWIN:
      return true;
    default:
      return false;
  }
}

std::vector<std::string> MacroRecorder::CurrentModifiers() {
  std::vector<std::string> modifiers;
  if (IsKeyDown(VK_CONTROL)) modifiers.push_back("CTRL");
  if (IsKeyDown(VK_MENU)) modifiers.push_back("ALT");
  if (IsKeyDown(VK_SHIFT)) modifiers.push_back("SHIFT");
  if (IsKeyDown(VK_LWIN) || IsKeyDown(VK_RWIN)) modifiers.push_back("WIN");
  return modifiers;
}

std::string MacroRecorder::MouseButtonFromMessage(WPARAM message) {
  switch (message) {
    case WM_LBUTTONDOWN:
      return "left";
    case WM_RBUTTONDOWN:
      return "right";
    case WM_MBUTTONDOWN:
      return "middle";
    default:
      return {};
  }
}

std::string MacroRecorder::TextFromKeyEvent(DWORD virtual_key, DWORD scan_code) {
  // Modifier shortcuts are commands, not text. Ctrl+Alt is intentionally
  // allowed because Windows commonly uses it as AltGr for Arabic and other
  // keyboard layouts.
  const bool control_down = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
  const bool alt_down = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
  const bool win_down = (GetAsyncKeyState(VK_LWIN) & 0x8000) != 0 ||
                        (GetAsyncKeyState(VK_RWIN) & 0x8000) != 0;
  if (win_down || (control_down && !alt_down) || (alt_down && !control_down)) {
    return {};
  }

  BYTE keyboard_state[256]{};
  if (!GetKeyboardState(keyboard_state)) return {};
  // The low-level hook runs before the normal keyboard message reaches a
  // target queue. Synchronize modifier state from the system and include the
  // current key explicitly so Shift/Caps Lock/AltGr are translated correctly.
  const int modifier_keys[] = {
      VK_SHIFT, VK_LSHIFT, VK_RSHIFT, VK_CONTROL, VK_LCONTROL, VK_RCONTROL,
      VK_MENU, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN,
  };
  for (const int modifier_key : modifier_keys) {
    if ((GetAsyncKeyState(modifier_key) & 0x8000) != 0) {
      keyboard_state[modifier_key] |= 0x80;
    } else {
      keyboard_state[modifier_key] &= static_cast<BYTE>(~0x80);
    }
  }
  if (virtual_key < 256) keyboard_state[virtual_key] |= 0x80;

  const HWND foreground = GetForegroundWindow();
  const DWORD target_thread = foreground == nullptr
      ? 0
      : GetWindowThreadProcessId(foreground, nullptr);
  const HKL layout = GetKeyboardLayout(target_thread);
  if (layout == nullptr) return {};

  wchar_t output[8]{};
  const int length = ToUnicodeEx(
      virtual_key, scan_code, keyboard_state, output,
      static_cast<int>(sizeof(output) / sizeof(output[0])), 0, layout);
  if (length <= 0) return {};  // dead key or non-character key

  for (int index = 0; index < length; ++index) {
    if (std::iswcntrl(output[index])) return {};
  }
  return Utf8FromWide(std::wstring(output, static_cast<size_t>(length)));
}

std::string MacroRecorder::KeyNameFromVirtualKey(DWORD virtual_key) {
  if (virtual_key >= 'A' && virtual_key <= 'Z') return std::string(1, static_cast<char>(virtual_key));
  if (virtual_key >= '0' && virtual_key <= '9') return std::string(1, static_cast<char>(virtual_key));
  if (virtual_key >= VK_NUMPAD0 && virtual_key <= VK_NUMPAD9) {
    return std::string(1, static_cast<char>('0' + (virtual_key - VK_NUMPAD0)));
  }
  if (virtual_key >= VK_F1 && virtual_key <= VK_F24) return "F" + std::to_string(virtual_key - VK_F1 + 1);

  static const std::map<DWORD, std::string> names = {
      {VK_RETURN, "ENTER"}, {VK_TAB, "TAB"}, {VK_ESCAPE, "ESC"},
      {VK_SPACE, "SPACE"}, {VK_BACK, "BACKSPACE"}, {VK_DELETE, "DELETE"},
      {VK_INSERT, "INSERT"}, {VK_HOME, "HOME"}, {VK_END, "END"},
      {VK_PRIOR, "PAGEUP"}, {VK_NEXT, "PAGEDOWN"}, {VK_LEFT, "LEFT"},
      {VK_RIGHT, "RIGHT"}, {VK_UP, "UP"}, {VK_DOWN, "DOWN"},
      {VK_CAPITAL, "CAPSLOCK"}, {VK_NUMLOCK, "NUMLOCK"}, {VK_SCROLL, "SCROLLLOCK"},
      {VK_SNAPSHOT, "PRINTSCREEN"}, {VK_PAUSE, "PAUSE"},
      {VK_OEM_3, "`"}, {VK_OEM_MINUS, "-"}, {VK_OEM_PLUS, "="},
      {VK_OEM_4, "["}, {VK_OEM_6, "]"}, {VK_OEM_5, "\\"},
      {VK_OEM_1, ";"}, {VK_OEM_7, "'"}, {VK_OEM_COMMA, ","},
      {VK_OEM_PERIOD, "."}, {VK_OEM_2, "/"},
  };
  const auto found = names.find(virtual_key);
  return found == names.end() ? std::string{} : found->second;
}

