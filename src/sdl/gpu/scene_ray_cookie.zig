//! A directional light's cookie as either ray tracer binds it
//! (`MetalSceneRayTracer`, `VulkanSceneRayTracer`).

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_ray_cookie);
const mod = @import("../module.zig");
const sdl_c = @import("sdl_c");

/// A texture a directional light shines through (`SceneDirectionalLight.cookie`),
/// on the GPU: which light it filters, and its plane (`SceneTracing.cookie`).
pub const SceneRayCookie = struct {
    const Self = @This();

    /// The texture and its plane.
    plane: mod.SceneRayPlane,
    /// The index of the directional light it filters, in the frame's order.
    light: u32,

    /// The light a cookie filters, as `SceneTracing.planes.x` reads it.
    ///
    /// - `cookie`: the cookie, or null.
    /// - Returns: its light's index, or -1 for none.
    pub fn lightOf(cookie: ?Self) f32 {
        const self = cookie orelse return -1;
        return @floatFromInt(self.light);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a cookie names its light; none names no light" {
    try std.testing.expectEqual(@as(f32, -1), SceneRayCookie.lightOf(null));
    const texture: *sdl_c.SDL_GPUTexture = @ptrFromInt(0x1000);
    try std.testing.expectEqual(@as(f32, 1), SceneRayCookie.lightOf(.{ .plane = .{ .texture = texture, .equations = std.mem.zeroes([3][4]f32) }, .light = 1 }));
}
