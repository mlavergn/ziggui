//! What a press in a window does for the window manager.

const std = @import("std");
const log = std.log.scoped(.ziggui_window_hit);

/// What a point does when pressed (`WindowHitArea.at` finds it; `WindowHitTest`
/// maps it to `SDL_HITTEST_*`).
pub const WindowHit = enum {
    const Self = @This();

    /// Content: the app gets the press.
    normal,

    /// Empty title bar: the press drags the window (a double click maximizes).
    draggable,

    /// The top-left corner resizes the window.
    resizeTopLeft,

    /// The top edge resizes the window.
    resizeTop,

    /// The top-right corner resizes the window.
    resizeTopRight,

    /// The right edge resizes the window.
    resizeRight,

    /// The bottom-right corner resizes the window.
    resizeBottomRight,

    /// The bottom edge resizes the window.
    resizeBottom,

    /// The bottom-left corner resizes the window.
    resizeBottomLeft,

    /// The left edge resizes the window.
    resizeLeft,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
