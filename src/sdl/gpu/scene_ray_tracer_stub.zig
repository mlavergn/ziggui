//! The ray tracer where none can run: SDL built without either interop (a
//! prebuilt `-Dsdl3-prefix` SDL). Every scene draws rasterized.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_ray_tracer_stub);
const mod = @import("../module.zig");
const scenes = @import("scenes");
const sdl_c = @import("sdl_c");

/// A ray tracer that is never made: `supported` is false and `init` null,
/// with the declarations `SceneRenderer` and its tests name.
pub const SceneRayTracerStub = struct {
    const Self = @This();

    /// Frames a frame's own objects are kept (`MetalSceneRayTracer.retire_frames`).
    pub const retire_frames = 4;

    /// Never anything.
    primitives: std.ArrayList(void) = .empty,
    /// Never anything.
    sets: std.ArrayList(void) = .empty,
    /// Never anything.
    retired: std.ArrayList(void) = .empty,
    /// Never anything.
    triangles: ?*anyopaque = null,
    /// Never anything.
    instances: ?*anyopaque = null,

    /// No ray tracer.
    ///
    /// - `allocator`: unused.
    /// - `device`: unused.
    /// - Returns: null.
    pub fn init(allocator: std.mem.Allocator, device: *sdl_c.SDL_GPUDevice) ?Self {
        _ = allocator;
        _ = device;
        return null;
    }

    /// Nothing to release.
    ///
    /// - `self`: the ray tracer.
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// No device traces rays here.
    ///
    /// - `device`: unused.
    /// - Returns: false.
    pub fn supported(device: *sdl_c.SDL_GPUDevice) bool {
        _ = device;
        return false;
    }

    /// Nothing to start.
    ///
    /// - `self`: the ray tracer.
    /// - `frame_number`: unused.
    pub fn nextFrame(self: *Self, frame_number: u64) void {
        _ = self;
        _ = frame_number;
    }

    /// Nothing is built.
    ///
    /// - `self`: the ray tracer.
    /// - `arena`: unused.
    /// - `command_buffer`: unused.
    /// - `shapes`: unused.
    /// - Returns: false, so the frame draws shadow maps.
    pub fn prepare(self: *Self, arena: std.mem.Allocator, command_buffer: *sdl_c.SDL_GPUCommandBuffer, shapes: []const mod.SceneRayShape) bool {
        _ = self;
        _ = arena;
        _ = command_buffer;
        _ = shapes;
        return false;
    }

    /// Nothing is bound.
    ///
    /// - `self`: the ray tracer.
    /// - `command_buffer`: unused.
    /// - `pass`: unused.
    /// - `sky`: unused.
    /// - `blank`: unused.
    /// - `sampler`: unused.
    /// - Returns: false.
    pub fn bind(self: *Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer, pass: *sdl_c.SDL_GPURenderPass, sky: scenes.Vec3, blank: *sdl_c.SDL_GPUTexture, sampler: *sdl_c.SDL_GPUSampler) bool {
        _ = self;
        _ = command_buffer;
        _ = pass;
        _ = sky;
        _ = blank;
        _ = sampler;
        return false;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
