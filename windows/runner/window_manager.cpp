#include "window_manager.h"

#include <psapi.h>

#include <string>
#include <algorithm>
#include <utility>
#include <vector>
#include <map>

#pragma comment(lib, "psapi.lib")

namespace {

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

bool IsShellOrPopupClass(const std::wstring& class_name) {
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

bool IsUsableApplicationWindow(HWND window) {
  if (window == nullptr || !IsWindow(window) || !IsWindowVisible(window)) {
    return false;
  }

  // Keep the actual visible top-level window. A modal dialog such as the HP
  // scanner selector is often an owned window; replacing it with GA_ROOTOWNER
  // loses its title and makes playback unable to find the recorded dialog.
  const std::wstring class_name = WindowClassName(window);
  if (IsShellOrPopupClass(class_name)) return false;

  // A shell-owned popup can still be returned by EnumWindows through an owner;
  // reject it without rejecting ordinary application dialogs.
  const HWND root = RootOwnerWindow(window);
  if (root != window && IsShellOrPopupClass(WindowClassName(root))) return false;

  wchar_t title[2]{};
  return GetWindowTextW(window, title, 2) > 0;
}

bool SetForegroundReliable(HWND window) {
  if (window == nullptr || !IsWindow(window) || !IsWindowVisible(window)) return false;

  const DWORD current_thread = GetCurrentThreadId();
  const DWORD target_thread = GetWindowThreadProcessId(window, nullptr);
  bool attached = false;
  if (target_thread != 0 && target_thread != current_thread) {
    attached = AttachThreadInput(current_thread, target_thread, TRUE) != FALSE;
  }

  // Modal dialogs can reject the first foreground request while their owner is
  // completing a transition. Retry briefly instead of reporting a false
  // activation failure to Dart.
  bool foreground = false;
  for (int attempt = 0; attempt < 3; ++attempt) {
    if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
    BringWindowToTop(window);
    SetForegroundWindow(window);
    SetFocus(window);
    foreground = GetForegroundWindow() == window;
    if (foreground) break;
    Sleep(50);
  }

  if (attached) AttachThreadInput(current_thread, target_thread, FALSE);
  return foreground;
}

}  // namespace

#pragma comment(lib, "psapi.lib")

namespace {

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                                       value.data(), static_cast<int>(value.size()),
                                       nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

std::string ProcessName(HWND hwnd) {
  DWORD process_id = 0;
  GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == 0) return {};

  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,
                                FALSE, process_id);
  if (process == nullptr) return {};

  wchar_t name[MAX_PATH] = L"";
  DWORD name_length = MAX_PATH;
  const BOOL ok = QueryFullProcessImageNameW(process, 0, name, &name_length);
  CloseHandle(process);
  if (!ok) return {};

  const std::wstring path(name, name_length);
  const size_t separator = path.find_last_of(L"\\/");
  return WideToUtf8(separator == std::wstring::npos ? path : path.substr(separator + 1));
}

WindowInfo ReadWindowInfo(HWND hwnd) {
  wchar_t title[512] = L"";
  const int length = GetWindowTextW(hwnd, title, static_cast<int>(sizeof(title) / sizeof(title[0])));
  WindowInfo info;
  info.hwnd = hwnd;
  info.isActive = GetForegroundWindow() == hwnd;
  if (length > 0) info.title = WideToUtf8(std::wstring(title, length));
  info.processName = ProcessName(hwnd);
  return info;
}

BOOL CALLBACK EnumWindowsProc(HWND hwnd, LPARAM lparam) {
  if (!IsUsableApplicationWindow(hwnd)) return TRUE;
  auto* windows = reinterpret_cast<std::vector<WindowInfo>*>(lparam);
  WindowInfo info = ReadWindowInfo(hwnd);
  if (!info.title.empty()) windows->push_back(std::move(info));
  return TRUE;
}

std::string RemoveUnicodeDirectionMarks(std::string value) {
  static const std::vector<std::string> marks = {
      "\xE2\x80\x8E", "\xE2\x80\x8F", "\xE2\x80\AA", "\xE2\x80\AB",
      "\xE2\x80\AC", "\xE2\x80\AD", "\xE2\x80\AE", "\xE2\x81\xA6",
      "\xE2\x81\xA7", "\xE2\x81\xA8", "\xE2\x81\xA9"};
  for (const auto& mark : marks) {
    size_t position = 0;
    while ((position = value.find(mark, position)) != std::string::npos) {
      value.erase(position, mark.size());
    }
  }
  return value;
}

std::string LowerAscii(std::string value) {
  value = RemoveUnicodeDirectionMarks(std::move(value));
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
    if (character >= 'A' && character <= 'Z') {
      return static_cast<char>(character - 'A' + 'a');
    }
    return static_cast<char>(character);
  });
  return value;
}

std::string MeaningfulTitleFragment(const std::string& value) {
  const std::string normalized = RemoveUnicodeDirectionMarks(value);
  const size_t open = normalized.find_last_of('[');
  const size_t close = normalized.find_last_of(']');
  if (open != std::string::npos && close != std::string::npos && open < close) {
    const std::string fragment = normalized.substr(open + 1, close - open - 1);
    if (fragment.size() >= 3) return fragment;
  }
  return normalized;
}

int TitleMatchScore(const std::string& actual, const std::string& requested) {
  const std::string actual_lower = LowerAscii(actual);
  const std::string requested_lower = LowerAscii(MeaningfulTitleFragment(requested));
  if (actual_lower.empty() || requested_lower.size() < 3) return 0;
  if (actual_lower == requested_lower) return 10000;
  if (actual_lower.find(requested_lower) != std::string::npos) {
    return 7000 + static_cast<int>(requested_lower.size());
  }
  if (requested_lower.find(actual_lower) != std::string::npos) {
    return 6000 + static_cast<int>(actual_lower.size());
  }
  return 0;
}

std::map<std::string, HWND> g_window_affinity;
std::map<std::string, HWND> g_process_affinity;

std::string ProcessAliasForTitle(const std::string& requested) {
  const std::string title = LowerAscii(requested);
  if (title.find("google chrome") != std::string::npos ||
      title.find("chrome") != std::string::npos) {
    return "chrome.exe";
  }
  if (title.find("microsoft edge") != std::string::npos ||
      title.find("edge") != std::string::npos) {
    return "msedge.exe";
  }
  if (title.find("firefox") != std::string::npos) return "firefox.exe";
  if (title.find("brave") != std::string::npos) return "brave.exe";
  return {};
}

int ProcessMatchScore(const WindowInfo& window, const std::string& requested) {
  const std::string alias = ProcessAliasForTitle(requested);
  if (alias.empty()) return 0;
  const std::string process = LowerAscii(window.processName);
  if (process == alias) return 5000;
  if (process.find(alias) != std::string::npos) return 4500;
  return 0;
}

}  // namespace

std::vector<WindowInfo> GetOpenWindows() {
  std::vector<WindowInfo> windows;
  EnumWindows(EnumWindowsProc, reinterpret_cast<LPARAM>(&windows));
  return windows;
}

WindowInfo GetActiveWindowInfo() {
  const HWND hwnd = GetForegroundWindow();
  if (hwnd == nullptr || !IsUsableApplicationWindow(hwnd)) {
    return WindowInfo{};
  }
  return ReadWindowInfo(hwnd);
}

bool WindowTitlesMatch(const std::string& actual_title, const std::string& requested_title) {
  return TitleMatchScore(actual_title, requested_title) > 0;
}

bool ActivateWindowByTitle(const std::string& target_title) {
  if (target_title.empty()) return false;

  // Keep runtime affinity so a browser window can continue to be targeted
  // after its title changes, e.g. New Tab -> a website title.
  const auto affinity = g_window_affinity.find(target_title);
  if (affinity != g_window_affinity.end()) {
    const HWND cached = affinity->second;
    if (IsUsableApplicationWindow(cached)) {
      if (SetForegroundReliable(cached)) return true;
    } else {
      g_window_affinity.erase(affinity);
    }
  }

  const auto windows = GetOpenWindows();

  // Prefer the last browser HWND when its title has changed.
  const std::string process_alias = ProcessAliasForTitle(target_title);
  if (!process_alias.empty()) {
    const auto process_affinity = g_process_affinity.find(process_alias);
    if (process_affinity != g_process_affinity.end()) {
      const HWND cached = process_affinity->second;
      if (IsUsableApplicationWindow(cached) && SetForegroundReliable(cached)) {
        g_window_affinity[target_title] = cached;
        return true;
      }
      g_process_affinity.erase(process_affinity);
    }
  }

  const WindowInfo* best_match = nullptr;
  int best_score = 0;
  for (const auto& window : windows) {
    const int title_score = TitleMatchScore(window.title, target_title);
    const int process_score = ProcessMatchScore(window, target_title);
    // Prefer a reliable title match. Use the process alias only when the
    // recorded tab title is no longer present in the current window title.
    const int score = title_score > 0 ? title_score : process_score;
    if (score > best_score) {
      best_score = score;
      best_match = &window;
    }
  }
  if (best_match == nullptr || best_match->hwnd == nullptr) return false;

  const HWND hwnd = best_match->hwnd;
  g_window_affinity[target_title] = hwnd;
  const std::string matched_alias = ProcessAliasForTitle(target_title);
  if (!matched_alias.empty()) g_process_affinity[matched_alias] = hwnd;
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else {
    ShowWindow(hwnd, SW_SHOW);
  }
  return SetForegroundReliable(hwnd);
}
