//! A light a node carries: directional (as the sun) or a point.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_light);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Light from far away along the node's -Z, the same everywhere (the sun).
pub const SceneDirectionalLight = struct {
    const Self = @This();

    /// Whether it casts shadows onto the nodes that receive them.
    casts_shadows: bool = true,
    /// How wide the light's source looks, in degrees (the sun's is about
    /// 0.53): ray-traced shadows (`SceneLightingTechnique.rayTraced`) are sharp
    /// where a shadow meets its caster and soften away from it; 0 for hard
    /// shadows. Shadow maps ignore it.
    angular_diameter: f32 = 0,
    /// A texture it shines through (a light cookie), or null: a point is lit
    /// by the light that passes the plane on its way there, its texels'
    /// colors scaling it (white passes it all, black none). Ray-traced scenes
    /// on Metal only (`SceneLightingTechnique.rayTraced`), on what the light
    /// lights directly and what reflections show; elsewhere it shines
    /// unfiltered. Only the first directional light's cookie in the graph applies.
    cookie: ?mod.ScenePlaneTexture = null,
};

/// Light from the node's position in every direction, fading to nothing at
/// `range`.
pub const ScenePointLight = struct {
    const Self = @This();

    /// How far it reaches, in scene units.
    range: f32 = 10,
    /// Whether it casts shadows onto the nodes that receive them: only when
    /// they are ray traced (`SceneLightingTechnique.rayTraced`); shadow maps
    /// cast none from a point light.
    casts_shadows: bool = false,
    /// The radius of the light's source, a sphere, in scene units: its
    /// ray-traced shadows soften away from their caster; 0 for hard shadows.
    radius: f32 = 0,
    /// How far from the light its shadows are traced, or null for its whole
    /// `range`: past it what it lights is lit unshadowed, the shadows fading
    /// out over its last fifth. A light's glow far off is faint, its shadows
    /// fainter, and every pixel it reaches costs rays: a fire's shadows
    /// traced only near it cost a fraction.
    shadow_range: ?f32 = null,
    /// The most rays one of its soft shadows sends, 4 to 32 in fours, or
    /// null for the scene's (`Scene.soft_shadow_rays`).
    shadow_rays: ?u32 = null,
};

/// What kind of light it is.
pub const SceneLightKind = union(enum) {
    const Self = @This();

    /// Light along the node's -Z.
    directional: SceneDirectionalLight,
    /// Light from the node's position.
    point: ScenePointLight,
};

/// A light a node carries, moving with it (SceneKit's `SCNLight`). A scene
/// draws with up to `SceneFrame.max_directional_lights` directional lights
/// and `SceneFrame.max_point_lights` point lights, the first in the graph
/// kept; its ambient light is the scene's own (`Scene.ambient`).
pub const SceneLight = struct {
    const Self = @This();

    /// What kind of light it is.
    kind: SceneLightKind = .{ .directional = .{} },
    /// Its color, in sRGB.
    color: renderer.Color = renderer.Color.white,
    /// How bright it is: its color is multiplied by it.
    intensity: f32 = 1,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = mod;
}
