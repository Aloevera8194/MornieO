#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <stdlib.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Only the deb installs a desktop entry for mornye://, so the browser cannot
// hand an extension callback back to a zip or AppImage copy. Points the
// per-user handler at this copy unless the current one already starts it.
static void register_url_scheme() {
  // An AppImage runs from a new mount on every launch; its file stays put.
  const gchar* appimage = g_getenv("APPIMAGE");
  g_autofree gchar* self_path =
      appimage != nullptr ? g_strdup(appimage)
                          : g_file_read_link("/proc/self/exe", nullptr);
  if (self_path == nullptr) return;
  g_autofree gchar* self_real = realpath(self_path, nullptr);

  g_autoptr(GAppInfo) current =
      g_app_info_get_default_for_uri_scheme("mornye");
  if (current != nullptr && self_real != nullptr) {
    const char* executable = g_app_info_get_executable(current);
    g_autofree gchar* found =
        executable != nullptr ? g_find_program_in_path(executable) : nullptr;
    g_autofree gchar* found_real =
        found != nullptr ? realpath(found, nullptr) : nullptr;
    if (g_strcmp0(found_real, self_real) == 0) return;
  }

  // GIO appends " %u" and writes a hidden entry plus the mimeapps default.
  g_autofree gchar* commandline = g_shell_quote(self_path);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GAppInfo) handler = g_app_info_create_from_commandline(
      commandline, "Mornye", G_APP_INFO_CREATE_SUPPORTS_URIS, &error);
  if (handler == nullptr ||
      !g_app_info_set_as_default_for_type(handler, "x-scheme-handler/mornye",
                                          &error)) {
    g_warning("Could not register the mornye:// handler: %s",
              error != nullptr ? error->message : "unknown error");
  }
}

static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Single instance: a second launch activates the running window.
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows != nullptr) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }

  register_url_scheme();

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Mornye");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Mornye");
  }

  gtk_window_set_default_size(window, 1280, 800);
  GdkGeometry geometry = {};
  geometry.min_width = 800;
  geometry.min_height = 600;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);

  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* bundle_dir = g_path_get_dirname(executable);
    g_autofree gchar* icon_path =
        g_build_filename(bundle_dir, "data", "mornye.png", nullptr);
    gtk_window_set_icon_from_file(window, icon_path, nullptr);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  // The primary instance creates its window (and registers the plugins)
  // before GLib emits "command-line", so app_links sees the launch URL.
  if (!g_application_get_is_remote(application)) {
    g_application_activate(application);
  }
  *exit_status = 0;

  // Not handled here: GLib sends the command line to the primary instance,
  // which emits "command-line" there. app_links reads a forwarded
  // mornye:// URL from it; the handler below raises the window.
  return FALSE;
}

static gint my_application_command_line(GApplication* application,
                                        GApplicationCommandLine* command_line) {
  g_application_activate(application);
  return 0;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // Unique on the session bus: later launches (for example a mornye://
  // callback from the browser, `Exec=mornye %u`) forward their whole command
  // line to this process. URLs arrive as arguments, so "open" is not used.
  return MY_APPLICATION(g_object_new(
      my_application_get_type(), "application-id", APPLICATION_ID, "flags",
      G_APPLICATION_HANDLES_COMMAND_LINE, nullptr));
}
