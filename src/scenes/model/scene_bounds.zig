//! An axis-aligned box that holds geometry: what shadows are fitted to.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_bounds);
const mod = @import("module.zig");

/// An axis-aligned box from `min` to `max`, empty while `min` exceeds `max`.
pub const SceneBounds = struct {
    const Self = @This();

    /// The corner with the smallest components.
    min: mod.Vec3 = .{ .x = std.math.inf(f32), .y = std.math.inf(f32), .z = std.math.inf(f32) },
    /// The corner with the largest components.
    max: mod.Vec3 = .{ .x = -std.math.inf(f32), .y = -std.math.inf(f32), .z = -std.math.inf(f32) },

    /// The box holding nothing.
    pub const empty = Self{};

    /// The box from one corner to the other.
    ///
    /// - `min`: the corner with the smallest components.
    /// - `max`: the corner with the largest components.
    /// - Returns: the box.
    pub fn init(min: mod.Vec3, max: mod.Vec3) Self {
        const self = Self{ .min = min, .max = max };
        return self;
    }

    /// Whether the box holds nothing.
    ///
    /// - `self`: the box.
    /// - Returns: true when empty.
    pub fn isEmpty(self: *const Self) bool {
        return self.min.x > self.max.x or self.min.y > self.max.y or self.min.z > self.max.z;
    }

    /// The box grown to hold a point.
    ///
    /// - `self`: the box.
    /// - `point`: the point.
    /// - Returns: the grown box.
    pub fn including(self: *const Self, point: mod.Vec3) Self {
        return .{ .min = self.min.min(point), .max = self.max.max(point) };
    }

    /// The box grown to hold another.
    ///
    /// - `self`: the box.
    /// - `other`: the other box.
    /// - Returns: the grown box.
    pub fn merged(self: *const Self, other: Self) Self {
        if (other.isEmpty()) return self.*;
        return .{ .min = self.min.min(other.min), .max = self.max.max(other.max) };
    }

    /// The box's eight corners.
    ///
    /// - `self`: the box.
    /// - Returns: the corners.
    pub fn corners(self: *const Self) [8]mod.Vec3 {
        var points: [8]mod.Vec3 = undefined;
        for (&points, 0..) |*point, index| point.* = .{
            .x = if (index & 1 == 0) self.min.x else self.max.x,
            .y = if (index & 2 == 0) self.min.y else self.max.y,
            .z = if (index & 4 == 0) self.min.z else self.max.z,
        };
        return points;
    }

    /// The axis-aligned box holding this one after a transform.
    ///
    /// - `self`: the box.
    /// - `matrix`: the transform.
    /// - Returns: the transformed box; empty for an empty one.
    pub fn transformed(self: *const Self, matrix: mod.Mat4) Self {
        if (self.isEmpty()) return empty;
        var result = empty;
        for (self.corners()) |corner| result = result.including(matrix.transformPoint(corner));
        return result;
    }

    /// The box's center.
    ///
    /// - `self`: the box.
    /// - Returns: the center; the origin for an empty box.
    pub fn center(self: *const Self) mod.Vec3 {
        if (self.isEmpty()) return mod.Vec3.zero;
        return self.min.add(self.max).scale(0.5);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "bounds grow to hold points and boxes, and move with a transform" {
    try std.testing.expect(SceneBounds.empty.isEmpty());
    const box = SceneBounds.empty.including(mod.Vec3.init(-1, -1, -1)).including(mod.Vec3.init(1, 1, 1));
    try std.testing.expect(!box.isEmpty());
    const moved = box.transformed(mod.Mat4.translation(mod.Vec3.init(2, 0, 0)));
    try std.testing.expect(moved.center().approxEql(mod.Vec3.init(2, 0, 0), 1e-6));
    try std.testing.expect(box.merged(SceneBounds.empty).max.approxEql(box.max, 0));
}
