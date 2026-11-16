#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Une seule copie de sPing à la fois : une deuxième ouverture (raccourci, clic sur une
  // notification Windows) montre la fenêtre de la première, puis s'arrête.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\sPing-ShinezeoGame-instance");
  if (instance_mutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"sPing");
    if (existing) {
      ::AllowSetForegroundWindow(ASFW_ANY);
      ::PostMessageW(existing, kShowMessage, 0, 0);
    }
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }
  // Lancé avec Windows (clé « Run ») : démarre caché dans la zone de notification.
  const bool start_hidden = ::wcsstr(::GetCommandLineW(), L"--demarrage") != nullptr;

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, start_hidden);

  // Fenêtre étroite, comme sur le téléphone, calée à droite de l'écran principal et
  // centrée en hauteur. Les dimensions sont en pixels logiques : Win32Window
  // applique lui-même l'échelle d'affichage.
  RECT work = {0, 0, 1280, 720};
  ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work, 0);
  const double scale = ::GetDpiForSystem() / 96.0;
  const int work_width = static_cast<int>((work.right - work.left) / scale);
  const int work_height = static_cast<int>((work.bottom - work.top) / scale);
  const int width = (std::min)(420, (std::max)(360, work_width - 20));
  const int height = (std::min)(760, (std::max)(480, work_height - 40));
  const int x = static_cast<int>(work.left / scale) +
                (std::max)(10, work_width - width - 48);
  const int y = static_cast<int>(work.top / scale) +
                (std::max)(10, (work_height - height) / 2);
  Win32Window::Point origin(x, y);
  Win32Window::Size size(width, height);
  if (!window.Create(L"sPing", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex) ::CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
