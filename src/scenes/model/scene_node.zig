//! A node of a scene: its place, and what it shows, lights or sees from.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_node);
const mod = @import("module.zig");

/// A node of a `Scene` (SceneKit's `SCNNode`): a transform in its parent's
/// space and, each optional, a shape with its material, a light and a
/// camera, all moving with it and its children. The scene keeps its parent.
pub const SceneNode = struct {
    const Self = @This();

    /// A name for the app's own use.
    name: []const u8 = "",
    /// Its place in its parent's space.
    transform: mod.SceneTransform = .{},
    /// The shape it shows, or null for none.
    geometry: ?mod.SceneGeometry = null,
    /// How its shape's surface looks.
    material: mod.SceneMaterial = .{},
    /// A light it carries, or null for none.
    light: ?mod.SceneLight = null,
    /// A camera it carries, or null for none.
    camera: ?mod.SceneCamera = null,
    /// Whether its shape casts shadows from directional lights.
    casts_shadows: bool = true,
    /// Whether its shape shows the shadows cast onto it.
    receives_shadows: bool = true,
    /// Whether it and its children are left out of the scene.
    hidden: bool = false,
    /// How opaque its shape and its children's are, 0 to 1, multiplied down
    /// the tree (SceneKit's `opacity`): below 1 its shape blends as a
    /// translucent one (drawn back to front, casting no shadow), at 0 it is
    /// not drawn. Its light and camera are unaffected.
    opacity: f32 = 1,

    /// Turns the node so its -Z looks at a point, its +Y leaning up, both in
    /// its parent's space (SceneKit's `look(at:)`). A point at the node's own
    /// position leaves it as it is.
    ///
    /// - `self`: the node.
    /// - `target`: the point, in the parent's space.
    /// - `up`: the direction up should lean toward.
    pub fn lookAt(self: *Self, target: mod.Vec3, up: mod.Vec3) void {
        const forward = target.sub(self.transform.position);
        if (forward.length() == 0) return;
        self.transform.rotation = mod.Quaternion.lookRotation(forward, up);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "look-at turns a node's -Z toward the point" {
    var node = SceneNode{ .transform = .{ .position = mod.Vec3.init(3, 0, 0) } };
    node.lookAt(mod.Vec3.zero, mod.Vec3.up);
    const forward = node.transform.rotation.rotate(mod.Vec3.init(0, 0, -1));
    try std.testing.expect(forward.approxEql(mod.Vec3.init(-1, 0, 0), 1e-5));
    // Looking at its own position changes nothing.
    const before = node.transform.rotation;
    node.lookAt(node.transform.position, mod.Vec3.up);
    try std.testing.expectEqual(before, node.transform.rotation);
}
