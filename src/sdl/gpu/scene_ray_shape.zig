//! An opaque shape of a scene's frame as either ray tracer takes it
//! (`MetalSceneRayTracer`, `VulkanSceneRayTracer`).

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_ray_shape);
const scenes = @import("scenes");
const sdl_c = @import("sdl_c");

/// An opaque shape rays meet: its mesh (key, geometry and, for Metal, SDL buffers), where
/// the frame places it, its surface, and whether it casts shadows. A scene's
/// frame hands its opaque shapes to the ray tracer (`SceneRayTracer.prepare`)
/// as these.
pub const SceneRayShape = struct {
    const Self = @This();

    /// The mesh's key (`SceneGeometry.key`): its primitive structure is kept by it.
    key: u64,
    /// The mesh's geometry, built again for its triangles' normals when its structure is.
    geometry: scenes.SceneGeometry,
    /// The mesh's vertices (`scenes.SceneVertex`, position first). Metal
    /// builds from it; Vulkan cannot (SDL's buffers lack the usage a build
    /// reads) and uploads `geometry` built again instead.
    vertex_buffer: *sdl_c.SDL_GPUBuffer,
    /// The mesh's indices, 32-bit, three a triangle. Metal only, as `vertex_buffer`.
    index_buffer: *sdl_c.SDL_GPUBuffer,
    /// How many indices it has. Metal only, as `vertex_buffer`.
    index_count: u32,
    /// The shape's transform into the scene's space.
    world: scenes.Mat4,
    /// Its normals' transform into the scene's space.
    normal: scenes.Mat4,
    /// Its surface, as a reflection shows it.
    material: scenes.SceneMaterial,
    /// Its texture on the GPU, null for a material with none.
    texture: ?*sdl_c.SDL_GPUTexture,
    /// Whether shadow rays meet it.
    casts_shadows: bool,
    /// Whether reflection rays meet it.
    reflected: bool = true,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
