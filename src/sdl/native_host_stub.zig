//! The Linux and Windows native-view host: not implemented yet. No region is
//! collected, so every `NativeView` draws its placeholder.
//!
//! The intended hosts are a child `GtkWidget` (Linux) or a child `HWND`
//! (Windows) parented to SDL's window and positioned each frame from the
//! `NativeRegion`s, as AppKit's is. A web view there is `webkitgtk-6.0`'s
//! `WebKitWebView` or WebView2's controller window.

const std = @import("std");
const log = std.log.scoped(.ziggui_native_host_stub);
const renderer = @import("renderer");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// The native-view host where none is implemented: it places nothing.
pub const NativeHostStub = struct {
    const Self = @This();

    /// No platform view is placed, so the loop collects no regions.
    pub const presents = false;

    /// Places nothing; the loop never calls it, as `presents` is false.
    ///
    /// - `window`: the main window.
    /// - `regions`: the frame's `NativeView` regions.
    /// - `overlay_open`: a sheet, alert, popover or menu is drawn this frame.
    pub fn present(window: *sdl_c.SDL_Window, regions: []const views.NativeRegion, overlay_open: bool) void {
        _ = window;
        _ = regions;
        _ = overlay_open;
    }

    /// No platform view holds the keyboard.
    ///
    /// - Returns: false.
    pub fn hasFocus() bool {
        return false;
    }

    /// Nothing to hand back.
    pub fn release() void {}

    /// No platform view takes editing keys.
    ///
    /// - `keycode`: the key's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
    /// - Returns: false.
    pub fn performEdit(keycode: u32, modifiers: u16) bool {
        _ = keycode;
        _ = modifiers;
        return false;
    }

    /// No platform view is shown.
    ///
    /// - `point`: the point, in the window's points.
    /// - Returns: false.
    pub fn contains(point: renderer.Point) bool {
        _ = point;
        return false;
    }

    /// Nothing to detach.
    pub fn detachAll() void {}
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "the stub places nothing and holds no focus" {
    try std.testing.expect(!NativeHostStub.presents);
    try std.testing.expect(!NativeHostStub.hasFocus());
    try std.testing.expect(!NativeHostStub.contains(.{ .x = 1, .y = 1 }));
}
