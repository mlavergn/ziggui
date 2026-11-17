//! The Windows platform code: the Win32 calls SDL does not make, and the
//! stubs for Windows video (Media Foundation) and web pages (WebView2).
//! Other targets reach it only through the compile-time selectors in the
//! parent module (`VideoBackend`, `WebBackend`) and the Windows branches of
//! `App` and the event loop.

const std = @import("std");
const log = std.log.scoped(.ziggui_windows_module);

/// The Win32 calls SDL does not make: the notification-area icon and the icon resource.
pub const Win32 = @import("win32.zig").Win32;
/// The Windows media player (Media Foundation): a stub for now.
pub const MediaFoundationPlayer = @import("media_foundation_player.zig").MediaFoundationPlayer;
/// The Windows web view (WebView2): a stub for now.
pub const WebView2Backend = @import("web_view2_backend.zig").WebView2Backend;

// -----------------------------------------------------------------------------
// From the sdl module

/// The app and its window (`Win32` reaches the window), from the sdl module.
pub const App = @import("../module.zig").App;
/// The popover panel (`Win32` toggles it from the tray), from the sdl module.
pub const Panel = @import("../module.zig").Panel;
/// The window's icon (`Win32` sets the tray's), from the sdl module.
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
