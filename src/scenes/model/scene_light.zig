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
};

/// Light from the node's position in every direction, fading to nothing at
/// `range`. Casts no shadows.
pub const ScenePointLight = struct {
    const Self = @This();

    /// How far it reaches, in scene units.
    range: f32 = 10,
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
