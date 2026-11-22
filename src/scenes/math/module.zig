//! A scene's math: vectors, rotations and matrices, column-major `f32`.

const std = @import("std");
const log = std.log.scoped(.ziggui_math_module);

/// A point or a direction in a scene.
pub const Vec3 = @import("vec3.zig").Vec3;
/// A point in homogeneous coordinates, or a matrix column.
pub const Vec4 = @import("vec4.zig").Vec4;
/// A 4×4 column-major matrix.
pub const Mat4 = @import("mat4.zig").Mat4;
/// A rotation as a unit quaternion.
pub const Quaternion = @import("quaternion.zig").Quaternion;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("vec3.zig");
    _ = @import("vec4.zig");
    _ = @import("mat4.zig");
    _ = @import("quaternion.zig");
}
