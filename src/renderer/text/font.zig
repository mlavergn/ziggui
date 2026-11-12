//! High-level font façade. Wraps the low-level `TtfFont` parser and the
//! `TextShaper` metrics; `TextPainter` paints a string into a `Canvas` as a
//! sequence of tinted glyph-coverage quads. The default font is the bundled
//! Inter (OFL).

const std = @import("std");
const log = std.log.scoped(.ziggui_font);
const mod = @import("module.zig");

/// A font face and its metrics.
pub const Font = struct {
    const Self = @This();

    /// The parsed face.
    face: mod.TtfFont,

    /// The bundled default font (Inter). The embedded blob is known-good.
    ///
    /// - Returns: the font.
    pub fn default() Self {
        const self = Self{ .face = mod.TtfFont.parse(mod.TtfFont.inter_ttf) catch @panic("the bundled font does not parse") };
        return self;
    }

    /// The bundled icon font (a Lucide subset). Its glyphs live in the Private
    /// Use Area; see `Icon`. The embedded blob is known-good.
    ///
    /// - Returns: the font.
    pub fn icons() Self {
        const self = Self{ .face = mod.TtfFont.parse(mod.TtfFont.icon_ttf) catch @panic("the bundled font does not parse") };
        return self;
    }

    /// The bundled monochrome emoji font (Noto Emoji, OFL). Wire it as a
    /// fallback via `face.fallback` so codepoints the primary font lacks (emoji,
    /// etc.) render through the normal coverage path. The embedded blob is
    /// known-good.
    ///
    /// - Returns: the font.
    pub fn emoji() Self {
        const self = Self{ .face = mod.TtfFont.parse(mod.TtfFont.emoji_ttf) catch @panic("the bundled font does not parse") };
        return self;
    }

    /// A font parsed from a TrueType blob.
    ///
    /// - `bytes`: the blob; it must outlive the font.
    /// - Returns: the font; fails when the blob does not parse.
    pub fn fromBytes(bytes: []const u8) !Self {
        const self = Self{ .face = try mod.TtfFont.parse(bytes) };
        return self;
    }

    /// The line height at a pixel size.
    ///
    /// - `self`: the font.
    /// - `pixel_size`: the em size in pixels.
    /// - Returns: the line height in pixels.
    pub fn lineHeight(self: *const Self, pixel_size: f32) f32 {
        return mod.TextShaper.init(&self.face).lineHeight(pixel_size);
    }

    /// The ascent at a pixel size.
    ///
    /// - `self`: the font.
    /// - `pixel_size`: the em size in pixels.
    /// - Returns: the distance from a line's top to its baseline, in pixels.
    pub fn ascent(self: *const Self, pixel_size: f32) f32 {
        return mod.TextShaper.init(&self.face).ascentPixels(pixel_size);
    }

    /// Measure a single line: width = advance sum, height = one line height.
    ///
    /// - `self`: the font.
    /// - `text`: the UTF-8 line.
    /// - `pixel_size`: the em size in pixels.
    /// - Returns: the line's size in pixels.
    pub fn measure(self: *const Self, text: []const u8, pixel_size: f32) mod.Size {
        return .{
            .width = mod.TextShaper.init(&self.face).measureLineWidth(text, pixel_size),
            .height = self.lineHeight(pixel_size),
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Font: icons parses and maps a known PUA codepoint to a glyph" {
    const font = Font.icons();
    // lucide `heart` lives at U+E0F2 in the bundled subset.
    try std.testing.expect(font.face.glyphIndex(0xE0F2) != 0);
}

test "Font: default parses and measures text" {
    const font = Font.default();
    const size = font.measure("Hello", 16);
    try std.testing.expect(size.width > 0);
    try std.testing.expect(size.height > 0);
}
