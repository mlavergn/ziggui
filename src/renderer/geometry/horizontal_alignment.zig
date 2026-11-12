//! A horizontal alignment guide.

const std = @import("std");
const log = std.log.scoped(.ziggui_horizontal_alignment);
const mod = @import("module.zig");

/// Horizontal alignment guide. `fraction()` maps to a 0..1 position used when
/// placing a child in available width.
pub const HorizontalAlignment = enum {
    const Self = @This();

    /// Against the leading (left) edge.
    leading,
    /// Centered.
    center,
    /// Against the trailing (right) edge.
    trailing,

    /// Where in the leftover width the child sits.
    ///
    /// - `self`: the alignment.
    /// - Returns: 0 for leading, 0.5 for center, 1 for trailing.
    pub fn fraction(self: *const Self) f32 {
        return switch (self.*) {
            .leading => 0.0,
            .center => 0.5,
            .trailing => 1.0,
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

test "HorizontalAlignment: fractions" {
    try std.testing.expectEqual(@as(f32, 0.0), mod.HorizontalAlignment.leading.fraction());
    try std.testing.expectEqual(@as(f32, 0.5), mod.HorizontalAlignment.center.fraction());
    try std.testing.expectEqual(@as(f32, 1.0), mod.HorizontalAlignment.trailing.fraction());
}
