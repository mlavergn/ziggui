//! A material's shader modifier: GPU code that moves its vertices, or shades its pixels.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_shader_modifier);
const mod = @import("module.zig");

/// GPU code that changes a surface as it is drawn (SceneKit's shader
/// modifiers, at its geometry and surface entry points): a surface animated
/// on the GPU (waves, a flag, grass in the wind) keeps one mesh, uploaded
/// once, while the modifier reads values the app sets each frame (`values`,
/// a time, say).
///
/// `geometry` runs per vertex: the body of a Metal function with these in
/// scope: `thread float3 &position`, `thread float3 &normal` and `thread
/// float2 &uv` (the vertex's, in the node's space, to change), `thread float4 &tint`
/// (white; it multiplies the surface's color and alpha, blended across each
/// triangle: a fade, say), `thread float4 &custom` (zero; blended across the
/// triangle into the surface body's `custom`, for what it hands on), and
/// `constant float4 *values` (`values`). A mesh may carry anything in its
/// normals and texture coordinates for the modifier to read, so long as the
/// modifier writes the real ones.
///
/// Both bodies have `textures` and `samplers` in scope:
/// `textures[i].sample(samplers[i], uv)` reads `textures[i]`; per vertex give a level (`level(0.0)`, or a coarser
/// one where the mesh is too coarse for the texture's detail), as a vertex
/// has no screen footprint to choose one.
///
/// `surface` runs per pixel, before the surface is lit: the body of a Metal
/// function with `float3 world` (the point, in the scene's space), `float3
/// eye` (the camera's position), `thread float3 &normal` (in the scene's
/// space) and `thread float2 &uv` (blended from the vertices', to change:
/// the texture is sampled at `uv` after it), `thread float4 &tint` (as the
/// vertices left it), `float4 custom` (what the geometry body handed on)
/// and `constant float4 *values` in scope. What changes fast across a
/// triangle belongs here: a texture's coordinates found along the view (clouds on a
/// dome), a sparkle, a pattern too fine for the mesh.
///
/// `declarations` is Metal placed before those functions, at file scope:
/// the helper functions and constants the bodies call (Metal has no
/// functions inside functions), shared by modifiers that include the same
/// text.
///
/// It changes what is drawn only: shadow maps, ray-traced shadows and what
/// reflections show see the mesh as uploaded, so a moving surface is best
/// translucent (it then casts no shadow). Give its mesh `SceneMesh.bounds`
/// with room for where it moves. Metal only: elsewhere the mesh is drawn
/// unmodified (logged once).
///
/// The code is compiled into the renderer's pipelines once per distinct
/// `geometry`, `surface` and `declarations` (`key`) and kept for the
/// renderer's life, so keep it constant and put what changes in `values`
/// and `textures`. It runs as written on the GPU: pass only the app's own
/// code, never text from a user, a file or the network.
pub const SceneShaderModifier = struct {
    const Self = @This();

    /// How many values a modifier reads.
    pub const max_values = 32;
    /// How many textures it reads.
    pub const max_textures = 4;

    /// The per-vertex Metal function body; empty for none.
    geometry: []const u8 = "",
    /// The per-pixel Metal function body; empty for none.
    surface: []const u8 = "",
    /// Metal at file scope before the body's function: its helpers; empty for none.
    declarations: []const u8 = "",
    /// What the modifier reads, as `values[0]` to `values[31]`; changing
    /// them re-uploads nothing.
    values: [max_values][4]f32 = @splat(.{ 0, 0, 0, 0 }),
    /// What the modifier samples, as `textures[0]` to `textures[3]` with
    /// `samplers[i]` (repeating, linear, mipmapped), white where null. A
    /// texture rewritten each frame takes a new `generation` and is
    /// refreshed in place; `.float16` holds data unclamped.
    textures: [max_textures]?mod.SceneTexture = @splat(null),

    /// What identifies the modifier's code: modifiers sharing it share a pipeline.
    ///
    /// - `self`: the modifier.
    /// - Returns: the key.
    pub fn key(self: *const Self) u64 {
        const declared = std.hash.Wyhash.hash(0x5ce1e, self.declarations);
        return std.hash.Wyhash.hash(std.hash.Wyhash.hash(declared, self.geometry), self.surface);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a shader modifier's key follows its code, not its values" {
    var first = SceneShaderModifier{ .geometry = "position.y += values[0].x;" };
    const same = SceneShaderModifier{ .geometry = "position.y += values[0].x;" };
    const other = SceneShaderModifier{ .geometry = "position.y -= values[0].x;" };
    first.values[0][0] = 2;
    try std.testing.expectEqual(first.key(), same.key());
    try std.testing.expect(first.key() != other.key());
    const declared = SceneShaderModifier{ .geometry = "position.y += values[0].x;", .declarations = "constant float lift = 1.0;" };
    try std.testing.expect(declared.key() != same.key());
    const shaded = SceneShaderModifier{ .geometry = "position.y += values[0].x;", .surface = "uv.x += 0.5;" };
    try std.testing.expect(shaded.key() != same.key());
}
