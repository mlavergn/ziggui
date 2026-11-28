//! A texture on a plane as either ray tracer binds it
//! (`MetalSceneRayTracer`, `VulkanSceneRayTracer`).

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_ray_plane);
const sdl_c = @import("sdl_c");

/// A texture laid on a plane (`ScenePlaneTexture`), on the GPU: the texture
/// uploaded and the plane's equations (`ScenePlaneTexture.equations`), as the
/// traced fragment shader reads them (`ScenePlane`).
pub const SceneRayPlane = struct {
    const Self = @This();

    /// The texture, uploaded.
    texture: *sdl_c.SDL_GPUTexture,
    /// The plane's u, v and plane rows.
    equations: [3][4]f32,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
