//! Camera control: orbit and zoom the point-of-view node about the scene's
//! camera target (SceneKit's `allowsCameraControl`).

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_camera_control);
const mod = @import("module.zig");

/// Moves a scene's point-of-view node about `Scene.camera_target`: a drag
/// orbits it, a wheel or a pinch brings it nearer or farther, and it keeps
/// looking at the target. A scene with no point-of-view node is left alone.
pub const SceneCameraControl = struct {
    const Self = @This();

    /// The turn a point of drag makes, in radians.
    radians_per_point: f32 = 0.01,
    /// How much a line of wheel zooms (the distance shrinks by
    /// `exp(lines × zoom_per_line)`).
    zoom_per_line: f32 = 0.1,
    /// The nearest the camera comes to the target.
    min_distance: f32 = 0.5,
    /// The farthest it goes.
    max_distance: f32 = 100,

    /// The steepest the orbit looks down or up, short of straight, so the
    /// camera's up never flips.
    const max_pitch = std.math.pi / 2.0 - 0.01;

    /// Orbits the camera about the target: a drag right turns the scene
    /// right, a drag down tips it toward the viewer.
    ///
    /// - `self`: the control.
    /// - `scene`: the scene.
    /// - `delta_x`: the drag across, in points.
    /// - `delta_y`: the drag down, in points.
    /// - Returns: true when the camera moved.
    pub fn orbit(self: *const Self, scene: *mod.Scene, delta_x: f32, delta_y: f32) bool {
        const node = Self.cameraNode(scene) orelse return false;
        const offset = node.transform.position.sub(scene.camera_target);
        const distance = offset.length();
        if (distance == 0) return false;
        const yaw = std.math.atan2(offset.x, offset.z) - delta_x * self.radians_per_point;
        const pitch = std.math.clamp(std.math.asin(std.math.clamp(offset.y / distance, -1, 1)) + delta_y * self.radians_per_point, -max_pitch, max_pitch);
        const direction = mod.Vec3.init(@cos(pitch) * @sin(yaw), @sin(pitch), @cos(pitch) * @cos(yaw));
        node.transform.position = scene.camera_target.add(direction.scale(distance));
        node.lookAt(scene.camera_target, mod.Vec3.up);
        return true;
    }

    /// Brings the camera nearer the target (a factor above 1) or farther
    /// (below 1), between `min_distance` and `max_distance`.
    ///
    /// - `self`: the control.
    /// - `scene`: the scene.
    /// - `factor`: how much nearer: the distance is divided by it.
    /// - Returns: true when the camera moved.
    pub fn zoom(self: *const Self, scene: *mod.Scene, factor: f32) bool {
        if (!(factor > 0) or !std.math.isFinite(factor)) return false;
        const node = Self.cameraNode(scene) orelse return false;
        const offset = node.transform.position.sub(scene.camera_target);
        const distance = offset.length();
        if (distance == 0) return false;
        const zoomed = std.math.clamp(distance / factor, self.min_distance, self.max_distance);
        node.transform.position = scene.camera_target.add(offset.scale(zoomed / distance));
        node.lookAt(scene.camera_target, mod.Vec3.up);
        return zoomed != distance;
    }

    /// Zooms by a wheel's turn: up brings the camera nearer.
    ///
    /// - `self`: the control.
    /// - `scene`: the scene.
    /// - `lines`: the wheel's turn, positive up.
    /// - Returns: true when the camera moved.
    pub fn wheel(self: *const Self, scene: *mod.Scene, lines: f32) bool {
        // Bounded, so a huge turn zooms to a limit rather than overflowing.
        return self.zoom(scene, @exp(std.math.clamp(lines * self.zoom_per_line, -20, 20)));
    }

    /// The point-of-view node, when it is in the scene and carries the
    /// camera the scene is seen through (a node without one is not what the
    /// view shows, so moving it would move nothing on screen).
    ///
    /// - `scene`: the scene.
    /// - Returns: the node, or null for none.
    fn cameraNode(scene: *mod.Scene) ?*mod.SceneNode {
        const point_of_view = scene.point_of_view orelse return null;
        const node = scene.node(point_of_view) orelse return null;
        if (node.camera == null) return null;
        return node;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a drag orbits the camera about the target at the same distance, still looking at it" {
    var scene = try mod.Scene.init(std.testing.allocator);
    defer scene.deinit();
    scene.point_of_view = try scene.addChild(scene.root(), .{ .camera = .{}, .transform = .{ .position = mod.Vec3.init(0, 0, 5) } });
    const control = SceneCameraControl{};
    try std.testing.expect(control.orbit(&scene, -std.math.pi / 2.0 / control.radians_per_point, 0));
    const camera = scene.node(scene.point_of_view.?).?;
    // A quarter turn: from +Z round to +X, five units out, looking back at the origin.
    try std.testing.expect(camera.transform.position.approxEql(mod.Vec3.init(5, 0, 0), 1e-4));
    try std.testing.expect(camera.transform.rotation.rotate(mod.Vec3.init(0, 0, -1)).approxEql(mod.Vec3.init(-1, 0, 0), 1e-4));
    // Tipping stops short of straight down.
    _ = control.orbit(&scene, 0, 10_000);
    try std.testing.expect(camera.transform.position.y < 5 and camera.transform.position.y > 4.9);
    try std.testing.expectApproxEqAbs(@as(f32, 5), camera.transform.position.length(), 1e-4);
}

test "a wheel zooms toward the target within the limits; no point of view moves nothing" {
    var scene = try mod.Scene.init(std.testing.allocator);
    defer scene.deinit();
    const control = SceneCameraControl{};
    try std.testing.expect(!control.wheel(&scene, 1));
    scene.point_of_view = try scene.addChild(scene.root(), .{ .camera = .{}, .transform = .{ .position = mod.Vec3.init(0, 0, 5) } });
    try std.testing.expect(control.zoom(&scene, 2));
    try std.testing.expect(scene.node(scene.point_of_view.?).?.transform.position.approxEql(mod.Vec3.init(0, 0, 2.5), 1e-5));
    _ = control.wheel(&scene, 1000);
    try std.testing.expectApproxEqAbs(control.min_distance, scene.node(scene.point_of_view.?).?.transform.position.length(), 1e-5);
    try std.testing.expect(!control.zoom(&scene, 0));
    // A point of view with no camera is not what the view shows: left alone.
    scene.point_of_view = try scene.addChild(scene.root(), .{ .transform = .{ .position = mod.Vec3.init(0, 0, 5) } });
    try std.testing.expect(!control.orbit(&scene, 10, 0));
}
