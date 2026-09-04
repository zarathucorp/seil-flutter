#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  external_file_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.zarathu.seil/external_file",
      &flutter::StandardMethodCodec::GetInstance());
  external_file_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "open" && call.method_name() != "reveal") {
          result->NotImplemented();
          return;
        }
        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("invalid_path", "File path is missing.");
          return;
        }
        const auto path_iterator =
            arguments->find(flutter::EncodableValue("path"));
        if (path_iterator == arguments->end()) {
          result->Error("invalid_path", "File path is missing.");
          return;
        }
        const auto* path_utf8 =
            std::get_if<std::string>(&path_iterator->second);
        if (path_utf8 == nullptr || path_utf8->empty()) {
          result->Error("invalid_path", "File path is empty.");
          return;
        }
        const std::wstring path = Utf16FromUtf8(*path_utf8);
        if (path.empty() ||
            ::GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) {
          result->Error("missing_file", "File does not exist.");
          return;
        }

        HINSTANCE launch_result;
        if (call.method_name() == "reveal") {
          const std::wstring parameters = L"/select,\"" + path + L"\"";
          launch_result = ::ShellExecuteW(
              GetHandle(), L"open", L"explorer.exe", parameters.c_str(),
              nullptr, SW_SHOWNORMAL);
        } else {
          launch_result = ::ShellExecuteW(
              GetHandle(), L"open", path.c_str(), nullptr, nullptr,
              SW_SHOWNORMAL);
        }
        if (reinterpret_cast<INT_PTR>(launch_result) <= 32) {
          result->Error("open_failed", "Windows could not open the file.");
          return;
        }
        result->Success();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    external_file_channel_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
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

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
