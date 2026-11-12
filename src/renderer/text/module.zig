//! Text: the TrueType parser, glyph caches, shaping, the bundled fonts, the
//! text painter, and the icon catalog.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_module);

/// A parsed TrueType face.
pub const TtfFont = @import("ttf_font.zig").TtfFont;
/// Why a blob failed to parse as a TrueType font.
pub const TtfParseError = @import("ttf_font.zig").TtfParseError;
/// A codepoint resolved to the face that carries its glyph.
pub const ResolvedGlyph = @import("ttf_font.zig").ResolvedGlyph;
/// A glyph's coverage bitmap and its placement.
pub const RasterGlyph = @import("raster_glyph.zig").RasterGlyph;
/// The callbacks of a face another engine reads.
pub const ExternalFace = @import("external_face.zig").ExternalFace;
/// Rasterized glyphs of a face, by glyph and pixel size.
pub const GlyphCache = @import("glyph_cache.zig").GlyphCache;
/// A glyph and its pen position on a line.
pub const PositionedGlyph = @import("positioned_glyph.zig").PositionedGlyph;
/// One line of word-wrapped text.
pub const WrappedLine = @import("wrapped_line.zig").WrappedLine;
/// Measures, lays out and wraps text in one face.
pub const TextShaper = @import("text_shaper.zig").TextShaper;
/// A font face and its metrics.
pub const Font = @import("font.zig").Font;
/// Paints text and icon glyphs into a canvas.
pub const TextPainter = @import("text_painter.zig").TextPainter;
/// A text style's face selection (weight, italic, monospace).
pub const FontStyle = @import("font_style.zig").FontStyle;
/// The bundled faces and a glyph cache for each.
pub const FontSet = @import("font_set.zig").FontSet;
/// A Lucide icon, valued by its codepoint in the icon font.
pub const Icon = @import("icon.zig").Icon;

/// A 2D point (from the renderer).
pub const Point = @import("../module.zig").Point;
/// A 2D extent (from the renderer).
pub const Size = @import("../module.zig").Size;
/// An axis-aligned rectangle (from the renderer).
pub const Rect = @import("../module.zig").Rect;
/// An RGBA color (from the renderer).
pub const Color = @import("../module.zig").Color;
/// A retained list of draw commands (from the renderer).
pub const Canvas = @import("../module.zig").Canvas;
/// A CPU pixel buffer (from the renderer).
pub const Framebuffer = @import("../module.zig").Framebuffer;
/// The CPU rasterizer (from the renderer).
pub const Rasterizer = @import("../module.zig").Rasterizer;
/// A font weight (from the renderer).
pub const FontWeight = @import("../module.zig").FontWeight;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("ttf_font.zig");
    _ = @import("raster_glyph.zig");
    _ = @import("external_face.zig");
    _ = @import("glyph_cache.zig");
    _ = @import("positioned_glyph.zig");
    _ = @import("wrapped_line.zig");
    _ = @import("text_shaper.zig");
    _ = @import("font.zig");
    _ = @import("text_painter.zig");
    _ = @import("font_style.zig");
    _ = @import("font_set.zig");
    _ = @import("icon.zig");
}
