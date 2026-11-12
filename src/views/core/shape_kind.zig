//! The shapes a shape view draws.

const std = @import("std");
const log = std.log.scoped(.ziggui_shape_kind);

/// The outline a shape view fills.
pub const ShapeKind = enum {
    const Self = @This();

    /// A sharp-cornered rectangle.
    rect,
    /// A rectangle with rounded corners.
    roundedRect,
    /// A circle inscribed in the frame.
    circle,
    /// A rectangle whose ends are half circles.
    capsule,
    /// An ellipse filling the frame.
    ellipse,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
