//! A four-component vector: a point in homogeneous coordinates, or a column
//! of a `Mat4`.

const std = @import("std");
const log = std.log.scoped(.ziggui_vec4);
const mod = @import("module.zig");

/// A point in homogeneous coordinates (`w` 1 for a point, 0 for a
/// direction), or one column of a `Mat4`.
pub const Vec4 = extern struct {
    const Self = @This();

    /// The x component.
    x: f32 = 0,
    /// The y component.
    y: f32 = 0,
    /// The z component.
    z: f32 = 0,
    /// The w component.
    w: f32 = 0,

    /// A vector of four components.
    ///
    /// - `x`: the x component.
    /// - `y`: the y component.
    /// - `z`: the z component.
    /// - `w`: the w component.
    /// - Returns: the vector.
    pub fn init(x: f32, y: f32, z: f32, w: f32) Self {
        const self = Self{ .x = x, .y = y, .z = z, .w = w };
        return self;
    }

    /// A point or direction with its `w`.
    ///
    /// - `vector`: the point or direction.
    /// - `w`: 1 for a point, 0 for a direction.
    /// - Returns: the vector.
    pub fn fromVec3(vector: mod.Vec3, w: f32) Self {
        const self = Self{ .x = vector.x, .y = vector.y, .z = vector.z, .w = w };
        return self;
    }

    /// The first three components, divided by `w` when it is neither 0 nor 1
    /// (a projected point).
    ///
    /// - `self`: the vector.
    /// - Returns: the point.
    pub fn toVec3(self: *const Self) mod.Vec3 {
        if (self.w == 0 or self.w == 1) return .{ .x = self.x, .y = self.y, .z = self.z };
        return .{ .x = self.x / self.w, .y = self.y / self.w, .z = self.z / self.w };
    }

    /// The vector's components as an array.
    ///
    /// - `self`: the vector.
    /// - Returns: x, y, z and w.
    pub fn toArray(self: *const Self) [4]f32 {
        return .{ self.x, self.y, self.z, self.w };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a projected point divides by w; a point or direction keeps its components" {
    try std.testing.expect(Vec4.init(2, 4, 6, 2).toVec3().approxEql(mod.Vec3.init(1, 2, 3), 1e-6));
    try std.testing.expect(Vec4.fromVec3(mod.Vec3.init(1, 2, 3), 0).toVec3().approxEql(mod.Vec3.init(1, 2, 3), 1e-6));
}
