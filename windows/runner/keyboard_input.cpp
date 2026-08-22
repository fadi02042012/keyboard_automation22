#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "keyboard_input.h"
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <map>
#include <string>
#include <unordered_set>
#include <vector>

namespace {

std::string NormalizeKey(std::string key) {
  std::transform(key.begin(), key.end(), key.begin(),
                 [](unsigned char value) { return static_cast<char>(std::toupper(value)); });
  return key;
}

WORD GetVirtualKeyCode(const std::string& raw_key) {
  const std::string key = NormalizeKey(raw_key);
  static const std::map<std::string, WORD> key_map = {
      {"A", 'A'}, {"B", 'B'}, {"C", 'C'}, {"D", 'D'}, {"E", 'E'},
      {"F", 'F'}, {"G", 'G'}, {"H", 'H'}, {"I", 'I'}, {"J", 'J'},
      {"K", 'K'}, {"L", 'L'}, {"M", 'M'}, {"N", 'N'}, {"O", 'O'},
      {"P", 'P'}, {"Q", 'Q'}, {"R", 'R'}, {"S", 'S'}, {"T", 'T'},
      {"U", 'U'}, {"V", 'V'}, {"W", 'W'}, {"X", 'X'}, {"Y", 'Y'},
      {"Z", 'Z'}, {"0", '0'}, {"1", '1'}, {"2", '2'}, {"3", '3'},
      {"4", '4'}, {"5", '5'}, {"6", '6'}, {"7", '7'}, {"8", '8'},
      {"9", '9'}, {"ENTER", VK_RETURN}, {"RETURN", VK_RETURN},
      {"TAB", VK_TAB}, {"ESC", VK_ESCAPE}, {"ESCAPE", VK_ESCAPE},
      {"SPACE", VK_SPACE}, {"BACKSPACE", VK_BACK}, {"DELETE", VK_DELETE},
      {"INSERT", VK_INSERT}, {"HOME", VK_HOME}, {"END", VK_END},
      {"PAGEUP", VK_PRIOR}, {"PAGEDOWN", VK_NEXT}, {"PGUP", VK_PRIOR},
      {"PGDN", VK_NEXT}, {"LEFT", VK_LEFT}, {"RIGHT", VK_RIGHT},
      {"UP", VK_UP}, {"DOWN", VK_DOWN}, {"PRINTSCREEN", VK_SNAPSHOT},
      {"PAUSE", VK_PAUSE}, {"CAPSLOCK", VK_CAPITAL}, {"NUMLOCK", VK_NUMLOCK},
      {"SCROLLLOCK", VK_SCROLL}, {"`", VK_OEM_3}, {"-", VK_OEM_MINUS},
      {"=", VK_OEM_PLUS}, {"[", VK_OEM_4}, {"]", VK_OEM_6},
      {"\\", VK_OEM_5}, {";", VK_OEM_1}, {"'", VK_OEM_7},
      {",", VK_OEM_COMMA}, {".", VK_OEM_PERIOD}, {"/", VK_OEM_2},
      {"F1", VK_F1}, {"F2", VK_F2}, {"F3", VK_F3}, {"F4", VK_F4},
      {"F5", VK_F5}, {"F6", VK_F6}, {"F7", VK_F7}, {"F8", VK_F8},
      {"F9", VK_F9}, {"F10", VK_F10}, {"F11", VK_F11}, {"F12", VK_F12},
      {"F13", VK_F13}, {"F14", VK_F14}, {"F15", VK_F15}, {"F16", VK_F16},
      {"F17", VK_F17}, {"F18", VK_F18}, {"F19", VK_F19}, {"F20", VK_F20},
      {"F21", VK_F21}, {"F22", VK_F22}, {"F23", VK_F23}, {"F24", VK_F24},
  };
  const auto found = key_map.find(key);
  return found == key_map.end() ? 0 : found->second;
}

bool IsExtendedKey(WORD key) {
  switch (key) {
    case VK_INSERT:
    case VK_DELETE:
    case VK_HOME:
    case VK_END:
    case VK_PRIOR:
    case VK_NEXT:
    case VK_LEFT:
    case VK_RIGHT:
    case VK_UP:
    case VK_DOWN:
    case VK_DIVIDE:
    case VK_NUMLOCK:
    case VK_SNAPSHOT:
      return true;
    default:
      return false;
  }
}

bool ModifierKey(const std::string& raw_modifier, WORD* key) {
  std::string modifier = NormalizeKey(raw_modifier);
  if (modifier == "CTRL" || modifier == "CONTROL") {
    *key = VK_LCONTROL;
  } else if (modifier == "ALT") {
    *key = VK_LMENU;
  } else if (modifier == "SHIFT") {
    *key = VK_LSHIFT;
  } else if (modifier == "WIN" || modifier == "WINDOWS" || modifier == "META") {
    *key = VK_LWIN;
  } else {
    return false;
  }
  return true;
}

INPUT KeyboardEvent(WORD key, bool key_up) {
  INPUT input{};
  input.type = INPUT_KEYBOARD;
  input.ki.wVk = key;
  input.ki.dwFlags = (key_up ? KEYEVENTF_KEYUP : 0) |
                     (IsExtendedKey(key) ? KEYEVENTF_EXTENDEDKEY : 0);
  return input;
}

}  // namespace

std::wstring StringToWString(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       value.data(), static_cast<int>(value.size()),
                                       nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

bool KeyboardInput::SendText(const std::wstring& text) {
  if (text.empty()) return true;
  constexpr size_t kBatchSize = 64;
  for (size_t offset = 0; offset < text.size(); offset += kBatchSize) {
    const size_t count = std::min(kBatchSize, text.size() - offset);
    std::vector<INPUT> inputs;
    inputs.reserve(count * 2);
    for (size_t index = 0; index < count; ++index) {
      INPUT down{};
      down.type = INPUT_KEYBOARD;
      down.ki.wScan = text[offset + index];
      down.ki.dwFlags = KEYEVENTF_UNICODE;
      inputs.push_back(down);
      INPUT up = down;
      up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
      inputs.push_back(up);
    }
    if (SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT)) != inputs.size()) {
      return false;
    }
  }
  return true;
}

bool KeyboardInput::SendKey(const std::string& raw_key,
                             const std::vector<std::string>& modifiers) {
  const WORD key = GetVirtualKeyCode(raw_key);
  if (key == 0) return false;

  std::vector<WORD> modifier_keys;
  std::unordered_set<WORD> seen;
  modifier_keys.reserve(modifiers.size());
  for (const auto& modifier : modifiers) {
    WORD modifier_key = 0;
    if (!ModifierKey(modifier, &modifier_key) || modifier_key == 0 ||
        !seen.insert(modifier_key).second) {
      return false;
    }
    modifier_keys.push_back(modifier_key);
  }

  std::vector<INPUT> inputs;
  inputs.reserve(modifier_keys.size() * 2 + 2);
  for (const WORD modifier : modifier_keys) inputs.push_back(KeyboardEvent(modifier, false));
  inputs.push_back(KeyboardEvent(key, false));
  inputs.push_back(KeyboardEvent(key, true));
  for (auto it = modifier_keys.rbegin(); it != modifier_keys.rend(); ++it) {
    inputs.push_back(KeyboardEvent(*it, true));
  }

  return SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT)) == inputs.size();
}

void KeyboardInput::KeyDown(const std::string& key) {
  const WORD virtual_key = GetVirtualKeyCode(key);
  if (virtual_key == 0) return;
  INPUT input = KeyboardEvent(virtual_key, false);
  SendInput(1, &input, sizeof(INPUT));
}

void KeyboardInput::KeyUp(const std::string& key) {
  const WORD virtual_key = GetVirtualKeyCode(key);
  if (virtual_key == 0) return;
  INPUT input = KeyboardEvent(virtual_key, true);
  SendInput(1, &input, sizeof(INPUT));
}
