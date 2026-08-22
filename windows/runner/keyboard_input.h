#ifndef KEYBOARD_INPUT_H_
#define KEYBOARD_INPUT_H_

#include <windows.h>
#include <string>
#include <vector>

std::wstring StringToWString(const std::string& str);

class KeyboardInput {
 public:
  static bool SendText(const std::wstring& text);
  static bool SendKey(const std::string& key, const std::vector<std::string>& modifiers);
  static void KeyDown(const std::string& key);
  static void KeyUp(const std::string& key);
};

#endif