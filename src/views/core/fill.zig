//! What a background or a shape is filled with: a color, a gradient, or a
//! material.

const std = @import("std");
const log = std.log.scoped(.ziggui_fill);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A two-color linear gradient along `start` to `end`, in unit points (0..1)
/// of the filled rect, like SwiftUI's `UnitPoint`.
pub const GradientFill = struct {
    const Self = @This();

    /// The color at `start`.
    start_color: renderer.Color,

    /// The color at `end`.
    end_color: renderer.Color,

    /// Where the gradient starts, in unit points.
    start: renderer.Point,

    /// Where it ends, in unit points.
    end: renderer.Point,
};

/// What a background or a shape is filled with.
pub const Fill = union(enum) {
    const Self = @This();

    /// A flat color.
    color: renderer.Color,

    /// A linear gradient.
    linearGradient: GradientFill,

    /// A frosted material.
    material: mod.Material,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
