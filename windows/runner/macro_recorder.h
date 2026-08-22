#ifndef MACRO_RECORDER_H_
#define MACRO_RECORDER_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <flutter/standard_method_codec.h>

class MacroRecorder {
 public:
  explicit MacroRecorder(HWND ignored_window = nullptr);
  ~MacroRecorder();

  MacroRecorder(const MacroRecorder&) = delete;
  MacroRecorder& operator=(const MacroRecorder&) = delete;

  bool Start();
  flutter::EncodableList Stop();
  void Cancel();
  bool IsRecording() const;

 private:
  struct RecordedEvent {
    std::string kind;
    std::string key;
    // The character produced by this key under the active Windows layout.
    // It is optional so legacy key events remain fully backward-compatible.
    std::string text;
    std::vector<std::string> modifiers;
    int x = 0;
    int y = 0;
    std::string button;
    std::string window_title;
    std::string previous_window_title;
    bool window_changed = false;
    bool double_click = false;
    int delay_ms = 0;
  };

  static LRESULT CALLBACK KeyboardHookProc(int code, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK MouseHookProc(int code, WPARAM wparam, LPARAM lparam);

  void HookThreadMain();
  void CaptureKeyboard(WPARAM message, const KBDLLHOOKSTRUCT& event);
  void CaptureMouse(WPARAM message, const MSLLHOOKSTRUCT& event);
  void AppendEvent(RecordedEvent event);
  void StopThread();
  bool IsIgnoredKeyboardEvent() const;
  bool IsIgnoredMousePoint(POINT point) const;

  static std::string KeyNameFromVirtualKey(DWORD virtual_key);
  static std::string TextFromKeyEvent(DWORD virtual_key, DWORD scan_code);
  static std::string ActiveWindowTitle();
  static std::string WindowTitleAtPoint(POINT point);
  static std::string WindowTitleForHandle(HWND window);
  static bool IsModifierVirtualKey(DWORD virtual_key);
  static std::vector<std::string> CurrentModifiers();
  static std::string MouseButtonFromMessage(WPARAM message);

  HWND ignored_window_ = nullptr;
  mutable std::mutex mutex_;
  std::condition_variable ready_condition_;
  std::thread hook_thread_;
  DWORD hook_thread_id_ = 0;
  HHOOK keyboard_hook_ = nullptr;
  HHOOK mouse_hook_ = nullptr;
  bool ready_ = false;
  bool hooks_installed_ = false;
  bool recording_ = false;
  std::vector<RecordedEvent> events_;
  std::chrono::steady_clock::time_point last_event_time_{};
  bool has_last_mouse_ = false;
  std::chrono::steady_clock::time_point last_mouse_time_{};
  POINT last_mouse_point_{};
  std::string last_mouse_button_;
  std::string last_window_title_;

  static std::atomic<MacroRecorder*> active_recorder_;
};

#endif  // MACRO_RECORDER_H_

