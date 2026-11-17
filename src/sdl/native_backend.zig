//! Picks this OS's native-view host at compile time and hands it to the
//! event loop: the placement of the app's platform views at the
//! `NativeView` regions each frame collects, their hiding while an overlay
//! is open, and the keyboard focus moving between them and SDL's view.

const std = @import("std");
const log = std.log.scoped(.ziggui_native_backend);
const mod = @import("module.zig");
const renderer = @import("renderer");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// This OS's native-view host, as the event loop uses it. Each platform type
/// has the same declarations: `presents`, `present`, `hasFocus`, `release`,
/// `contains` and `detachAll`.
pub const NativeBackend = struct {
    const Self = @This();

    /// The platform host: AppKit on macOS, child windows on Windows; a stub on
    /// Linux for now.
    const Platform = switch (mod.os_tag) {
        .macos => mod.AppKitNativeHost,
        .windows => mod.Win32NativeHost,
        else => mod.NativeHostStub,
    };

    /// Whether this OS places platform views over the window's surface: the
    /// loop collects `NativeView` regions only then, else each draws a
    /// placeholder.
    pub const presents = Platform.presents;

    /// Shows each region's platform view where its `NativeView` is, and hides
    /// those no view showed this frame, or every one while an overlay is open.
    ///
    /// - `window`: the main window.
    /// - `regions`: the frame's `NativeView` regions, in points.
    /// - `overlay_open`: a sheet, alert, popover or menu is drawn this frame.
    pub fn present(window: *sdl_c.SDL_Window, regions: []const views.NativeRegion, overlay_open: bool) void {
        Platform.present(window, regions, overlay_open);
    }

    /// Reports whether a platform view holds the keyboard, so the loop leaves
    /// keys and text to it.
    ///
    /// - Returns: true while one of the placed views is first responder.
    pub fn hasFocus() bool {
        return Platform.hasFocus();
    }

    /// Hands the keyboard back to SDL's view when a platform view holds it; a
    /// click on ziggui's own surface calls this.
    pub fn release() void {
        Platform.release();
    }

    /// Sends an editing key the app did not consume (⌘C, ⌘X, ⌘V, ⌘A, with
    /// no other modifier) to the platform view holding the keyboard, as an
    /// Edit menu would.
    ///
    /// - `keycode`: the key's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: true when it was an editing key a view took.
    pub fn performEdit(keycode: u32, modifiers: u16) bool {
        return Platform.performEdit(keycode, modifiers);
    }

    /// Reports whether a point falls on a shown platform view, whose clicks
    /// are its own and never ziggui's.
    ///
    /// - `point`: the point, in the window's points.
    /// - Returns: true over a shown platform view.
    pub fn contains(point: renderer.Point) bool {
        return Platform.contains(point);
    }

    /// Takes every platform view out of the window; the loop calls this
    /// before it destroys the window. The app's views live on.
    pub fn detachAll() void {
        Platform.detachAll();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
