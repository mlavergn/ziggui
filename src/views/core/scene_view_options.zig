//! How a `SceneView` draws its scene and takes gestures.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_view_options);
const mod = @import("module.zig");

/// How a `SceneView` draws its scene and takes gestures (SceneKit's
/// `SceneView` options).
pub const SceneViewOptions = struct {
    const Self = @This();

    /// Whether gestures move the camera (SceneKit's `allowsCameraControl`):
    /// a drag orbits the point-of-view node about `Scene.camera_target`, and
    /// a wheel or pinch the app passes to `SceneCameraInput` zooms it.
    allows_camera_control: bool = false,
    /// Whether the scene moves on its own, so the view asks for a frame
    /// every 16 ms while it shows (the app moves its nodes as it builds).
    animating: bool = false,
    /// What the view says it shows, to accessibility.
    label: []const u8 = "3D scene",
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = mod;
}
