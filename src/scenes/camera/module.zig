//! Camera control: the gestures that move a scene's point of view.

const std = @import("std");
const log = std.log.scoped(.ziggui_camera_module);

/// A point or a direction in a scene.
pub const Vec3 = @import("../math/module.zig").Vec3;
/// A 3D scene.
pub const Scene = @import("../model/module.zig").Scene;
/// A node of a scene.
pub const SceneNode = @import("../model/module.zig").SceneNode;

/// Orbits and zooms a scene's point of view about its camera target.
pub const SceneCameraControl = @import("scene_camera_control.zig").SceneCameraControl;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("scene_camera_control.zig");
}
