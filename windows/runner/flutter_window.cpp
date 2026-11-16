#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr wchar_t kRunKey[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"sPing";

enum MenuCommand : UINT { kMenuOpen = 1, kMenuDiscreet = 2, kMenuQuit = 3 };

std::wstring ExecutablePath() {
  wchar_t path[MAX_PATH * 2];
  const DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH * 2);
  return std::wstring(path, length);
}

// Démarrage avec Windows : une valeur dans la clé « Run » de l'utilisateur.
bool LaunchAtStartup() {
  return ::RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                        nullptr, nullptr, nullptr) == ERROR_SUCCESS;
}

void SetLaunchAtStartup(bool enabled) {
  if (enabled) {
    const std::wstring command = L"\"" + ExecutablePath() + L"\" --demarrage";
    ::RegSetKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, REG_SZ,
                      command.c_str(),
                      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    ::RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunValue);
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

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
  SetUpChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  taskbar_created_ = ::RegisterWindowMessageW(L"TaskbarCreated");
  AddTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // Lancé avec Windows : sPing reste discret dans la zone de notification.
    if (!start_hidden_ || !tray_added_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetUpChannel() {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "sping/fenetre",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* flag = std::get_if<bool>(call.arguments());
        const std::string& method = call.method_name();
        if (method == "garderEnZone" && flag) {
          keep_in_tray_ = *flag;
          result->Success();
        } else if (method == "discret" && flag) {
          discreet_ = *flag;
          result->Success();
        } else if (method == "demarrageAuto") {
          if (flag) {
            SetLaunchAtStartup(*flag);
            result->Success();
          } else {
            result->Success(flutter::EncodableValue(LaunchAtStartup()));
          }
        } else if (method == "afficher") {
          Reveal();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::AddTrayIcon() {
  if (!tray_icon_) {
    tray_icon_ = static_cast<HICON>(::LoadImageW(
        ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
        ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON), 0));
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = 1;
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = tray_icon_;
  wcscpy_s(data.szTip, L"sPing");
  tray_added_ = ::Shell_NotifyIconW(NIM_ADD, &data) == TRUE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) return;
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = 1;
  ::Shell_NotifyIconW(NIM_DELETE, &data);
  tray_added_ = false;
}

void FlutterWindow::Reveal() {
  HWND window = GetHandle();
  if (!window) return;
  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  } else {
    ::ShowWindow(window, SW_SHOW);
  }
  ::SetForegroundWindow(window);
}

void FlutterWindow::ShowTrayMenu() {
  HWND window = GetHandle();
  HMENU menu = ::CreatePopupMenu();
  if (!menu) return;
  ::AppendMenuW(menu, MF_STRING, kMenuOpen, L"Ouvrir sPing");
  ::AppendMenuW(menu, MF_STRING | (discreet_ ? MF_CHECKED : MF_UNCHECKED),
                kMenuDiscreet, L"Mode discret");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuQuit, L"Quitter sPing");
  ::SetMenuDefaultItem(menu, kMenuOpen, FALSE);
  POINT cursor;
  ::GetCursorPos(&cursor);
  // Sans cela, le menu ne se ferme pas quand on clique ailleurs.
  ::SetForegroundWindow(window);
  const UINT command = ::TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x, cursor.y,
      0, window, nullptr);
  ::PostMessageW(window, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
  switch (command) {
    case kMenuOpen:
      Reveal();
      break;
    case kMenuDiscreet:
      discreet_ = !discreet_;
      if (channel_) channel_->InvokeMethod("basculerDiscret", nullptr);
      break;
    case kMenuQuit:
      keep_in_tray_ = false;
      ::DestroyWindow(window);
      break;
  }
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

  if (taskbar_created_ != 0 && message == taskbar_created_) {
    tray_added_ = false;
    AddTrayIcon();
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_CLOSE:
      // La fenêtre se cache : sPing continue de recevoir les notifications.
      if (keep_in_tray_ && tray_added_) {
        ::ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
    case kShowMessage:
      Reveal();
      return 0;
    case kTrayMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          Reveal();
          break;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          break;
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
