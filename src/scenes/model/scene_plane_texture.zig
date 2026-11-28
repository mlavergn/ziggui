//! A texture laid on a plane in a scene's space.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_plane_texture);
const mod = @import("module.zig");

/// A texture laid on a plane in the scene's space, repeating across it:
/// `origin` is where its texture coordinates are (0, 0), and `u_axis` and
/// `v_axis` span one repeat (their lengths are the texture's size on the
/// plane, and the plane is the one they span: level, upright or tilted;
/// they needn't be square to each other).
///
/// What a ray sees of it is its texel where the ray crosses the plane ahead.
/// A directional light's `cookie` is one: the light reaching a point is
/// scaled by the texel where the ray toward the light crosses it (a cloud
/// layer's shadow). A `SceneEnvironment`'s `overlays` are others, laid over
/// the sky a reflection sees by the texel's alpha (the clouds themselves).
/// Moving `origin` slides the texture across the plane (the clouds drifting).
pub const ScenePlaneTexture = struct {
    const Self = @This();

    /// The texture; it repeats.
    texture: mod.SceneTexture,
    /// Where on the plane its texture coordinates are (0, 0), in the scene's space.
    origin: mod.Vec3,
    /// One repeat of the texture along its u, in the scene's space.
    u_axis: mod.Vec3,
    /// One repeat along its v.
    v_axis: mod.Vec3,

    /// A texture on a level plane through `origin`, repeating every `tile`
    /// along +X (its u) and +Z (its v).
    ///
    /// - `texture`: the texture.
    /// - `origin`: where its texture coordinates are (0, 0); its height is the plane's.
    /// - `tile`: the texture's size on the plane, each way.
    /// - Returns: the plane texture.
    pub fn level(texture: mod.SceneTexture, origin: mod.Vec3, tile: f32) Self {
        return .{ .texture = texture, .origin = origin, .u_axis = mod.Vec3.init(tile, 0, 0), .v_axis = mod.Vec3.init(0, 0, tile) };
    }

    /// Whether it can be drawn: its numbers finite and its axes spanning a plane.
    ///
    /// - `self`: the plane texture.
    /// - Returns: true when it can.
    pub fn isUsable(self: *const Self) bool {
        const numbers = [_]f32{ self.origin.x, self.origin.y, self.origin.z, self.u_axis.x, self.u_axis.y, self.u_axis.z, self.v_axis.x, self.v_axis.y, self.v_axis.z };
        for (numbers) |number| if (!std.math.isFinite(number)) return false;
        const span = self.u_axis.cross(self.v_axis).length();
        return span > 1e-6 * self.u_axis.length() * self.v_axis.length();
    }

    /// The plane's equations, as a shader evaluates them at a point p: its
    /// u is dot(p, u.xyz) + u.w, its v likewise, and it lies on the plane
    /// where dot(p, plane.xyz) + plane.w is 0 (plane.xyz its unit normal,
    /// along `u_axis` × `v_axis`).
    ///
    /// - `self`: the plane texture; usable (`isUsable`).
    /// - Returns: the u, v and plane rows.
    pub fn equations(self: *const Self) [3][4]f32 {
        const perpendicular = self.u_axis.cross(self.v_axis);
        const normal = perpendicular.normalized();
        // The axes' duals: each is square to the other axis and dots to 1 with its own.
        const across_v = self.v_axis.cross(perpendicular);
        const across_u = perpendicular.cross(self.u_axis);
        const u = across_v.scale(1 / self.u_axis.dot(across_v));
        const v = across_u.scale(1 / self.v_axis.dot(across_u));
        return .{
            .{ u.x, u.y, u.z, -u.dot(self.origin) },
            .{ v.x, v.y, v.z, -v.dot(self.origin) },
            .{ normal.x, normal.y, normal.z, -normal.dot(self.origin) },
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

/// Reads a plane texture's `equations` back, as the traced shader does.
const PlaneProbe = struct {
    const Self = @This();

    /// A row of `equations` at a point.
    ///
    /// - `row`: the u, v or plane row.
    /// - `point`: the point, in the scene's space.
    /// - Returns: the row's value there.
    fn evaluate(row: [4]f32, point: mod.Vec3) f32 {
        return row[0] * point.x + row[1] * point.y + row[2] * point.z + row[3];
    }
};

test "a plane texture's equations map one repeat to one, square axes or not" {
    const pixels = [_]u8{ 255, 255, 255, 255 };
    const texture = mod.SceneTexture{ .image = .{ .width = 1, .height = 1, .pixels = &pixels } };
    const level = ScenePlaneTexture.level(texture, mod.Vec3.init(1, 10, 0), 4);
    try std.testing.expect(level.isUsable());
    const flat = level.equations();
    // 2 m past the origin along +X is half a repeat along u; the plane is at height 10.
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), PlaneProbe.evaluate(flat[0], mod.Vec3.init(3, 10, 7)), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1.75), PlaneProbe.evaluate(flat[1], mod.Vec3.init(3, 10, 7)), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), PlaneProbe.evaluate(flat[2], mod.Vec3.init(-5, 10, 2)), 1e-6);
    const slanted = ScenePlaneTexture{ .texture = texture, .origin = mod.Vec3.init(1, 1, 1), .u_axis = mod.Vec3.init(2, 0, 0), .v_axis = mod.Vec3.init(1, 3, 0) };
    const rows = slanted.equations();
    const corner = slanted.origin.add(slanted.u_axis).add(slanted.v_axis.scale(0.5));
    try std.testing.expectApproxEqAbs(@as(f32, 1), PlaneProbe.evaluate(rows[0], corner), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), PlaneProbe.evaluate(rows[1], corner), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), PlaneProbe.evaluate(rows[2], corner), 1e-5);
    const line = ScenePlaneTexture{ .texture = texture, .origin = mod.Vec3.zero, .u_axis = mod.Vec3.init(1, 0, 0), .v_axis = mod.Vec3.init(2, 0, 0) };
    try std.testing.expect(!line.isUsable());
}
