//! How a node's surface looks: its color, texture and shine.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_material);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A base-color texture: an RGBA8 image in sRGB, in the app's memory, which
/// must outlive every frame that draws it. The GPU keeps a copy (with
/// mipmaps) keyed by the pixels and `generation`: change `generation` after
/// changing the pixels in place.
pub const SceneTexture = struct {
    const Self = @This();

    /// The pixels.
    image: renderer.Image,
    /// Changes when the pixels change in place.
    generation: u64 = 0,
    /// Whether any pixel is less than opaque, so the material blends.
    translucent: bool = false,

    /// What identifies the texture on the GPU.
    ///
    /// - `self`: the texture.
    /// - Returns: the key.
    pub fn key(self: *const Self) u64 {
        const identity = [_]u64{ @intFromPtr(self.image.pixels.ptr), self.image.width, self.image.height, self.generation };
        return std.hash.Wyhash.hash(0, std.mem.asBytes(&identity));
    }
};

/// A surface lit as Blinn-Phong: a diffuse base color (times the texture's)
/// and a white specular highlight.
pub const SceneMaterial = struct {
    const Self = @This();

    /// The surface's color, in sRGB; its alpha below 1 blends the surface.
    base_color: renderer.Color = renderer.Color.white,
    /// A texture its color is multiplied by, or null for none.
    texture: ?SceneTexture = null,
    /// How bright the highlight is, 0 for none.
    specular: f32 = 0.5,
    /// How tight the highlight is: the Blinn-Phong exponent.
    shininess: f32 = 32,
    /// How much of the scene the surface mirrors, 0 to 1, more at grazing
    /// angles: only when ray traced (`SceneLightingTechnique.rayTraced`), the
    /// opaque shapes reflected lit but unshadowed; ignored otherwise.
    reflectivity: f32 = 0,

    /// Whether the surface blends with what is behind it: drawn after the
    /// opaque ones, back to front, casting no shadow.
    ///
    /// - `self`: the material.
    /// - Returns: true when it blends.
    pub fn isTranslucent(self: *const Self) bool {
        if (self.base_color.a < 1) return true;
        if (self.texture) |texture| return texture.translucent;
        return false;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = mod;
}

test "a material blends when its color or its texture is less than opaque" {
    try std.testing.expect(!(SceneMaterial{}).isTranslucent());
    try std.testing.expect((SceneMaterial{ .base_color = renderer.Color.white.withAlpha(0.5) }).isTranslucent());
    const pixels: [4]u8 = @splat(255);
    const image = renderer.Image{ .width = 1, .height = 1, .pixels = &pixels };
    try std.testing.expect(!(SceneMaterial{ .texture = .{ .image = image } }).isTranslucent());
    try std.testing.expect((SceneMaterial{ .texture = .{ .image = image, .translucent = true } }).isTranslucent());
}
