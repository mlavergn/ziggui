//! A camera a node carries: the scene seen from the node, down its -Z.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_camera);
const mod = @import("module.zig");

/// A perspective camera a node carries, looking down the node's -Z with its
/// +Y up (SceneKit's `SCNCamera`). The scene is seen through the node
/// `Scene.point_of_view` names.
pub const SceneCamera = struct {
    const Self = @This();

    /// The vertical field of view, in degrees.
    field_of_view: f32 = 60,
    /// The nearest distance drawn.
    near: f32 = 0.1,
    /// The farthest distance drawn.
    far: f32 = 100,

    /// The projection for a view of the given aspect.
    ///
    /// - `self`: the camera.
    /// - `aspect`: the view's width over its height.
    /// - Returns: the projection; a degenerate camera (a field of view outside
    ///   1° to 179°, `near` not above 0 or `far` not beyond it) draws as the default.
    pub fn projection(self: *const Self, aspect: f32) mod.Mat4 {
        const camera = if (self.isUsable()) self.* else Self{};
        const safe_aspect = if (aspect > 0 and std.math.isFinite(aspect)) aspect else 1;
        return mod.Mat4.perspective(std.math.degreesToRadians(camera.field_of_view), safe_aspect, camera.near, camera.far);
    }

    /// Whether the camera can project: a field of view between 1° and 179°,
    /// `near` above 0 and `far` beyond it.
    ///
    /// - `self`: the camera.
    /// - Returns: true when it can.
    fn isUsable(self: *const Self) bool {
        return self.field_of_view >= 1 and self.field_of_view <= 179 and self.near > 0 and self.far > self.near and std.math.isFinite(self.far);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a degenerate camera projects as the default one" {
    const fallback = (SceneCamera{}).projection(1.5);
    try std.testing.expect((SceneCamera{ .near = 0 }).projection(1.5).approxEql(fallback, 0));
    try std.testing.expect((SceneCamera{ .field_of_view = 0 }).projection(1.5).approxEql(fallback, 0));
    try std.testing.expect((SceneCamera{}).projection(0).approxEql((SceneCamera{}).projection(1), 0));
}
