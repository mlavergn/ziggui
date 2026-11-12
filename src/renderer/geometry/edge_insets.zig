//! Per-side spacing in SwiftUI's leading/trailing vocabulary.

const std = @import("std");
const log = std.log.scoped(.ziggui_edge_insets);
const mod = @import("module.zig");

/// Per-side spacing using SwiftUI's leading/trailing vocabulary (LTR: leading =
/// left, trailing = right).
pub const EdgeInsets = struct {
    const Self = @This();

    /// The space above.
    top: f32 = 0,
    /// The space before (left, left-to-right).
    leading: f32 = 0,
    /// The space below.
    bottom: f32 = 0,
    /// The space after (right, left-to-right).
    trailing: f32 = 0,

    /// No space on any side.
    pub const zero = Self{};

    /// The same space on every side.
    ///
    /// - `amount`: the space.
    /// - Returns: the insets.
    pub fn all(amount: f32) Self {
        return .{ .top = amount, .leading = amount, .bottom = amount, .trailing = amount };
    }

    /// One space on the leading and trailing sides, another on the top and
    /// bottom.
    ///
    /// - `horizontal_amount`: the leading and trailing space.
    /// - `vertical_amount`: the top and bottom space.
    /// - Returns: the insets.
    pub fn symmetric(horizontal_amount: f32, vertical_amount: f32) Self {
        return .{ .top = vertical_amount, .leading = horizontal_amount, .bottom = vertical_amount, .trailing = horizontal_amount };
    }

    /// The leading and trailing space together.
    ///
    /// - `self`: the insets.
    /// - Returns: leading plus trailing.
    pub fn horizontal(self: *const Self) f32 {
        return self.leading + self.trailing;
    }

    /// The top and bottom space together.
    ///
    /// - `self`: the insets.
    /// - Returns: top plus bottom.
    pub fn vertical(self: *const Self) f32 {
        return self.top + self.bottom;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "EdgeInsets: constructors and sums" {
    try std.testing.expectEqual(
        mod.EdgeInsets{ .top = 5, .leading = 5, .bottom = 5, .trailing = 5 },
        mod.EdgeInsets.all(5),
    );
    try std.testing.expectEqual(
        mod.EdgeInsets{ .top = 2, .leading = 3, .bottom = 2, .trailing = 3 },
        mod.EdgeInsets.symmetric(3, 2),
    );
    const insets = mod.EdgeInsets{ .top = 1, .leading = 2, .bottom = 3, .trailing = 4 };
    try std.testing.expectEqual(@as(f32, 6), insets.horizontal());
    try std.testing.expectEqual(@as(f32, 4), insets.vertical());
}
