//! How a scene's shadows and reflections are drawn: rasterized, or by
//! tracing rays.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_lighting_technique);

/// How a scene's shadows and reflections are drawn.
pub const SceneLightingTechnique = enum {
    const Self = @This();

    /// Rasterized: each directional light's shadow from a shadow map (the
    /// casters' depth seen along the light, tested over a 3×3 patch, so edges
    /// are softened by the map's texels); point lights cast no shadow and
    /// nothing reflects.
    rasterized,
    /// By tracing rays through the opaque shapes' acceleration structures:
    /// exact shadows from directional lights and from point lights that cast
    /// them, softened by the light's source size (`angular_diameter`,
    /// `radius`), and reflections on surfaces with a `reflectivity`. Only
    /// where the GPU can (Metal with ray tracing, on Apple silicon, with SDL
    /// built from the release); elsewhere the scene is drawn `rasterized`.
    rayTraced,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
