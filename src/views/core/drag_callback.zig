//! What `View.onDrag` (and `PointerInput.armDrag`) calls as the pointer moves.

const std = @import("std");
const log = std.log.scoped(.ziggui_drag_callback);

/// A pointer-drag handler: gets the movement since the last event while the
/// button is held after a press inside the view.
pub const DragCallback = struct {
    const Self = @This();

    /// What `function` gets back.
    context: ?*anyopaque = null,

    /// The handler, given the movement across and down since the last event.
    function: *const fn (?*anyopaque, delta_x: f32, delta_y: f32) void,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
