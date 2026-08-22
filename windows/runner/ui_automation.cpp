#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "ui_automation.h"

#include "keyboard_input.h"
#include "window_manager.h"

#include <UIAutomation.h>
#include <oleauto.h>
#include <wrl/client.h>

#include <algorithm>
#include <cwctype>
#include <functional>
#include <limits>
#include <string>
#include <vector>

#pragma comment(lib, "uiautomationcore.lib")
#pragma comment(lib, "oleaut32.lib")

namespace {

using Microsoft::WRL::ComPtr;
using EncodableMap = flutter::EncodableMap;
using EncodableList = flutter::EncodableList;
using EncodableValue = flutter::EncodableValue;

class ScopedCom {
 public:
  explicit ScopedCom(std::string* error) {
    const HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(hr)) {
      owns_uninitialization_ = true;
      return;
    }
    // The Flutter runner may already have initialized COM in another mode.
    if (hr == RPC_E_CHANGED_MODE) return;
    usable_ = false;
    if (error != nullptr) {
      *error = "تعذر تهيئة COM لـ UI Automation (HRESULT=" +
          std::to_string(static_cast<unsigned long>(hr)) + ")";
    }
  }

  ~ScopedCom() {
    if (owns_uninitialization_) CoUninitialize();
  }

  bool IsUsable() const { return usable_; }

 private:
  bool owns_uninitialization_ = false;
  bool usable_ = true;
};

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

std::wstring Utf8ToWide(const std::string& value) {
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

std::string ReadString(const EncodableMap& args, const char* name) {
  const auto it = args.find(EncodableValue(name));
  if (it == args.end()) return {};
  const auto* value = std::get_if<std::string>(&it->second);
  return value == nullptr ? std::string{} : *value;
}

int ReadInt(const EncodableMap& args, const char* name, int fallback) {
  const auto it = args.find(EncodableValue(name));
  if (it == args.end()) return fallback;
  if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
  if (const auto* value = std::get_if<int64_t>(&it->second)) {
    return static_cast<int>(std::clamp<int64_t>(*value, 0, 100000));
  }
  return fallback;
}

bool ReadBool(const EncodableMap& args, const char* name, bool fallback) {
  const auto it = args.find(EncodableValue(name));
  if (it == args.end()) return fallback;
  if (const auto* value = std::get_if<bool>(&it->second)) return *value;
  return fallback;
}

std::wstring ReadElementString(IUIAutomationElement* element,
                              PROPERTYID property) {
  VARIANT value;
  VariantInit(&value);
  if (FAILED(element->GetCurrentPropertyValue(property, &value))) {
    return {};
  }
  std::wstring result;
  if (value.vt == VT_BSTR && value.bstrVal != nullptr) {
    result = value.bstrVal;
  }
  VariantClear(&value);
  return result;
}

bool Matches(IUIAutomationElement* element, const EncodableMap& args) {
  const std::string requested_name = ReadString(args, "name");
  const std::string requested_id = ReadString(args, "automationId");
  const std::string requested_class = ReadString(args, "className");
  const std::string requested_control_type = ReadString(args, "controlType");

  if (requested_name.empty() && requested_id.empty() && requested_class.empty() &&
      requested_control_type.empty()) {
    return false;
  }

  if (!requested_name.empty() &&
      WideToUtf8(ReadElementString(element, UIA_NamePropertyId)) != requested_name) {
    return false;
  }
  if (!requested_id.empty() &&
      WideToUtf8(ReadElementString(element, UIA_AutomationIdPropertyId)) != requested_id) {
    return false;
  }
  if (!requested_class.empty() &&
      WideToUtf8(ReadElementString(element, UIA_ClassNamePropertyId)) != requested_class) {
    return false;
  }
  if (!requested_control_type.empty()) {
    int control_type = 0;
    element->get_CurrentControlType(&control_type);
    const std::string actual = std::to_string(control_type);
    if (actual != requested_control_type) return false;
  }
  return true;
}

HWND FindWindow(const std::string& title) {
  const auto windows = GetOpenWindows();
  HWND fallback = nullptr;
  for (const auto& info : windows) {
    if (!WindowTitlesMatch(info.title, title)) continue;
    if (info.isActive) return info.hwnd;
    if (fallback == nullptr) fallback = info.hwnd;
  }
  return fallback;
}

bool CreateAutomation(ComPtr<IUIAutomation>* automation, std::string* error) {
  const HRESULT hr = CoCreateInstance(CLSID_CUIAutomation, nullptr,
                                       CLSCTX_INPROC_SERVER,
                                       IID_PPV_ARGS(automation->GetAddressOf()));
  if (FAILED(hr)) {
    if (error != nullptr) *error = "تعذر تهيئة Windows UI Automation (HRESULT=" +
        std::to_string(static_cast<unsigned long>(hr)) + ")";
    return false;
  }
  return true;
}

EncodableMap Describe(IUIAutomationElement* element) {
  EncodableMap item;
  item[EncodableValue("name")] = WideToUtf8(ReadElementString(element, UIA_NamePropertyId));
  item[EncodableValue("automationId")] =
      WideToUtf8(ReadElementString(element, UIA_AutomationIdPropertyId));
  item[EncodableValue("className")] =
      WideToUtf8(ReadElementString(element, UIA_ClassNamePropertyId));
  int control_type = 0;
  BOOL enabled = FALSE;
  BOOL offscreen = FALSE;
  RECT rect{};
  element->get_CurrentControlType(&control_type);
  element->get_CurrentIsEnabled(&enabled);
  element->get_CurrentIsOffscreen(&offscreen);
  element->get_CurrentBoundingRectangle(&rect);
  item[EncodableValue("controlType")] = static_cast<int32_t>(control_type);
  item[EncodableValue("enabled")] = enabled != FALSE;
  item[EncodableValue("offscreen")] = offscreen != FALSE;
  EncodableMap bounds;
  bounds[EncodableValue("left")] = static_cast<int32_t>(rect.left);
  bounds[EncodableValue("top")] = static_cast<int32_t>(rect.top);
  bounds[EncodableValue("right")] = static_cast<int32_t>(rect.right);
  bounds[EncodableValue("bottom")] = static_cast<int32_t>(rect.bottom);
  item[EncodableValue("bounds")] = EncodableValue(bounds);
  return item;
}

void Walk(IUIAutomationTreeWalker* walker,
          IUIAutomationElement* element,
          int depth,
          int max_depth,
          int max_elements,
          EncodableList* output) {
  if (element == nullptr || output == nullptr ||
      static_cast<int>(output->size()) >= max_elements || depth > max_depth) {
    return;
  }
  output->push_back(EncodableValue(Describe(element)));
  if (depth == max_depth || static_cast<int>(output->size()) >= max_elements) return;

  ComPtr<IUIAutomationElement> child;
  if (FAILED(walker->GetFirstChildElement(element, child.GetAddressOf()))) return;
  while (child != nullptr && static_cast<int>(output->size()) < max_elements) {
    Walk(walker, child.Get(), depth + 1, max_depth, max_elements, output);
    ComPtr<IUIAutomationElement> next;
    if (FAILED(walker->GetNextSiblingElement(child.Get(), next.GetAddressOf()))) break;
    child = next;
  }
}

bool FindElement(IUIAutomationTreeWalker* walker,
                 IUIAutomationElement* element,
                 const EncodableMap& args,
                 int depth,
                 int max_depth,
                 ComPtr<IUIAutomationElement>* result) {
  if (element == nullptr || depth > max_depth) return false;
  if (Matches(element, args)) {
    *result = element;
    return true;
  }
  ComPtr<IUIAutomationElement> child;
  if (FAILED(walker->GetFirstChildElement(element, child.GetAddressOf()))) return false;
  while (child != nullptr) {
    if (FindElement(walker, child.Get(), args, depth + 1, max_depth, result)) return true;
    ComPtr<IUIAutomationElement> next;
    if (FAILED(walker->GetNextSiblingElement(child.Get(), next.GetAddressOf()))) break;
    child = next;
  }
  return false;
}

bool ExecuteOnElement(IUIAutomationElement* element,
                      const std::string& command,
                      const EncodableMap& args,
                      std::string* error) {
  if (command == "focus") {
    return SUCCEEDED(element->SetFocus());
  }
  if (command == "invoke") {
    ComPtr<IUIAutomationInvokePattern> pattern;
    if (FAILED(element->GetCurrentPatternAs(
                    UIA_InvokePatternId, __uuidof(IUIAutomationInvokePattern),
                    reinterpret_cast<void**>(pattern.GetAddressOf()))) ||
        FAILED(pattern->Invoke())) {
      if (error != nullptr) *error = "العنصر لا يدعم أمر Invoke.";
      return false;
    }
    return true;
  }
  if (command == "set_value") {
    const std::string value = ReadString(args, "value");
    ComPtr<IUIAutomationValuePattern> pattern;
    if (FAILED(element->GetCurrentPatternAs(
                    UIA_ValuePatternId, __uuidof(IUIAutomationValuePattern),
                    reinterpret_cast<void**>(pattern.GetAddressOf()))) ||
        pattern == nullptr) {
      if (error != nullptr) *error = "العنصر لا يدعم تعيين القيمة.";
      return false;
    }

    // IUIAutomationValuePattern::SetValue requires an owning BSTR. Passing
    // std::wstring::c_str() directly is not type-safe and fails with MSVC.
    const std::wstring wide_value = Utf8ToWide(value);
    BSTR bstr_value = SysAllocStringLen(
        wide_value.data(), static_cast<UINT>(wide_value.size()));
    if (bstr_value == nullptr) {
      if (error != nullptr) *error = "تعذر تخصيص نص القيمة.";
      return false;
    }
    const HRESULT set_result = pattern->SetValue(bstr_value);
    SysFreeString(bstr_value);
    if (FAILED(set_result)) {
      if (error != nullptr) *error = "تعذر تعيين قيمة العنصر.";
      return false;
    }
    return true;
  }
  if (command == "toggle") {
    ComPtr<IUIAutomationTogglePattern> pattern;
    if (FAILED(element->GetCurrentPatternAs(
                    UIA_TogglePatternId, __uuidof(IUIAutomationTogglePattern),
                    reinterpret_cast<void**>(pattern.GetAddressOf()))) ||
        FAILED(pattern->Toggle())) {
      if (error != nullptr) *error = "العنصر لا يدعم Toggle.";
      return false;
    }
    return true;
  }
  if (command == "select") {
    ComPtr<IUIAutomationSelectionItemPattern> pattern;
    if (FAILED(element->GetCurrentPatternAs(
                    UIA_SelectionItemPatternId,
                    __uuidof(IUIAutomationSelectionItemPattern),
                    reinterpret_cast<void**>(pattern.GetAddressOf()))) ||
        FAILED(pattern->Select())) {
      if (error != nullptr) *error = "العنصر لا يدعم Select.";
      return false;
    }
    return true;
  }
  if (error != nullptr) *error = "الأمر الدلالي غير مدعوم: " + command;
  return false;
}

}  // namespace

UiAutomation::EncodableList UiAutomation::InspectElements(
    const std::string& window_title,
    int max_depth,
    int max_elements,
    std::string* error) {
    EncodableList output;
    ScopedCom com(error);
    if (!com.IsUsable()) return output;
    const HWND hwnd = FindWindow(window_title);
  if (hwnd == nullptr) {
    if (error != nullptr) *error = "لم يتم العثور على النافذة: " + window_title;
    return output;
  }
  ComPtr<IUIAutomation> automation;
  if (!CreateAutomation(&automation, error)) return output;
  ComPtr<IUIAutomationElement> root;
  if (FAILED(automation->ElementFromHandle(hwnd, root.GetAddressOf()))) {
    if (error != nullptr) *error = "تعذر الحصول على جذر عناصر النافذة.";
    return output;
  }
  ComPtr<IUIAutomationTreeWalker> walker;
  if (FAILED(automation->get_ControlViewWalker(walker.GetAddressOf()))) {
    if (error != nullptr) *error = "تعذر إنشاء متصفح عناصر النافذة.";
    return output;
  }
  Walk(walker.Get(), root.Get(), 0, std::clamp(max_depth, 0, 8),
       std::clamp(max_elements, 1, 500), &output);
  return output;
}

bool UiAutomation::ExecuteCommand(const std::string& window_title,
                                   const std::string& command,
                                   const EncodableMap& arguments,
                                   std::string* error) {
  ScopedCom com(error);
  if (!com.IsUsable()) return false;
  const HWND hwnd = FindWindow(window_title);
  if (hwnd == nullptr) {
    if (error != nullptr) *error = "لم يتم العثور على النافذة: " + window_title;
    return false;
  }
  ComPtr<IUIAutomation> automation;
  if (!CreateAutomation(&automation, error)) return false;
  ComPtr<IUIAutomationElement> root;
  if (FAILED(automation->ElementFromHandle(hwnd, root.GetAddressOf()))) {
    if (error != nullptr) *error = "تعذر الحصول على جذر عناصر النافذة.";
    return false;
  }
  ComPtr<IUIAutomationTreeWalker> walker;
  if (FAILED(automation->get_ControlViewWalker(walker.GetAddressOf()))) {
    if (error != nullptr) *error = "تعذر إنشاء متصفح عناصر النافذة.";
    return false;
  }
  ComPtr<IUIAutomationElement> element;
  const int max_depth = std::clamp(ReadInt(arguments, "maxDepth", 8), 0, 8);
  if (!FindElement(walker.Get(), root.Get(), arguments, 0, max_depth, &element)) {
    if (error != nullptr) *error = "لم يتم العثور على عنصر UI بالمحددات المقدمة.";
    return false;
  }
  return ExecuteOnElement(element.Get(), command, arguments, error);
}
