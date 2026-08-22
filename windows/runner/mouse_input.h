#ifndef MOUSE_INPUT_H_
#define MOUSE_INPUT_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#include <string>

class MouseInput {
 public:
  static bool Click(int x, int y, const std::string& button, bool doubleClick);
  static void Move(int x, int y);
  static void Down(const std::string& button);
  static void Up(const std::string& button);
  
  // NEW: دالة للحصول على إحداثيات الماوس الحالية
  static POINT GetPosition();
};

#endif