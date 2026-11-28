//! How a node's surface looks: its color, texture and shine.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_material);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// How a texture's pixels are stored.
pub const SceneTextureFormat = enum(u8) {
    const Self = @This();

    /// Four bytes a pixel, RGBA in sRGB: a picture's colors.
    srgb8,
    /// Four 16-bit floats a pixel (eight bytes), RGBA, linear and unclamped:
    /// data a shader modifier reads (heights, slopes) rather than colors.
    float16,

    /// The bytes a pixel takes.
    ///
    /// - `self`: the format.
    /// - Returns: 4 or 8.
    pub fn bytesPerPixel(self: *const Self) u64 {
        return switch (self.*) {
            .srgb8 => 4,
            .float16 => 8,
        };
    }
};

/// A texture: an RGBA image (sRGB bytes, or half floats for a shader
/// modifier's data: `format`), in the app's memory, which must outlive every
/// frame that draws it. The GPU keeps a copy (with
/// mipmaps) keyed by the pixels and `generation`: change `generation` after
/// changing the pixels in place.
pub const SceneTexture = struct {
    const Self = @This();

    /// The pixels.
    image: renderer.Image,
    /// Changes when the pixels change in place: the GPU's copy is refreshed
    /// in place, not made anew, so a texture rewritten every frame (a
    /// simulation's) costs its upload alone.
    generation: u64 = 0,
    /// Whether any pixel is less than opaque, so the material blends.
    translucent: bool = false,
    /// How its pixels are stored.
    format: SceneTextureFormat = .srgb8,

    /// What identifies the texture on the GPU.
    ///
    /// - `self`: the texture.
    /// - Returns: the key.
    pub fn key(self: *const Self) u64 {
        const identity = [_]u64{ @intFromPtr(self.image.pixels.ptr), self.image.width, self.image.height, self.generation, @backingInt(self.format) };
        return std.hash.Wyhash.hash(0, std.mem.asBytes(&identity));
    }

    /// What identifies its pixels whatever their generation: a texture
    /// whose key changed but whose source did not is refreshed in place.
    ///
    /// - `self`: the texture.
    /// - Returns: the source.
    pub fn source(self: *const Self) u64 {
        const identity = [_]u64{ @intFromPtr(self.image.pixels.ptr), self.image.width, self.image.height, @backingInt(self.format) };
        return std.hash.Wyhash.hash(1, std.mem.asBytes(&identity));
    }

    /// The bytes its pixels take.
    ///
    /// - `self`: the texture.
    /// - Returns: the size; for one past what a `u64` holds, a size larger
    ///   than any buffer (`isWhole` is then false).
    pub fn byteLength(self: *const Self) u64 {
        return self.image.byteLength() *| self.format.bytesPerPixel() / 4;
    }

    /// Whether its pixels hold every pixel the size says.
    ///
    /// - `self`: the texture.
    /// - Returns: true when they do.
    pub fn isWhole(self: *const Self) bool {
        return self.byteLength() <= self.image.pixels.len;
    }
};

/// A surface lit as Blinn-Phong: a diffuse base color (times the texture's)
/// and a white specular highlight, or giving off its own color (`emission`).
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
    /// How much of its color the surface gives off itself, 0 to 1 (SceneKit's
    /// `emission`, as a share of the base color times the texture): at 1 it
    /// shows that color whatever the light, unlit and unshadowed (a sky, a
    /// screen, a lamp's shade), and reflections show it so; between, its lit
    /// color mixes toward it.
    emission: f32 = 0,
    /// What its own color is multiplied by where it gives it off: above 1
    /// for a light brighter than white (a sky, a flame), shown as such through
    /// the scene's exposure and tone mapping. Metal; elsewhere 1.
    emission_strength: f32 = 1,
    /// GPU code that moves the surface's vertices, or recomputes its
    /// texture coordinates, normal and tint per pixel, as it is drawn, or
    /// null for none; it must outlive the frames that draw the material, and
    /// its values may change between them.
    shader_modifier: ?*const mod.SceneShaderModifier = null,

    /// The emission kept between 0 and 1; 0 for one that is not a number
    /// (`clamp` would make NaN 1, fully unlit).
    ///
    /// - `self`: the material.
    /// - Returns: the share.
    pub fn emissionShare(self: *const Self) f32 {
        return if (self.emission > 0) @min(self.emission, 1) else 0;
    }

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

test "a material's emission is kept between 0 and 1, and one that is not a number gives off nothing" {
    try std.testing.expectEqual(@as(f32, 0), (SceneMaterial{}).emissionShare());
    try std.testing.expectEqual(@as(f32, 0.25), (SceneMaterial{ .emission = 0.25 }).emissionShare());
    try std.testing.expectEqual(@as(f32, 1), (SceneMaterial{ .emission = 4 }).emissionShare());
    try std.testing.expectEqual(@as(f32, 0), (SceneMaterial{ .emission = std.math.nan(f32) }).emissionShare());
}
