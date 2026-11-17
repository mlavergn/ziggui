//! The Linux platform code: the tray icon over D-Bus (StatusNotifierItem),
//! the freedesktop entry, and the stubs for Linux video (GStreamer) and web
//! pages (WebKitGTK). Other targets reach it only through the compile-time
//! selectors in the parent module (`VideoBackend`, `WebBackend`) and the
//! Linux branches of `App` and the event loop.

const std = @import("std");
const log = std.log.scoped(.ziggui_linux_module);

/// The Linux status item: a StatusNotifierItem over D-Bus.
pub const StatusNotifier = @import("status_notifier.zig").StatusNotifier;
/// Linux desktop integration: the running executable's freedesktop entry and icon.
pub const DesktopInstall = @import("desktop_install.zig").DesktopInstall;
/// The Linux media player (GStreamer): a stub for now.
pub const GstreamerPlayer = @import("gstreamer_player.zig").GstreamerPlayer;
/// The Linux web view (WebKitGTK): a stub for now.
pub const WebKitGtkBackend = @import("web_kit_gtk_backend.zig").WebKitGtkBackend;

// -----------------------------------------------------------------------------
// From the sdl module

/// The app and its window (`StatusNotifier` reaches the app), from the sdl module.
pub const App = @import("../module.zig").App;
/// The window's icon (`StatusNotifier` publishes it), from the sdl module.
pub const WindowIcon = @import("../module.zig").WindowIcon;
/// The target OS, from the sdl module.
pub const os_tag = @import("../module.zig").os_tag;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
