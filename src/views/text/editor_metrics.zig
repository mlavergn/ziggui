//! Tab-aware horizontal metrics for edited text, shared by the caret, the
//! selection and the click math so they all agree.

const std = @import("std");
const log = std.log.scoped(.ziggui_editor_metrics);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Widths of edited text in one face at one size, with tabs snapping to tab
/// stops rather than drawing a `.notdef` box.
pub const EditorMetrics = struct {
    const Self = @This();

    /// Editor tab width, in spaces (tabs snap to the next multiple of this).
    pub const tab_size: f32 = 4;

    /// The face the text is drawn in.
    face: *const renderer.TtfFont,

    /// The text's size.
    pixel_size: f32,

    /// Metrics of `face` at `pixel_size`.
    ///
    /// - `face`: the face the text is drawn in.
    /// - `pixel_size`: the text's size.
    /// - Returns: the metrics.
    pub fn init(face: *const renderer.TtfFont, pixel_size: f32) Self {
        const self = Self{ .face = face, .pixel_size = pixel_size };
        return self;
    }

    /// The advance of a single space and of a tab stop.
    ///
    /// - `self`: the metrics.
    /// - Returns: the space's and the tab's widths.
    pub fn tabMetrics(self: *const Self) struct { space: f32, tab: f32 } {
        const space = renderer.TextShaper.init(self.face).measureLineWidth(" ", self.pixel_size);
        return .{ .space = space, .tab = space * tab_size };
    }

    /// Pixel width of `slice`, honoring tab stops (so `\t` advances to the
    /// next multiple of the tab width). Each codepoint is measured in the face
    /// that draws it (the fallback chain, at that face's own scale), so the
    /// width matches the drawn text on emoji and CJK lines too.
    ///
    /// - `self`: the metrics.
    /// - `slice`: the text, from a line's start.
    /// - Returns: its width.
    pub fn prefixWidth(self: *const Self, slice: []const u8) f32 {
        const tab_width = self.tabMetrics().tab;
        const lines = mod.TextLines.init(slice);
        var x: f32 = 0;
        var index: usize = 0;
        while (index < slice.len) {
            const next = lines.nextCodepointEnd(index);
            if (slice[index] == '\t') {
                x = (@floor(x / tab_width) + 1) * tab_width;
            } else {
                x += self.codepointAdvance(slice[index..next]);
            }
            index = next;
        }
        return x;
    }

    /// The byte offset within `line` whose glyph boundary is nearest to pixel
    /// `target_x` (measured from the line's left edge): click to position.
    /// Codepoints are measured as `prefixWidth` measures them.
    ///
    /// - `self`: the metrics.
    /// - `line`: the line's text.
    /// - `target_x`: the click, from the line's left edge.
    /// - Returns: the byte offset.
    pub fn caretInLine(self: *const Self, line: []const u8, target_x: f32) usize {
        if (target_x <= 0) return 0;
        const tab_width = self.tabMetrics().tab;
        const lines = mod.TextLines.init(line);
        var x: f32 = 0;
        var index: usize = 0;
        while (index < line.len) {
            const next = lines.nextCodepointEnd(index);
            const advance = if (line[index] == '\t')
                (@floor(x / tab_width) + 1) * tab_width - x
            else
                self.codepointAdvance(line[index..next]);
            if (target_x < x + advance / 2) return index; // nearer this cell's left edge
            x += advance;
            index = next;
        }
        return line.len;
    }

    /// The advance of one codepoint (a bad byte draws as U+FFFD), resolved
    /// through the face's fallback chain at the resolving face's scale, as
    /// drawing resolves it.
    ///
    /// - `self`: the metrics.
    /// - `bytes`: the codepoint's bytes.
    /// - Returns: its advance, in pixels.
    fn codepointAdvance(self: *const Self, bytes: []const u8) f32 {
        // A lone non-ASCII byte is a bad one (`utf8Decode` would take a
        // single byte as its own codepoint).
        const codepoint: u21 = if (bytes.len == 1)
            (if (bytes[0] < 0x80) bytes[0] else 0xFFFD)
        else
            std.unicode.utf8Decode(bytes) catch 0xFFFD;
        const resolved = self.face.resolve(codepoint);
        const scale = resolved.face.scaleForPixelSize(self.pixel_size);
        return @as(f32, @floatFromInt(resolved.face.advanceWidth(resolved.glyph))) * scale;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "the caret after an emoji sits where the drawn text puts the next glyph" {
    var font = renderer.Font.default();
    var emoji = renderer.Font.emoji();
    font.face.fallback = &emoji.face;
    const line = "a\u{1F600}b"; // the emoji is in the fallback face only
    const after_emoji = 5;
    const metrics = EditorMetrics.init(&font.face, 14);
    const glyphs = try renderer.TextShaper.init(&font.face).layoutLine(std.testing.allocator, line, 14, 0);
    defer std.testing.allocator.free(glyphs);
    try std.testing.expectEqual(@as(usize, 3), glyphs.len);
    try std.testing.expect(glyphs[1].face == &emoji.face);
    // The caret, the selection and the click all measure as drawing places glyphs.
    try std.testing.expectEqual(glyphs[2].x, metrics.prefixWidth(line[0..after_emoji]));
    try std.testing.expectEqual(renderer.TextShaper.init(&font.face).measureLineWidth(line, 14), metrics.prefixWidth(line));
    try std.testing.expectEqual(@as(usize, after_emoji), metrics.caretInLine(line, glyphs[2].x));
    try std.testing.expectEqual(@as(usize, 1), metrics.caretInLine(line, glyphs[1].x + glyphs[1].advance * 0.4));
}

test "a bad byte measures as one replacement glyph, and the letters after it as themselves" {
    const font = renderer.Font.default();
    const metrics = EditorMetrics.init(&font.face, 14);
    const shaper = renderer.TextShaper.init(&font.face);
    const expected = shaper.measureLineWidth("\u{FFFD}", 14) + shaper.measureLineWidth("a", 14);
    try std.testing.expectApproxEqAbs(expected, metrics.prefixWidth("\xe2a"), 0.001);
    try std.testing.expectEqual(@as(usize, 1), metrics.caretInLine("\xe2ab", shaper.measureLineWidth("\u{FFFD}", 14)));
}
