#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

// Messages propres à sPing.
// Clic sur l'icône de la zone de notification.
constexpr UINT kTrayMessage = WM_APP + 1;
// Une deuxième copie de sPing demande à la première d'afficher sa fenêtre.
constexpr UINT kShowMessage = WM_APP + 2;

// Fenêtre de sPing : la vue Flutter, plus une icône dans la zone de notification.
// Fermer la fenêtre la cache (sPing continue de recevoir les notifications) tant que
// « Garder sPing dans la zone de notification » est activé ; « Quitter » dans le menu de
// l'icône arrête sPing. Le code Dart dialogue avec elle par le canal « sping/fenetre »
// (lib/data/platform/desktop_shell.dart).
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |start_hidden| : lancé avec Windows, sPing démarre caché dans la zone de notification.
  explicit FlutterWindow(const flutter::DartProject& project, bool start_hidden);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetUpChannel();
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  void Reveal();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool start_hidden_;
  bool keep_in_tray_ = true;
  bool discreet_ = false;
  bool tray_added_ = false;
  HICON tray_icon_ = nullptr;
  // Message envoyé par l'Explorateur quand il redémarre : l'icône est alors à recréer.
  UINT taskbar_created_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
