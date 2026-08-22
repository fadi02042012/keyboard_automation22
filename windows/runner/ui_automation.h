#ifndef RUNNER_UI_AUTOMATION_H_
#define RUNNER_UI_AUTOMATION_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <flutter/encodable_value.h>
#include <string>

class UiAutomation {
 public:
  using EncodableMap = flutter::EncodableMap;
  using EncodableList = flutter::EncodableList;
  using EncodableValue = flutter::EncodableValue;

  static EncodableList InspectElements(const std::string& window_title,
                                       int max_depth,
                                       int max_elements,
                                       std::string* error);

  static bool ExecuteCommand(const std::string& window_title,
                             const std::string& command,
                             const EncodableMap& arguments,
                             std::string* error);
};

#endif  // RUNNER_UI_AUTOMATION_H_

