#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl.h>
#include <windows.h>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// Per user session, so two signed-in users each get their own instance.
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\com.zarz.mornye.instance";

// Same ID as the installer's Start Menu shortcut (windows/installer), so the
// taskbar groups the window with its pinned shortcut.
constexpr wchar_t kAppUserModelId[] = L"com.zarz.mornye";

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single instance. A second launch (for example a mornye:// callback from
  // the browser: the installer registers `"mornye.exe" "%1"` under
  // HKCU\Software\Classes\mornye) hands its URL to the running window with
  // WM_COPYDATA, raises that window and exits. The installer closes the app
  // before it replaces files, so a /RELAUNCH=1 start finds no instance.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // False while the first instance has not created its window yet; the
    // URL is then lost, as for any launch during startup.
    SendAppLinkToInstance();
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);

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
  Win32Window::Size size(1280, 800);
  if (!window.Create(L"Mornye", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex != nullptr) {
    ::ReleaseMutex(instance_mutex);
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
