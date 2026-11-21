//! What the popover window shows, and its size.

const std = @import("std");
const log = std.log.scoped(.ziggui_popover_window_specification);
const mod = @import("module.zig");
const views = @import("views");

/// A secondary, borderless window that hosts a view tree: the custom tray
/// popover (Swift's `MenuBarExtra(.window)` popover window). Created hidden; the app
/// shows it under the pointer via `PopoverWindow.show` (typically from a status-item
/// click). Drawn with the software rasterizer so it never competes with the
/// main window's GPU swapchain.
///
/// - `AppState`: the app's state type, which `body` builds from.
/// - Returns: the specification type.
pub fn PopoverWindowSpecification(comptime AppState: type) type {
    return struct {
        const Self = @This();

        /// Builds the popover window's view tree, once per frame while it is visible.
        ///
        /// - Returns: the popover window's view tree.
        body: *const fn (*AppState) views.View,

        /// Takes the popover window's mouse events (and only its: the main
        /// window's go to `App.setMouseHandler`'s handler), in its points,
        /// before its views do, as that handler does for the main window: a
        /// `ZoomState`'s wheel and pinch, say.
        ///
        /// - `state`: the app's state.
        /// - `event`: the mouse event.
        /// - Returns: true when it took the event, so the popover window's views do not.
        mouse: ?*const fn (state: *AppState, event: mod.MouseEvent) bool = null,

        /// Logical (point) width. HiDPI backing is handled like the main window.
        width: u32 = 340,

        /// Logical (point) height.
        height: u32 = 620,
    };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
