#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "automation_engine.h"
#include "keyboard_input.h"
#include "mouse_input.h"
#include "macro_recorder.h"
#include "ui_automation.h"
#include <windows.h>

#include <cmath>
#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <vector>

namespace {

using EncodableMap = flutter::EncodableMap;
using EncodableValue = flutter::EncodableValue;

const EncodableMap* ArgumentsOf(
    const flutter::MethodCall<EncodableValue>& call) {
  return std::get_if<EncodableMap>(call.arguments());
}

bool ReadString(const EncodableMap& args, const char* name, std::string* value) {
  const auto it = args.find(EncodableValue(name));
  if (it == args.end()) return false;
  const auto* result = std::get_if<std::string>(&it->second);
  if (result == nullptr) return false;
  *value = *result;
  return true;
}

bool ReadInt(const EncodableMap& args, const char* name, int* value) {
  const auto it = args.find(EncodableValue(name));
  if (it == args.end()) return false;
  int64_t parsed = 0;
  if (const auto* number = std::get_if<int32_t>(&it->second)) {
    parsed = *number;
  } else if (const auto* number64 = std::get_if<int64_t>(&it->second)) {
    parsed = *number64;
  } else if (const auto* decimal = std::get_if<double>(&it->second)) {
    if (!std::isfinite(*decimal) ||
        *decimal < std::numeric_limits<int>::min() ||
        *decimal > std::numeric_limits<int>::max()) {
      return false;
    }
    parsed = static_cast<int64_t>(*decimal);
  } else {
    return false;
  }
  if (parsed < std::numeric_limits<int>::min() ||
      parsed > std::numeric_limits<int>::max()) {
    return false;
  }
  *value = static_cast<int>(parsed);
  return true;
}

bool ReadBool(const EncodableMap& args, const char* name, bool fallback) {
  const auto it = args.find(EncodableValue(name));
  if (it == args.end()) return fallback;
  if (const auto* value = std::get_if<bool>(&it->second)) return *value;
  return fallback;
}

bool ReadModifiers(const EncodableMap& args,
                   std::vector<std::string>* modifiers) {
  const auto it = args.find(EncodableValue("modifiers"));
  if (it == args.end()) return true;
  const auto* list = std::get_if<flutter::EncodableList>(&it->second);
  if (list == nullptr) return false;
  for (const auto& item : *list) {
    const auto* modifier = std::get_if<std::string>(&item);
    if (modifier == nullptr) return false;
    modifiers->push_back(*modifier);
  }
  return true;
}

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

std::optional<std::string> ReadClipboardText() {
  if (!OpenClipboard(nullptr)) return std::nullopt;
  struct ClipboardGuard {
    ~ClipboardGuard() { CloseClipboard(); }
  } guard;

  if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) return std::nullopt;
  const HANDLE handle = GetClipboardData(CF_UNICODETEXT);
  if (handle == nullptr) return std::nullopt;
  const auto* data = static_cast<const wchar_t*>(GlobalLock(handle));
  if (data == nullptr) return std::nullopt;
  const std::wstring text(data);
  GlobalUnlock(handle);
  return WideToUtf8(text);
}

}  // namespace

AutomationEngine::AutomationEngine(HWND ignored_window)
    : macro_recorder_(ignored_window) {}

void AutomationEngine::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments = ArgumentsOf(call);

  if (call.method_name() == "get_clipboard") {
    const auto text = ReadClipboardText();
    result->Success(EncodableValue(text.value_or(std::string{})));
    return;
  }

  if (call.method_name() == "start_macro_recording") {
    result->Success(EncodableValue(macro_recorder_.Start()));
    return;
  }

  if (call.method_name() == "stop_macro_recording") {
    // Return a self-describing payload so Dart can distinguish an empty
    // recording from a codec/type mismatch while remaining backward-compatible
    // with the event list stored under `events`.
    const auto events = macro_recorder_.Stop();
    EncodableMap payload;
    payload[EncodableValue("events")] = EncodableValue(events);
    payload[EncodableValue("count")] = static_cast<int32_t>(events.size());
    result->Success(EncodableValue(payload));
    return;
  }

  if (call.method_name() == "cancel_macro_recording") {
    macro_recorder_.Cancel();
    result->Success(EncodableValue(true));
    return;
  }

  if (call.method_name() == "is_macro_recording") {
    result->Success(EncodableValue(macro_recorder_.IsRecording()));
    return;
  }

  // Reading the cursor position is a no-argument operation. Handle it before
  // validating the optional argument map so older Dart callers that pass null
  // remain compatible with the Windows runner.
  if (call.method_name() == "get_mouse_position") {
    const POINT point = MouseInput::GetPosition();
    EncodableMap map;
    map[EncodableValue("x")] = static_cast<int32_t>(point.x);
    map[EncodableValue("y")] = static_cast<int32_t>(point.y);
    result->Success(EncodableValue(map));
    return;
  }

  if (arguments == nullptr) {
    result->Error("INVALID_ARGUMENTS", "Expected a map of arguments.");
    return;
  }

  if (call.method_name() == "ui_inspect_elements") {
    std::string window_title;
    if (!ReadString(*arguments, "windowTitle", &window_title) || window_title.empty()) {
      result->Error("MISSING_WINDOW_TITLE", "windowTitle must be a non-empty string.");
      return;
    }
    int max_depth = 4;
    int max_elements = 200;
    ReadInt(*arguments, "maxDepth", &max_depth);
    ReadInt(*arguments, "maxElements", &max_elements);
    std::string error;
    const auto elements = UiAutomation::InspectElements(
        window_title, max_depth, max_elements, &error);
    if (!error.empty()) {
      result->Error("UI_AUTOMATION_FAILED", error);
      return;
    }
    result->Success(EncodableValue(elements));
    return;
  }

  if (call.method_name() == "ui_execute_command") {
    std::string window_title;
    std::string command;
    if (!ReadString(*arguments, "windowTitle", &window_title) || window_title.empty() ||
        !ReadString(*arguments, "command", &command) || command.empty()) {
      result->Error("INVALID_UI_COMMAND", "windowTitle and command are required.");
      return;
    }
    std::string error;
    if (!UiAutomation::ExecuteCommand(window_title, command, *arguments, &error)) {
      result->Error("UI_AUTOMATION_COMMAND_FAILED", error);
      return;
    }
    result->Success(EncodableValue(true));
    return;
  }

  if (call.method_name() == "text") {
    std::string text;
    if (!ReadString(*arguments, "text", &text)) {
      result->Error("MISSING_TEXT", "The text argument must be a string.");
      return;
    }
    const std::wstring wide_text = StringToWString(text);
    if (!text.empty() && wide_text.empty()) {
      result->Error("INVALID_UTF8", "The text is not valid UTF-8.");
      return;
    }
    if (!KeyboardInput::SendText(wide_text)) {
      result->Error("SEND_TEXT_FAILED", "Windows rejected the text input.");
      return;
    }
    result->Success(EncodableValue(true));
    return;
  }

  if (call.method_name() == "key") {
    std::string key;
    if (!ReadString(*arguments, "key", &key) || key.empty()) {
      result->Error("MISSING_KEY", "The key argument must be a non-empty string.");
      return;
    }
    std::vector<std::string> modifiers;
    if (!ReadModifiers(*arguments, &modifiers)) {
      result->Error("INVALID_MODIFIERS", "Modifiers must be a string list.");
      return;
    }
    if (!KeyboardInput::SendKey(key, modifiers)) {
      result->Error("SEND_KEY_FAILED", "Windows rejected the keyboard input.");
      return;
    }
    result->Success(EncodableValue(true));
    return;
  }

  if (call.method_name() == "mouse_click") {
    int x = 0;
    int y = 0;
    if (!ReadInt(*arguments, "x", &x) || !ReadInt(*arguments, "y", &y)) {
      result->Error("MISSING_COORDINATES", "Coordinates must be integers.");
      return;
    }
    std::string button = "left";
    if (arguments->find(EncodableValue("button")) != arguments->end() &&
        !ReadString(*arguments, "button", &button)) {
      result->Error("INVALID_BUTTON", "Button must be left, right, or middle.");
      return;
    }
    const bool double_click = ReadBool(*arguments, "double_click", false);
    if (!MouseInput::Click(x, y, button, double_click)) {
      result->Error("MOUSE_CLICK_FAILED", "Windows rejected the mouse input.");
      return;
    }
    result->Success(EncodableValue(true));
    return;
  }

  result->NotImplemented();
}
