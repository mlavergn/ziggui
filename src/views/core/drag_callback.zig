//! What `View.onDrag` (and `PointerInput.armDrag`) calls as the pointer moves.

const std = @import("std");
const log = std.log.scoped(.ziggui_drag_callback);

/// A pointer-drag handler: gets the movement since the last event while the
/// button is held after a press inside the view, and hears when the press
/// arms it (`begin`) and when the button comes up (`end`).
pub const DragCallback = struct {
    const Self = @This();

    /// What `function`, `begin` and `end` get back.
    context: ?*anyopaque = null,

    /// The handler, given the movement across and down since the last event.
    function: *const fn (?*anyopaque, delta_x: f32, delta_y: f32) void,

    /// Called with `context` once when this armed drag ends (mouse-up),
    /// whether or not the pointer moved; null for none.
    end: ?*const fn (?*anyopaque) void = null,

    /// Called with `context` and `tag` when a press arms this drag, before any
    /// movement; null for none.
    begin: ?*const fn (?*anyopaque, tag: usize) void = null,

    /// Tells apart the views that share one `context` (a list row's index),
    /// for `begin`. An armed drag outlives the frame's build arena, so a
    /// per-view context allocated there would not.
    tag: usize = 0,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
