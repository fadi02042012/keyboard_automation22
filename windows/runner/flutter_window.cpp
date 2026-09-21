// windows/runner/flutter_window.cpp

#include "flutter_window.h"
#include "window_manager.h"
#include <optional>
#include <memory>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "automation_engine.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
    if (!Win32Window::OnCreate()) {
        return false;
    }

    RECT frame = GetClientArea();

    flutter_controller_ =
        std::make_unique<flutter::FlutterViewController>(
            frame.right - frame.left,
            frame.bottom - frame.top,
            project_);

    if (!flutter_controller_->engine() ||
        !flutter_controller_->view()) {
        return false;
    }

    // قناة لوحة المفاتيح
    keyboard_channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            flutter_controller_->engine()->messenger(),
            "keyboard_automation/keyboard",
            &flutter::StandardMethodCodec::GetInstance());

    auto engine = std::make_shared<AutomationEngine>(GetHandle());

    keyboard_channel_->SetMethodCallHandler(
        [engine](const flutter::MethodCall<flutter::EncodableValue>& call,
                 std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            engine->HandleMethodCall(call, std::move(result));
        });

    // ============================================================
    // ⬅️ قناة النوافذ (يجب أن تكون هنا)
    // ============================================================
    window_channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            flutter_controller_->engine()->messenger(),
            "keyboard_automation/windows",
            &flutter::StandardMethodCodec::GetInstance());

    window_channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            this->OnMethodCall(call, std::move(result));
        });

    SetChildContent(flutter_controller_->view()->GetNativeWindow());

    flutter_controller_->engine()->SetNextFrameCallback(
        [&]() {
            this->Show();
        });

    flutter_controller_->ForceRedraw();

    return true;
}

void FlutterWindow::OnDestroy() {
    if (flutter_controller_) {
        flutter_controller_ = nullptr;
    }
    Win32Window::OnDestroy();
}

// ============================================================
// ⬅️ دالة معالج استدعاءات القناة
// ============================================================
void FlutterWindow::OnMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    
    if (method_call.method_name() == "getOpenWindows") {
        auto windows = GetOpenWindows();
        flutter::EncodableList windowList;
        
        for (const auto& win : windows) {
            flutter::EncodableMap windowMap;
            windowMap[flutter::EncodableValue("title")] = flutter::EncodableValue(win.title);
            windowMap[flutter::EncodableValue("process")] = flutter::EncodableValue(win.processName);
            windowMap[flutter::EncodableValue("isActive")] = flutter::EncodableValue(win.isActive);
            windowMap[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(win.hwnd)));
            windowList.push_back(flutter::EncodableValue(windowMap));
        }
        
        result->Success(flutter::EncodableValue(windowList));
        return;
    }
    
    if (method_call.method_name() == "getActiveWindow") {
        auto win = GetActiveWindowInfo();
        flutter::EncodableMap windowMap;
        windowMap[flutter::EncodableValue("title")] = flutter::EncodableValue(win.title);
        windowMap[flutter::EncodableValue("process")] = flutter::EncodableValue(win.processName);
        windowMap[flutter::EncodableValue("isActive")] = flutter::EncodableValue(win.isActive);
        windowMap[flutter::EncodableValue("hwnd")] = flutter::EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(win.hwnd)));
        result->Success(flutter::EncodableValue(windowMap));
        return;
    }
    
    if (method_call.method_name() == "activateWindow") {
        auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) {
            std::string windowAlias;
            std::string windowTitle;
            auto aliasIt = args->find(flutter::EncodableValue("windowAlias"));
            if (aliasIt != args->end()) {
                if (const auto* value = std::get_if<std::string>(&aliasIt->second)) {
                    windowAlias = *value;
                }
            }
            auto titleIt = args->find(flutter::EncodableValue("windowTitle"));
            if (titleIt != args->end()) {
                if (const auto* value = std::get_if<std::string>(&titleIt->second)) {
                    windowTitle = *value;
                }
            }
            if (windowAlias.empty() && windowTitle.empty()) {
                result->Error("INVALID_ARGUMENTS", "windowAlias or windowTitle is required");
                return;
            }
            std::string matchMode = "title";
            auto modeIt = args->find(flutter::EncodableValue("windowMatch"));
            if (modeIt != args->end()) {
                if (const auto* value = std::get_if<std::string>(&modeIt->second)) {
                    matchMode = *value;
                }
            }
            const bool activated = !windowAlias.empty()
                ? ActivateWindowByAlias(windowAlias, windowTitle, matchMode)
                : ActivateWindowByTitle(windowTitle);
            result->Success(flutter::EncodableValue(activated));
            return;
        }
        result->Error("INVALID_ARGUMENTS", "Missing window arguments");
        return;
    }

    if (method_call.method_name() == "checkWindowActive") {
        auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) {
            auto it = args->find(flutter::EncodableValue("windowTitle"));
            if (it != args->end()) {
                const auto* targetTitle = std::get_if<std::string>(&it->second);
                if (targetTitle == nullptr || targetTitle->empty()) {
                    result->Error("INVALID_ARGUMENTS", "windowTitle must be a non-empty string");
                    return;
                }
                auto activeWindow = GetActiveWindowInfo();
                const bool isActive = WindowTitlesMatch(activeWindow.title, *targetTitle);
                result->Success(flutter::EncodableValue(isActive));
                return;
            }
        }
        result->Error("INVALID_ARGUMENTS", "Missing windowTitle parameter");
        return;
    }
    
    result->NotImplemented();
}

LRESULT FlutterWindow::MessageHandler(
    HWND hwnd,
    UINT const message,
    WPARAM const wparam,
    LPARAM const lparam) noexcept {

    if (flutter_controller_) {
        std::optional<LRESULT> result =
            flutter_controller_->HandleTopLevelWindowProc(
                hwnd,
                message,
                wparam,
                lparam);

        if (result) {
            return *result;
        }
    }

    switch (message) {
        case WM_FONTCHANGE:
            flutter_controller_->engine()->ReloadSystemFonts();
            break;
    }

    return Win32Window::MessageHandler(
        hwnd,
        message,
        wparam,
        lparam);
}