//! The two layout axes.

const std = @import("std");
const log = std.log.scoped(.ziggui_axis);
const mod = @import("module.zig");

/// The two layout axes. Stacks lay out along their main axis.
pub const Axis = enum {
    const Self = @This();

    /// Left to right.
    horizontal,
    /// Top to bottom.
    vertical,

    /// The other axis.
    ///
    /// - `self`: the axis.
    /// - Returns: the perpendicular axis.
    pub fn cross(self: *const Self) Self {
        return switch (self.*) {
            .horizontal => .vertical,
            .vertical => .horizontal,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Axis: cross axis" {
    try std.testing.expectEqual(mod.Axis.vertical, mod.Axis.horizontal.cross());
    try std.testing.expectEqual(mod.Axis.horizontal, mod.Axis.vertical.cross());
}
