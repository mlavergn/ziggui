//! The Linux platform code: the tray icon over D-Bus (StatusNotifierItem),
//! the freedesktop entry, GTK and what is built on it (the native-view host
//! and WebKitGTK web pages), and GStreamer video, all loaded at run time.
//! Other targets reach it only through the compile-time selectors in the
//! parent module (`VideoBackend`, `NativeBackend`, `WebBackend`) and the
//! Linux branches of `App` and the event loop.

const std = @import("std");
const log = std.log.scoped(.ziggui_linux_module);

/// The Linux status item: a StatusNotifierItem over D-Bus.
pub const StatusNotifier = @import("status_notifier.zig").StatusNotifier;
/// Linux desktop integration: the running executable's freedesktop entry and icon.
pub const DesktopInstall = @import("desktop_install.zig").DesktopInstall;
/// The Linux media player: GStreamer's `playbin`, its frames drawn by ziggui.
pub const GstreamerPlayer = @import("gstreamer_player.zig").GstreamerPlayer;
/// GStreamer and its app sink, loaded at run time.
pub const Gstreamer = @import("gstreamer.zig").Gstreamer;
/// The GStreamer entry points `Gstreamer.start` resolves.
pub const GstreamerApi = @import("gstreamer.zig").GstreamerApi;
/// GStreamer's mini-object head.
pub const GstMiniObject = @import("gstreamer.zig").GstMiniObject;
/// GStreamer's bus message.
pub const GstMessage = @import("gstreamer.zig").GstMessage;
/// A mapped GStreamer buffer.
pub const GstMapInfo = @import("gstreamer.zig").GstMapInfo;
/// The app sink's callbacks.
pub const GstAppSinkCallbacks = @import("gstreamer.zig").GstAppSinkCallbacks;
/// GTK 3, WebKitGTK and the Xlib calls around them, loaded at run time.
pub const Gtk = @import("gtk.zig").Gtk;
/// The GTK entry points `Gtk.start` resolves.
pub const GtkApi = @import("gtk.zig").GtkApi;
/// GLib's `gboolean`.
pub const Gboolean = @import("gtk.zig").Gboolean;
/// GLib's `GPollFD`.
pub const GpollFd = @import("gtk.zig").GpollFd;
/// GLib's `GError`.
pub const Gerror = @import("gtk.zig").Gerror;
/// The fields every `GdkEvent` starts with.
pub const GdkEventAny = @import("gtk.zig").GdkEventAny;
/// GDK's key event.
pub const GdkEventKey = @import("gtk.zig").GdkEventKey;
/// GDK's focus event.
pub const GdkEventFocus = @import("gtk.zig").GdkEventFocus;
/// Runs GLib's main context inside the SDL loop.
pub const GlibPump = @import("glib_pump.zig").GlibPump;
/// Loads a C library's entry points at run time (`Gtk`, `Gstreamer`).
pub const DynamicApi = @import("dynamic_api.zig").DynamicApi;
/// The Linux native-view host: app `GtkWidget`s in X11 child windows of SDL's.
pub const GtkNativeHost = @import("gtk_native_host.zig").GtkNativeHost;
/// The Linux web view: a WebKitGTK `WebKitWebView` per `WebPage`.
pub const WebKitGtkBackend = @import("web_kit_gtk_backend.zig").WebKitGtkBackend;

// -----------------------------------------------------------------------------
// From the sdl module

/// The app and its window (`StatusNotifier` and `GtkNativeHost` reach the
/// app), from the sdl module.
pub const App = @import("../module.zig").App;
/// The window's icon (`StatusNotifier` publishes it), from the sdl module.
pub const WindowIcon = @import("../module.zig").WindowIcon;
/// The origin rule the web view's bridges apply, from the sdl module.
pub const WebOrigin = @import("../module.zig").WebOrigin;
/// The target OS, from the sdl module.
pub const os_tag = @import("../module.zig").os_tag;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
