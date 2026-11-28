//! What a scene's reflections show where they meet nothing.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_environment);
const mod = @import("module.zig");

/// What a scene's reflections see where they meet nothing, in every
/// direction (rather than `Scene.background`'s one color): an
/// equirectangular texture, u around the horizon from +X toward +Z, v down
/// from straight up (+Y) to `max_polar_deg` (a direction lower than that
/// sees its last row); and over it, in order, its `overlays`, each where the
/// ray crosses its plane ahead, by its texel's alpha, fading where the ray
/// grazes the plane. Sampled a little blurred (`blur` levels), so a rippled
/// surface's reflection doesn't sparkle. Ray-traced scenes on Metal only;
/// elsewhere reflections see `Scene.background`.
pub const SceneEnvironment = struct {
    const Self = @This();

    /// The most overlays drawn; those past it are left out.
    pub const max_overlays = 4;

    /// The texture.
    texture: mod.SceneTexture,
    /// How far down from straight up it reaches, in degrees.
    max_polar_deg: f32 = 180,
    /// What its colors and its overlays' are multiplied by (as
    /// `SceneMaterial.emission_strength`); 1 for one not a finite number above 0.
    strength: f32 = 1,
    /// The mipmap level reflections sample, for a soft sky.
    blur: f32 = 1.5,
    /// Textures on planes laid over it, later over earlier; the slice must
    /// outlive the frames that draw the scene.
    overlays: []const mod.ScenePlaneTexture = &.{},
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
