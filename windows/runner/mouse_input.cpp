#include "mouse_input.h"

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <string>

namespace {

std::string NormalizeButton(std::string button) {
  std::transform(button.begin(), button.end(), button.begin(),
                 [](unsigned char value) {
                   return static_cast<char>(std::tolower(value));
                 });
  const auto first = button.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) return {};
  const auto last = button.find_last_not_of(" \t\r\n");
  return button.substr(first, last - first + 1);
}

DWORD ButtonDownFlag(const std::string& raw_button) {
  const std::string button = NormalizeButton(raw_button);
  if (button == "left") return MOUSEEVENTF_LEFTDOWN;
  if (button == "right") return MOUSEEVENTF_RIGHTDOWN;
  if (button == "middle") return MOUSEEVENTF_MIDDLEDOWN;
  return 0;
}

DWORD ButtonUpFlag(const std::string& raw_button) {
  const std::string button = NormalizeButton(raw_button);
  if (button == "left") return MOUSEEVENTF_LEFTUP;
  if (button == "right") return MOUSEEVENTF_RIGHTUP;
  if (button == "middle") return MOUSEEVENTF_MIDDLEUP;
  return 0;
}

bool SendMouseEvent(DWORD flags) {
  INPUT input{};
  input.type = INPUT_MOUSE;
  input.mi.dwFlags = flags;
  return SendInput(1, &input, sizeof(INPUT)) == 1;
}

}  // namespace

bool MouseInput::Click(int x, int y, const std::string& button, bool double_click) {
  const DWORD down = ButtonDownFlag(button);
  const DWORD up = ButtonUpFlag(button);
  if (down == 0 || up == 0) return false;
  if (!SetCursorPos(x, y)) return false;
  if (!SendMouseEvent(down) || !SendMouseEvent(up)) return false;
  if (double_click) {
    Sleep(80);
    if (!SendMouseEvent(down) || !SendMouseEvent(up)) return false;
  }
  return true;
}

void MouseInput::Move(int x, int y) {
  SetCursorPos(x, y);
}

void MouseInput::Down(const std::string& button) {
  const DWORD flag = ButtonDownFlag(button);
  if (flag != 0) SendMouseEvent(flag);
}

void MouseInput::Up(const std::string& button) {
  const DWORD flag = ButtonUpFlag(button);
  if (flag != 0) SendMouseEvent(flag);
}

POINT MouseInput::GetPosition() {
  POINT point{};
  GetCursorPos(&point);
  return point;
}
