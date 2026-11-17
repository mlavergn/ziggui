//! The Windows platform code: the Win32 calls SDL does not make, the
//! native-view host that places child windows over SDL's, the WebView2 web
//! view and the Media Foundation player. Other targets reach it only through
//! the compile-time selectors in the parent module (`VideoBackend`,
//! `WebBackend`, `NativeBackend`) and the Windows branches of `App` and the
//! event loop.

const std = @import("std");
const log = std.log.scoped(.ziggui_windows_module);

/// The Win32 calls SDL does not make: the notification-area icon and the icon resource.
pub const Win32 = @import("win32.zig").Win32;
/// The bits of COM the web view and the player share.
pub const Com = @import("com.zig").Com;
/// COM's `HRESULT`, shared by the Windows files: negative is a failure.
pub const HRESULT = @import("com.zig").HRESULT;
/// A window handle, shared by the Windows files.
pub const HWND = @import("win32.zig").HWND;
/// A message's word parameter, shared by the Windows files.
pub const WPARAM = @import("win32.zig").WPARAM;
/// A message's long parameter, shared by the Windows files.
pub const LPARAM = @import("win32.zig").LPARAM;
/// A window procedure's result, shared by the Windows files.
pub const LRESULT = @import("win32.zig").LRESULT;
/// Win32's `RECT`, shared by the Windows files.
pub const RECT = @import("win32.zig").RECT;
/// The Windows native-view host: child windows placed over SDL's.
pub const Win32NativeHost = @import("win32_native_host.zig").Win32NativeHost;
/// The Windows media player (Media Foundation), its frames drawn under ziggui's surface.
pub const MediaFoundationPlayer = @import("media_foundation_player.zig").MediaFoundationPlayer;
/// The Windows web view (WebView2), placed by `Win32NativeHost`.
pub const WebView2Backend = @import("web_view2_backend.zig").WebView2Backend;

// -----------------------------------------------------------------------------
// From the sdl module

/// The app and its window (`Win32` reaches the window), from the sdl module.
pub const App = @import("../module.zig").App;
/// The popover panel (`Win32` toggles it from the tray), from the sdl module.
pub const Panel = @import("../module.zig").Panel;
/// The window's icon (`Win32` sets the tray's), from the sdl module.
pub const WindowIcon = @import("../module.zig").WindowIcon;
/// A video frame drawn under ziggui's surface (`MediaFoundationPlayer` makes
/// them), from the sdl module.
pub const VideoUnderlay = @import("../module.zig").VideoUnderlay;
/// The origin rule the web view's bridges apply, from the sdl module.
pub const WebOrigin = @import("../module.zig").WebOrigin;
/// The target OS, from the sdl module.
pub const os_tag = @import("../module.zig").os_tag;
/// The target CPU (`WebView2Backend` picks the runtime's library by it), from the sdl module.
pub const cpu_arch = @import("../module.zig").cpu_arch;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
