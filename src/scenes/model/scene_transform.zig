//! Where a node is relative to its parent: a position, rotation and scale.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_transform);
const mod = @import("module.zig");

/// A node's place in its parent's space: scaled, then rotated, then moved.
pub const SceneTransform = struct {
    const Self = @This();

    /// The move, in the parent's units.
    position: mod.Vec3 = mod.Vec3.zero,
    /// The rotation.
    rotation: mod.Quaternion = mod.Quaternion.identity,
    /// The scale along each of the node's axes.
    scale: mod.Vec3 = mod.Vec3.one,

    /// The transform as a matrix.
    ///
    /// - `self`: the transform.
    /// - Returns: the matrix.
    pub fn matrix(self: *const Self) mod.Mat4 {
        return mod.Mat4.compose(self.position, self.rotation.normalized(), self.scale);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a transform scales, then rotates, then moves" {
    const transform = SceneTransform{
        .position = mod.Vec3.init(0, 0, 5),
        .rotation = mod.Quaternion.fromAxisAngle(mod.Vec3.up, std.math.pi / 2.0),
        .scale = mod.Vec3.init(2, 1, 1),
    };
    // X scaled to 2, turned to -Z, moved to z = 3.
    try std.testing.expect(transform.matrix().transformPoint(mod.Vec3.init(1, 0, 0)).approxEql(mod.Vec3.init(0, 0, 3), 1e-5));
}
