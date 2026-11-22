//! A three-component vector: a point or a direction in a scene.

const std = @import("std");
const log = std.log.scoped(.ziggui_vec3);
const mod = @import("module.zig");

/// A point or a direction in a scene, in its units (right-handed, Y up).
pub const Vec3 = extern struct {
    const Self = @This();

    /// The x component.
    x: f32 = 0,
    /// The y component.
    y: f32 = 0,
    /// The z component.
    z: f32 = 0,

    /// The origin, or no direction.
    pub const zero = Self{};
    /// All components 1: a scale that changes nothing.
    pub const one = Self{ .x = 1, .y = 1, .z = 1 };
    /// The +Y axis, a scene's up.
    pub const up = Self{ .y = 1 };

    /// A vector of three components.
    ///
    /// - `x`: the x component.
    /// - `y`: the y component.
    /// - `z`: the z component.
    /// - Returns: the vector.
    pub fn init(x: f32, y: f32, z: f32) Self {
        const self = Self{ .x = x, .y = y, .z = z };
        return self;
    }

    /// The sum of two vectors.
    ///
    /// - `self`: the first.
    /// - `other`: the second.
    /// - Returns: the sum.
    pub fn add(self: *const Self, other: Self) Self {
        return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
    }

    /// The difference of two vectors.
    ///
    /// - `self`: the first.
    /// - `other`: the one taken from it.
    /// - Returns: the difference.
    pub fn sub(self: *const Self, other: Self) Self {
        return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }

    /// The vector scaled by a factor.
    ///
    /// - `self`: the vector.
    /// - `factor`: the factor.
    /// - Returns: the scaled vector.
    pub fn scale(self: *const Self, factor: f32) Self {
        return .{ .x = self.x * factor, .y = self.y * factor, .z = self.z * factor };
    }

    /// The component-wise product of two vectors.
    ///
    /// - `self`: the first.
    /// - `other`: the second.
    /// - Returns: the product.
    pub fn multiply(self: *const Self, other: Self) Self {
        return .{ .x = self.x * other.x, .y = self.y * other.y, .z = self.z * other.z };
    }

    /// The dot product of two vectors.
    ///
    /// - `self`: the first.
    /// - `other`: the second.
    /// - Returns: the dot product.
    pub fn dot(self: *const Self, other: Self) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    /// The cross product of two vectors (right-handed).
    ///
    /// - `self`: the first.
    /// - `other`: the second.
    /// - Returns: the cross product.
    pub fn cross(self: *const Self, other: Self) Self {
        return .{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    /// The vector's length.
    ///
    /// - `self`: the vector.
    /// - Returns: the length.
    pub fn length(self: *const Self) f32 {
        return @sqrt(self.dot(self.*));
    }

    /// The vector at length 1, or zero for a vector with no length.
    ///
    /// - `self`: the vector.
    /// - Returns: the unit vector.
    pub fn normalized(self: *const Self) Self {
        const magnitude = self.length();
        if (magnitude == 0 or !std.math.isFinite(magnitude)) return zero;
        return self.scale(1 / magnitude);
    }

    /// The smaller of each component of two vectors.
    ///
    /// - `self`: the first.
    /// - `other`: the second.
    /// - Returns: the component-wise minimum.
    pub fn min(self: *const Self, other: Self) Self {
        return .{ .x = @min(self.x, other.x), .y = @min(self.y, other.y), .z = @min(self.z, other.z) };
    }

    /// The larger of each component of two vectors.
    ///
    /// - `self`: the first.
    /// - `other`: the second.
    /// - Returns: the component-wise maximum.
    pub fn max(self: *const Self, other: Self) Self {
        return .{ .x = @max(self.x, other.x), .y = @max(self.y, other.y), .z = @max(self.z, other.z) };
    }

    /// Whether two vectors agree to within a tolerance in every component.
    ///
    /// - `self`: the first.
    /// - `other`: the second.
    /// - `tolerance`: the largest difference allowed.
    /// - Returns: true when they agree.
    pub fn approxEql(self: *const Self, other: Self, tolerance: f32) bool {
        return @abs(self.x - other.x) <= tolerance and @abs(self.y - other.y) <= tolerance and @abs(self.z - other.z) <= tolerance;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = mod;
}

test "the cross product of X and Y is Z, and a normalized vector has length 1" {
    const x_axis = Vec3.init(1, 0, 0);
    const y_axis = Vec3.init(0, 1, 0);
    try std.testing.expect(x_axis.cross(y_axis).approxEql(Vec3.init(0, 0, 1), 1e-6));
    try std.testing.expectApproxEqAbs(@as(f32, 1), Vec3.init(3, 4, 12).normalized().length(), 1e-6);
    try std.testing.expectEqual(Vec3.zero, Vec3.zero.normalized());
}
