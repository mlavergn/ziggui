//! A 2D point in logical coordinates.

const std = @import("std");
const log = std.log.scoped(.ziggui_point);
const mod = @import("module.zig");

/// A 2D point in logical (DPI-independent) coordinates. +x is right, +y down,
/// matching screen/UI conventions.
pub const Point = struct {
    const Self = @This();

    /// The horizontal coordinate.
    x: f32 = 0,
    /// The vertical coordinate.
    y: f32 = 0,

    /// The component-wise sum of two points.
    ///
    /// - `self`: the first point.
    /// - `other`: the point added.
    /// - Returns: the sum.
    pub fn add(self: *const Self, other: Self) Self {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    /// The component-wise difference of two points.
    ///
    /// - `self`: the point subtracted from.
    /// - `other`: the point subtracted.
    /// - Returns: the difference.
    pub fn sub(self: *const Self, other: Self) Self {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    /// The point with both coordinates multiplied by `factor`.
    ///
    /// - `self`: the point.
    /// - `factor`: the multiplier.
    /// - Returns: the scaled point.
    pub fn scale(self: *const Self, factor: f32) Self {
        return .{ .x = self.x * factor, .y = self.y * factor };
    }

    /// The Euclidean distance between two points.
    ///
    /// - `self`: the first point.
    /// - `other`: the second point.
    /// - Returns: the distance.
    pub fn distance(self: *const Self, other: Self) f32 {
        const delta_x = self.x - other.x;
        const delta_y = self.y - other.y;
        return @sqrt(delta_x * delta_x + delta_y * delta_y);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Point: arithmetic and distance" {
    const first = mod.Point{ .x = 1, .y = 2 };
    const second = mod.Point{ .x = 4, .y = 6 };
    try std.testing.expectEqual(mod.Point{ .x = 5, .y = 8 }, first.add(second));
    try std.testing.expectEqual(mod.Point{ .x = 3, .y = 4 }, second.sub(first));
    try std.testing.expectEqual(@as(f32, 5), first.distance(second)); // 3-4-5 triangle
    try std.testing.expectEqual(mod.Point{ .x = 2, .y = 4 }, first.scale(2));
}
