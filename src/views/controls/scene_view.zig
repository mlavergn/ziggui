//! A 3D scene in the view tree (SwiftUI's SceneKit `SceneView`).

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_view);
const mod = @import("module.zig");
const scenes = @import("scenes");

/// Shows an app-owned 3D scene seen from its point of view, drawn on the GPU
/// with a depth buffer: what is painted before it shows behind it (where
/// the scene has no background), what is painted after it on top. It fills
/// what it is offered (size it with `.frame`); its corners stay square. The
/// software renderer, and a headless `--screenshot`, draw a placeholder: the
/// frame with a cube. With `allows_camera_control` a drag orbits the camera;
/// the app passes a wheel or pinch to `SceneCameraInput`. `.opacity()` has no
/// effect on it: fade nodes with `SceneNode.opacity`.
///
/// - `scene`: the scene; it must outlive the frames that show it.
/// - `options`: camera control, animation and its accessibility label.
/// - Returns: the view.
pub fn SceneView(scene: *scenes.Scene, options: mod.SceneViewOptions) mod.View {
    const view = mod.View{ .kind = .{ .sceneView = .{ .scene = scene, .options = options } } };
    if (!options.allows_camera_control) return view;
    // The scene is the drag's context: it outlives the frame, as an armed drag does.
    return view.onDrag(.{ .context = scene, .function = SceneDrag.orbit }).pointerStyle(.grabIdle);
}

/// The drag that orbits a scene's camera.
const SceneDrag = struct {
    const Self = @This();

    /// Orbits the camera by a drag's movement.
    ///
    /// - `context`: the scene.
    /// - `delta_x`: the movement across, in points.
    /// - `delta_y`: the movement down, in points.
    fn orbit(context: ?*anyopaque, delta_x: f32, delta_y: f32) void {
        const scene: *scenes.Scene = @ptrCast(@alignCast(context orelse return));
        _ = (scenes.SceneCameraControl{}).orbit(scene, delta_x, delta_y);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "SceneView carries its scene, and orbits by a drag only with camera control" {
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    const still = SceneView(&scene, .{});
    try std.testing.expectEqual(&scene, still.kind.sceneView.scene);
    try std.testing.expect(still.modifiers.on_drag == null);

    scene.point_of_view = try scene.addChild(scene.root(), .{ .camera = .{}, .transform = .{ .position = scenes.Vec3.init(0, 0, 5) } });
    const controlled = SceneView(&scene, .{ .allows_camera_control = true });
    const drag = controlled.modifiers.on_drag.?;
    drag.function(drag.context, 100, 0);
    try std.testing.expect(scene.node(scene.point_of_view.?).?.transform.position.x != 0);
}
