#ifndef RUNNER_WINDOW_MANAGER_H_
#define RUNNER_WINDOW_MANAGER_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <string>
#include <vector>

struct WindowInfo {
  std::string title;
  std::string processName;
  bool isActive = false;
  HWND hwnd = nullptr;
};

std::vector<WindowInfo> GetOpenWindows();
WindowInfo GetActiveWindowInfo();

// Activates the best visible top-level window matching a recorded title.
// Matching is case-insensitive and supports meaningful title fragments.
bool WindowTitlesMatch(const std::string& actual_title, const std::string& requested_title);
bool ActivateWindowByTitle(const std::string& target_title);
bool ActivateWindowByAlias(const std::string& alias, const std::string& fallback_title = "");

#endif  // RUNNER_WINDOW_MANAGER_H_
