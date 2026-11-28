//! A scene's environment as either ray tracer binds it
//! (`MetalSceneRayTracer`, `VulkanSceneRayTracer`).

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_ray_environment);
const mod = @import("../module.zig");
const scenes = @import("scenes");
const sdl_c = @import("sdl_c");

/// What a scene's reflections see where they meet nothing
/// (`SceneEnvironment`), on the GPU: its texture uploaded, and its overlays
/// (`SceneTracing.environment`, `planes.y`, `overlays`).
pub const SceneRayEnvironment = struct {
    const Self = @This();

    /// The most overlays bound (`SceneEnvironment.max_overlays`).
    pub const max_overlays = scenes.SceneEnvironment.max_overlays;

    /// The texture, uploaded.
    texture: *sdl_c.SDL_GPUTexture,
    /// How far down from straight up it reaches, in radians.
    max_polar: f32,
    /// What its colors and its overlays' are multiplied by.
    strength: f32 = 1,
    /// The mipmap level sampled.
    blur: f32 = 1.5,
    /// The overlays, the first `overlay_count` of them set.
    overlays: [max_overlays]mod.SceneRayPlane = undefined,
    /// How many overlays are set.
    overlay_count: u32 = 0,

    /// The environment's uniforms, as `SceneTracing.environment` reads them:
    /// bound, max polar, strength, blur.
    ///
    /// - `environment`: the environment, or null for none.
    /// - Returns: the float4.
    pub fn uniforms(environment: ?Self) [4]f32 {
        const self = environment orelse return .{ 0, 0, 1, 0 };
        return .{ 1, self.max_polar, self.strength, self.blur };
    }

    /// How many overlays an environment has, as `SceneTracing.planes.y` reads it.
    ///
    /// - `environment`: the environment, or null for none.
    /// - Returns: the count.
    pub fn overlaysOf(environment: ?Self) f32 {
        const self = environment orelse return 0;
        return @floatFromInt(self.overlay_count);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "an environment's uniforms say whether it's bound, and how many overlays" {
    try std.testing.expectEqual(@as(f32, 0), SceneRayEnvironment.uniforms(null)[0]);
    try std.testing.expectEqual(@as(f32, 0), SceneRayEnvironment.overlaysOf(null));
    const texture: *sdl_c.SDL_GPUTexture = @ptrFromInt(0x1000);
    var environment = SceneRayEnvironment{ .texture = texture, .max_polar = 1.5 };
    environment.overlays[0] = .{ .texture = texture, .equations = std.mem.zeroes([3][4]f32) };
    environment.overlay_count = 1;
    try std.testing.expectEqual(@as(f32, 1), SceneRayEnvironment.uniforms(environment)[0]);
    try std.testing.expectEqual(@as(f32, 1.5), SceneRayEnvironment.uniforms(environment)[1]);
    try std.testing.expectEqual(@as(f32, 1), SceneRayEnvironment.overlaysOf(environment));
}
