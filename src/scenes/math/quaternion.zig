//! A rotation as a unit quaternion.

const std = @import("std");
const log = std.log.scoped(.ziggui_quaternion);
const mod = @import("module.zig");

/// A rotation as a unit quaternion (`w` the scalar part).
pub const Quaternion = extern struct {
    const Self = @This();

    /// The x component of the vector part.
    x: f32 = 0,
    /// The y component of the vector part.
    y: f32 = 0,
    /// The z component of the vector part.
    z: f32 = 0,
    /// The scalar part.
    w: f32 = 1,

    /// No rotation.
    pub const identity = Self{};

    /// A rotation about an axis.
    ///
    /// - `axis`: the axis (any length but zero).
    /// - `angle`: the angle, in radians, counter-clockwise looking down the axis.
    /// - Returns: the rotation; none for a zero axis.
    pub fn fromAxisAngle(axis: mod.Vec3, angle: f32) Self {
        const unit = axis.normalized();
        if (unit.length() == 0) return identity;
        const half = angle / 2;
        const sine = @sin(half);
        const self = Self{ .x = unit.x * sine, .y = unit.y * sine, .z = unit.z * sine, .w = @cos(half) };
        return self;
    }

    /// The rotation whose basis is the given unit axes (a rotation matrix's
    /// columns: where X, Y and Z go).
    ///
    /// - `right`: where X goes.
    /// - `up`: where Y goes.
    /// - `back`: where Z goes.
    /// - Returns: the rotation.
    pub fn fromBasis(right: mod.Vec3, up: mod.Vec3, back: mod.Vec3) Self {
        // Shepperd's method: the largest of the four candidates keeps precision.
        const trace = right.x + up.y + back.z;
        var self: Self = undefined;
        if (trace > 0) {
            const factor = @sqrt(trace + 1) * 2;
            self = .{ .w = factor / 4, .x = (up.z - back.y) / factor, .y = (back.x - right.z) / factor, .z = (right.y - up.x) / factor };
        } else if (right.x > up.y and right.x > back.z) {
            const factor = @sqrt(1 + right.x - up.y - back.z) * 2;
            self = .{ .w = (up.z - back.y) / factor, .x = factor / 4, .y = (up.x + right.y) / factor, .z = (back.x + right.z) / factor };
        } else if (up.y > back.z) {
            const factor = @sqrt(1 + up.y - right.x - back.z) * 2;
            self = .{ .w = (back.x - right.z) / factor, .x = (up.x + right.y) / factor, .y = factor / 4, .z = (back.y + up.z) / factor };
        } else {
            const factor = @sqrt(1 + back.z - right.x - up.y) * 2;
            self = .{ .w = (right.y - up.x) / factor, .x = (back.x + right.z) / factor, .y = (back.y + up.z) / factor, .z = factor / 4 };
        }
        return self.normalized();
    }

    /// The rotation that turns `-Z` toward `forward`, keeping `up` as near
    /// to up as it can (a camera or a light looking along `forward`).
    ///
    /// - `forward`: the direction to look along.
    /// - `up`: the direction up should lean toward.
    /// - Returns: the rotation; none for a zero `forward`.
    pub fn lookRotation(forward: mod.Vec3, up: mod.Vec3) Self {
        const back = forward.normalized().scale(-1);
        if (back.length() == 0) return identity;
        var right = up.cross(back).normalized();
        // Looking straight along `up`: lean on another axis instead.
        if (right.length() == 0) right = mod.Vec3.init(0, 0, 1).cross(back).normalized();
        if (right.length() == 0) right = mod.Vec3.init(1, 0, 0);
        const true_up = back.cross(right);
        return Self.fromBasis(right, true_up, back);
    }

    /// The rotation `other` then this one.
    ///
    /// - `self`: the rotation applied second.
    /// - `other`: the rotation applied first.
    /// - Returns: the combined rotation.
    pub fn multiply(self: *const Self, other: Self) Self {
        return .{
            .w = self.w * other.w - self.x * other.x - self.y * other.y - self.z * other.z,
            .x = self.w * other.x + self.x * other.w + self.y * other.z - self.z * other.y,
            .y = self.w * other.y - self.x * other.z + self.y * other.w + self.z * other.x,
            .z = self.w * other.z + self.x * other.y - self.y * other.x + self.z * other.w,
        };
    }

    /// A vector rotated.
    ///
    /// - `self`: the rotation.
    /// - `vector`: the vector.
    /// - Returns: the rotated vector.
    pub fn rotate(self: *const Self, vector: mod.Vec3) mod.Vec3 {
        const axis = mod.Vec3.init(self.x, self.y, self.z);
        const twice_cross = axis.cross(vector).scale(2);
        return vector.add(twice_cross.scale(self.w)).add(axis.cross(twice_cross));
    }

    /// The rotation at length 1, or none for a quaternion with no length.
    ///
    /// - `self`: the quaternion.
    /// - Returns: the unit quaternion.
    pub fn normalized(self: *const Self) Self {
        const magnitude = @sqrt(self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w);
        if (magnitude == 0 or !std.math.isFinite(magnitude)) return identity;
        return .{ .x = self.x / magnitude, .y = self.y / magnitude, .z = self.z / magnitude, .w = self.w / magnitude };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a quarter turn about Y takes X to -Z, and two compose into a half turn" {
    const quarter = Quaternion.fromAxisAngle(mod.Vec3.up, std.math.pi / 2.0);
    try std.testing.expect(quarter.rotate(mod.Vec3.init(1, 0, 0)).approxEql(mod.Vec3.init(0, 0, -1), 1e-6));
    const half = quarter.multiply(quarter);
    try std.testing.expect(half.rotate(mod.Vec3.init(1, 0, 0)).approxEql(mod.Vec3.init(-1, 0, 0), 1e-6));
}

test "a look rotation turns -Z toward the direction, its up kept upward" {
    const forward = mod.Vec3.init(1, -1, -1).normalized();
    const rotation = Quaternion.lookRotation(forward, mod.Vec3.up);
    try std.testing.expect(rotation.rotate(mod.Vec3.init(0, 0, -1)).approxEql(forward, 1e-5));
    try std.testing.expect(rotation.rotate(mod.Vec3.up).y > 0);
    // Straight down still gives a rotation that looks there.
    const down = Quaternion.lookRotation(mod.Vec3.init(0, -1, 0), mod.Vec3.up);
    try std.testing.expect(down.rotate(mod.Vec3.init(0, 0, -1)).approxEql(mod.Vec3.init(0, -1, 0), 1e-5));
}
