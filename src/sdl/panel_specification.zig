//! What the popover panel window shows, and its size.

const std = @import("std");
const log = std.log.scoped(.ziggui_panel_specification);
const views = @import("views");

/// A secondary, borderless window that hosts a view tree: the custom tray
/// popover (Swift's `MenuBarExtra(.window)` panel). Created hidden; the app
/// shows it under the pointer via `Panel.show` (typically from a status-item
/// click). Drawn with the software rasterizer so it never competes with the
/// main window's GPU swapchain.
///
/// - `AppState`: the app's state type, which `body` builds from.
/// - Returns: the specification type.
pub fn PanelSpecification(comptime AppState: type) type {
    return struct {
        const Self = @This();

        /// Builds the panel's view tree, once per frame while it is visible.
        body: *const fn (*AppState) views.View,

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
