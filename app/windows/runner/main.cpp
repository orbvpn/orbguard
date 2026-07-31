#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "app_links/app_links_plugin_c_api.h"

// The window title passed to window.Create() below. SendAppLinkToInstance()
// looks the window up by this exact string, so the two MUST stay in sync.
constexpr wchar_t kWindowTitle[] = L"OrbGuard";

// Windows launches a NEW process every time an orbguard:// link is activated.
// Without this, tapping the emailed magic link while OrbGuard is already open
// starts a second copy that consumes the code, leaving the window the user is
// actually looking at signed out — the Microsoft 10.1.2.10 "Unusable Feature:
// Sign in" rejection. Forward the link to the running instance and exit.
bool SendAppLinkToInstance(const std::wstring& title) {
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", title.c_str());
  if (!hwnd) return false;

  // Hand the command line (carrying the orbguard:// URI) to the live window.
  SendAppLink(hwnd);

  // Restore it to the foreground in whatever state the user left it, so the
  // sign-in visibly completes in front of them.
  WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
  ::GetWindowPlacement(hwnd, &place);
  switch (place.showCmd) {
    case SW_SHOWMAXIMIZED:
      ::ShowWindow(hwnd, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ::ShowWindow(hwnd, SW_RESTORE);
      break;
    default:
      ::ShowWindow(hwnd, SW_NORMAL);
      break;
  }
  ::SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
                 SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
  ::SetForegroundWindow(hwnd);
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // A link arrived for an instance that is already running — deliver it there
  // rather than opening a duplicate window.
  if (SendAppLinkToInstance(kWindowTitle)) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
