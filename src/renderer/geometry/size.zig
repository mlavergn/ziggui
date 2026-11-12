//! A 2D extent in logical coordinates.

const std = @import("std");
const log = std.log.scoped(.ziggui_size);
const mod = @import("module.zig");

/// A 2D extent (width × height) in logical coordinates.
pub const Size = struct {
    const Self = @This();

    /// The horizontal extent.
    width: f32 = 0,
    /// The vertical extent.
    height: f32 = 0,

    /// The size with no extent.
    pub const zero = Self{ .width = 0, .height = 0 };

    /// The area the size covers.
    ///
    /// - `self`: the size.
    /// - Returns: width times height.
    pub fn area(self: *const Self) f32 {
        return self.width * self.height;
    }

    /// Whether either dimension is zero (or negative).
    ///
    /// - `self`: the size.
    /// - Returns: true when the size covers nothing.
    pub fn isEmpty(self: *const Self) bool {
        return self.width <= 0 or self.height <= 0;
    }

    /// The size with both dimensions multiplied by `factor`.
    ///
    /// - `self`: the size.
    /// - `factor`: the multiplier.
    /// - Returns: the scaled size.
    pub fn scale(self: *const Self, factor: f32) Self {
        return .{ .width = self.width * factor, .height = self.height * factor };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Size: helpers" {
    const size = mod.Size{ .width = 10, .height = 20 };
    try std.testing.expectEqual(@as(f32, 200), size.area());
    try std.testing.expect(!size.isEmpty());
    try std.testing.expect((mod.Size{ .width = 0, .height = 5 }).isEmpty());
    try std.testing.expectEqual(mod.Size{ .width = 12, .height = 24 }, size.scale(1.2));
}
