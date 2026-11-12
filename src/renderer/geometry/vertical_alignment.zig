//! A vertical alignment guide.

const std = @import("std");
const log = std.log.scoped(.ziggui_vertical_alignment);
const mod = @import("module.zig");

/// Vertical alignment guide. `fraction()` maps to a 0..1 position used when
/// placing a child in available height.
pub const VerticalAlignment = enum {
    const Self = @This();

    /// Against the top edge.
    top,
    /// Centered.
    center,
    /// Against the bottom edge.
    bottom,

    /// Where in the leftover height the child sits.
    ///
    /// - `self`: the alignment.
    /// - Returns: 0 for top, 0.5 for center, 1 for bottom.
    pub fn fraction(self: *const Self) f32 {
        return switch (self.*) {
            .top => 0.0,
            .center => 0.5,
            .bottom => 1.0,
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

test "VerticalAlignment: fractions" {
    try std.testing.expectEqual(@as(f32, 0.0), mod.VerticalAlignment.top.fraction());
    try std.testing.expectEqual(@as(f32, 1.0), mod.VerticalAlignment.bottom.fraction());
}
