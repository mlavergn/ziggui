//! The faces a rich paragraph's spans are measured and drawn in.

const std = @import("std");
const log = std.log.scoped(.ziggui_rich_faces);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Resolves a span to the face used to measure and draw it.
pub const RichFaces = struct {
    const Self = @This();

    /// The font set the spans' styles come from, or null (tests).
    fonts: ?*renderer.FontSet = null,

    /// Used when `fonts` is null (tests) and as the base weight source.
    fallback: *const renderer.TtfFont,

    /// The weight of a span that names none.
    base_weight: renderer.FontWeight = .regular,

    /// The face a span is measured and drawn in.
    ///
    /// - `self`: the faces.
    /// - `span`: the span.
    /// - Returns: its face (`fallback` without a font set).
    pub fn forSpan(self: *const Self, span: mod.Span) *const renderer.TtfFont {
        const fonts = self.fonts orelse return self.fallback;
        const style = self.styleOf(span);
        return fonts.cache(style).face;
    }

    /// The glyph cache a span is drawn from.
    ///
    /// - `self`: the faces.
    /// - `span`: the span.
    /// - Returns: its cache, or null without a font set.
    pub fn cacheFor(self: *const Self, span: mod.Span) ?*renderer.GlyphCache {
        const fonts = self.fonts orelse return null;
        return fonts.cache(self.styleOf(span));
    }

    /// The face selection a span asks for.
    ///
    /// - `self`: the faces.
    /// - `span`: the span.
    /// - Returns: its weight, italic and mono.
    fn styleOf(self: *const Self, span: mod.Span) renderer.FontStyle {
        return .{ .weight = span.weight orelse self.base_weight, .italic = span.italic, .mono = span.mono };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
