#ifndef AUTOMATION_ENGINE_H_
#define AUTOMATION_ENGINE_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "macro_recorder.h"

class AutomationEngine {
 public:
  explicit AutomationEngine(HWND ignored_window);
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  MacroRecorder macro_recorder_;
};

#endif  // AUTOMATION_ENGINE_H_
