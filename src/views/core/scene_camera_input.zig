//! The wheel and pinch that zoom a `SceneView`'s camera, from the app's
//! event loop, as `ZoomState` takes them for a picture.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_camera_input);
const mod = @import("module.zig");
const renderer = @import("renderer");
const scenes = @import("scenes");

/// Zooms a scene's camera from the app's wheel and pinch events (a drag
/// orbits it on its own, through the view). Each acts only when the view
/// lets gestures move the camera, the frame that drew it is still its
/// window's last, and the pointer is over the part of it on screen; the app
/// passes no events while an overlay covers the view.
pub const SceneCameraInput = struct {
    const Self = @This();

    /// Zooms by a wheel's turn over the view: up brings the camera nearer.
    ///
    /// - `scene`: the scene.
    /// - `point`: the pointer, in points.
    /// - `lines`: the wheel's turn, positive up.
    /// - Returns: true when the view took the turn.
    pub fn wheel(scene: *scenes.Scene, point: renderer.Point, lines: f32) bool {
        if (!Self.takes(scene, point)) return false;
        _ = (scenes.SceneCameraControl{}).wheel(scene, lines);
        return true;
    }

    /// Zooms by a pinch over the view: spreading brings the camera nearer.
    ///
    /// - `scene`: the scene.
    /// - `point`: the pointer, in points.
    /// - `scale`: the pinch's scale since its last event (above 1 spreading).
    /// - Returns: true when the view took the pinch.
    pub fn pinch(scene: *scenes.Scene, point: renderer.Point, scale: f32) bool {
        if (!Self.takes(scene, point)) return false;
        _ = (scenes.SceneCameraControl{}).zoom(scene, scale);
        return true;
    }

    /// Whether a gesture at a point reaches the scene's camera: the view
    /// allows it, its window's last frame drew it, and the point is on it.
    ///
    /// - `scene`: the scene.
    /// - `point`: the pointer, in points.
    /// - Returns: true when it does.
    fn takes(scene: *const scenes.Scene, point: renderer.Point) bool {
        const viewport = scene.viewport orelse return false;
        if (!viewport.camera_control) return false;
        const drawn = mod.FrameStamp{ .popover_window = viewport.popover_window, .number = viewport.frame_number };
        if (!mod.BuildScope.shared().isLatest(drawn)) return false;
        return viewport.shows(point.x, point.y);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a wheel zooms the camera only over a view drawn in the last frame that allows it" {
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    scene.point_of_view = try scene.addChild(scene.root(), .{ .camera = .{}, .transform = .{ .position = scenes.Vec3.init(0, 0, 5) } });
    const scope = mod.BuildScope.shared();
    const saved = scope.frame_number;
    defer scope.frame_number = saved;
    // Never drawn: nothing.
    try std.testing.expect(!SceneCameraInput.wheel(&scene, .{ .x = 10, .y = 10 }, 1));
    scene.viewport = .{ .rect = .{ 0, 0, 100, 100 }, .visible = .{ 0, 0, 100, 100 }, .frame_number = scope.frame_number, .popover_window = false, .camera_control = true };
    try std.testing.expect(SceneCameraInput.wheel(&scene, .{ .x = 10, .y = 10 }, 1));
    try std.testing.expect(scene.node(scene.point_of_view.?).?.transform.position.z < 5);
    // Off the view, a view that does not allow it, or a frame later: nothing.
    try std.testing.expect(!SceneCameraInput.pinch(&scene, .{ .x = 150, .y = 10 }, 2));
    scene.viewport.?.camera_control = false;
    try std.testing.expect(!SceneCameraInput.wheel(&scene, .{ .x = 10, .y = 10 }, 1));
    scene.viewport.?.camera_control = true;
    scope.frame_number +%= 1;
    try std.testing.expect(!SceneCameraInput.pinch(&scene, .{ .x = 10, .y = 10 }, 2));
}
