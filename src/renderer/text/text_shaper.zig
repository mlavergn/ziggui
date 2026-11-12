//! Text shaping & layout: turn a UTF-8 string into positioned glyphs, measure
//! its width, and wrap it into lines. This is intentionally simple — left-to-
//! right, one glyph per codepoint, no kerning or complex-script shaping (those
//! are post-v1, see PRD §9). It is enough for crisp Latin UI text and is fully
//! testable against the bundled font.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_shaper);
const mod = @import("module.zig");

/// Decodes UTF-8 one codepoint at a time, substituting U+FFFD for bad bytes.
const CodepointIterator = struct {
    const Self = @This();

    /// The text decoded.
    text: []const u8,
    /// The byte offset of the next codepoint.
    index: usize = 0,
    /// Whether a sequence ran past the end of `text` (the next codepoint
    /// would decode differently in a longer text).
    truncated: bool = false,

    /// An iterator at the start of `text`.
    fn init(text: []const u8) Self {
        const self = Self{ .text = text };
        return self;
    }

    /// The next codepoint, or null at the end. A sequence that does not decode
    /// (a bad lead byte, a bad continuation, or one cut off by the end of
    /// `text`) is one U+FFFD for its first byte only, as the text editor's
    /// `TextLines.nextCodepointEnd` steps it, so drawn glyphs and caret stops
    /// agree on invalid text.
    fn next(self: *Self) ?u21 {
        if (self.index >= self.text.len) return null;
        const length = std.unicode.utf8ByteSequenceLength(self.text[self.index]) catch {
            self.index += 1;
            return 0xFFFD;
        };
        if (self.index + length > self.text.len) {
            self.index += 1;
            self.truncated = true;
            return 0xFFFD;
        }
        const codepoint = std.unicode.utf8Decode(self.text[self.index .. self.index + length]) catch {
            self.index += 1;
            return 0xFFFD;
        };
        self.index += length;
        return codepoint;
    }
};

/// The width of the line `wrapText` is filling, kept as it grows instead of
/// re-measured from its start for every word. It sums the same advances in the
/// same order from zero as `measureLineWidth` over the same bytes, so the
/// width is bit-identical to it.
const LineMeter = struct {
    const Self = @This();

    /// The line's first byte.
    start: usize = 0,
    /// One past the last byte measured.
    end: usize = 0,
    /// The advances of `text[start..end]`, summed left to right from zero.
    width: f32 = 0,
    /// Whether the last codepoint measured ended inside `text[start..end]`,
    /// so a longer line decodes the measured bytes the same way.
    whole: bool = true,

    /// The width of `text[start..end]`, exactly as
    /// `measureLineWidth(text[start..end])` measures it.
    fn widthOf(self: *Self, shaper: *const TextShaper, text: []const u8, start: usize, end: usize, pixel_size: f32) f32 {
        if (start != self.start or end < self.end or !self.whole) self.* = .{ .start = start, .end = start };
        var iterator = CodepointIterator{ .text = text[start..end], .index = self.end - start };
        while (iterator.next()) |codepoint| self.width += shaper.codepointAdvance(codepoint, pixel_size);
        self.end = end;
        self.whole = !iterator.truncated;
        return self.width;
    }
};

/// Measures, lays out and wraps text in one face (and its fallbacks).
pub const TextShaper = struct {
    const Self = @This();

    /// The primary face.
    face: *const mod.TtfFont,

    /// A shaper over `face`.
    ///
    /// - `face`: the primary face; it must outlive the shaper.
    /// - Returns: the shaper.
    pub fn init(face: *const mod.TtfFont) Self {
        const self = Self{ .face = face };
        return self;
    }

    /// Measure the advance width (pixels) of a single line of text. Each codepoint
    /// is resolved through the face's fallback chain, using the resolving face's own
    /// units-per-em scale (fonts differ), so fallback glyphs advance correctly.
    ///
    /// - `self`: the shaper.
    /// - `text`: the UTF-8 line.
    /// - `pixel_size`: the em size in pixels.
    /// - Returns: the width in pixels.
    pub fn measureLineWidth(self: *const Self, text: []const u8, pixel_size: f32) f32 {
        var width: f32 = 0;
        var iterator = CodepointIterator.init(text);
        while (iterator.next()) |codepoint| width += self.codepointAdvance(codepoint, pixel_size);
        return width;
    }

    /// The line height (pixels): ascent − descent + line gap, scaled.
    ///
    /// - `self`: the shaper.
    /// - `pixel_size`: the em size in pixels.
    /// - Returns: the line height in pixels.
    pub fn lineHeight(self: *const Self, pixel_size: f32) f32 {
        const scale = self.face.scaleForPixelSize(pixel_size);
        const ascent: f32 = @floatFromInt(self.face.ascent);
        const descent: f32 = @floatFromInt(self.face.descent);
        const line_gap: f32 = @floatFromInt(self.face.line_gap);
        return (ascent - descent + line_gap) * scale;
    }

    /// Distance from the top of a line to the baseline (pixels).
    ///
    /// - `self`: the shaper.
    /// - `pixel_size`: the em size in pixels.
    /// - Returns: the ascent in pixels.
    pub fn ascentPixels(self: *const Self, pixel_size: f32) f32 {
        return @as(f32, @floatFromInt(self.face.ascent)) * self.face.scaleForPixelSize(pixel_size);
    }

    /// Lay out a single line into positioned glyphs starting at pen x = `start_x`.
    /// Caller owns the returned slice.
    ///
    /// - `self`: the shaper.
    /// - `allocator`: allocator for the returned slice.
    /// - `text`: the UTF-8 line.
    /// - `pixel_size`: the em size in pixels.
    /// - `start_x`: the pen's starting x.
    /// - Returns: the glyphs; propagates allocation failure.
    pub fn layoutLine(self: *const Self, allocator: std.mem.Allocator, text: []const u8, pixel_size: f32, start_x: f32) ![]mod.PositionedGlyph {
        var glyphs: std.ArrayList(mod.PositionedGlyph) = .empty;
        errdefer glyphs.deinit(allocator);
        var pen = start_x;
        var iterator = CodepointIterator.init(text);
        while (iterator.next()) |codepoint| {
            const resolved = self.face.resolve(codepoint);
            const scale = resolved.face.scaleForPixelSize(pixel_size);
            const advance = @as(f32, @floatFromInt(resolved.face.advanceWidth(resolved.glyph))) * scale;
            try glyphs.append(allocator, .{ .glyph = resolved.glyph, .face = resolved.face, .x = pen, .advance = advance });
            pen += advance;
        }
        return glyphs.toOwnedSlice(allocator);
    }

    /// Greedy word-wrap of `text` to `max_width` pixels. Returns byte ranges into
    /// `text` for each line. Words are split on ASCII spaces; a word wider than a
    /// whole line on its own (a path, a URL) is broken at codepoint boundaries.
    /// Caller owns the slice.
    ///
    /// - `self`: the shaper.
    /// - `allocator`: allocator for the returned slice.
    /// - `text`: the UTF-8 text.
    /// - `pixel_size`: the em size in pixels.
    /// - `max_width`: the widest a line may be, in pixels.
    /// - Returns: the lines; propagates allocation failure.
    pub fn wrapText(self: *const Self, allocator: std.mem.Allocator, text: []const u8, pixel_size: f32, max_width: f32) ![]mod.WrappedLine {
        var lines: std.ArrayList(mod.WrappedLine) = .empty;
        errdefer lines.deinit(allocator);

        var line_start: usize = 0;
        var line_end: usize = 0; // exclusive end of committed content on the line
        var meter = LineMeter{};
        var index: usize = 0;
        while (index < text.len) {
            // find next word [word_start, word_end) and following whitespace end
            const word_start = index;
            while (index < text.len and text[index] != ' ' and text[index] != '\n') : (index += 1) {}
            const word_end = index;
            // candidate line is [line_start, word_end)
            const candidate_width = meter.widthOf(self, text, line_start, word_end, pixel_size);
            if (candidate_width > max_width and line_end > line_start) {
                // commit current line, start new one at this word
                try lines.append(allocator, .{
                    .start = line_start,
                    .end = line_end,
                    .width = meter.widthOf(self, text, line_start, line_end, pixel_size),
                });
                line_start = word_start;
            }
            // An unbreakable word that overflows a whole line by itself: emit
            // codepoint-boundary chunks; the final chunk stays as the open line so
            // following words can join it.
            if (line_start == word_start and
                meter.widthOf(self, text, word_start, word_end, pixel_size) > max_width)
            {
                var iterator = CodepointIterator.init(text[word_start..word_end]);
                var chunk_start = word_start;
                var chunk_width: f32 = 0;
                while (true) {
                    const offset = word_start + iterator.index;
                    const codepoint = iterator.next() orelse break;
                    const advance = self.codepointAdvance(codepoint, pixel_size);
                    if (chunk_width + advance > max_width and offset > chunk_start) {
                        try lines.append(allocator, .{ .start = chunk_start, .end = offset, .width = chunk_width });
                        chunk_start = offset;
                        chunk_width = advance;
                    } else {
                        chunk_width += advance;
                    }
                }
                line_start = chunk_start;
            }
            line_end = word_end;

            // handle explicit newline / spaces
            if (index < text.len and text[index] == '\n') {
                try lines.append(allocator, .{
                    .start = line_start,
                    .end = line_end,
                    .width = meter.widthOf(self, text, line_start, line_end, pixel_size),
                });
                index += 1;
                line_start = index;
                line_end = index;
            } else {
                // skip spaces
                while (index < text.len and text[index] == ' ') : (index += 1) {}
            }
        }
        if (line_end > line_start or lines.items.len == 0) {
            try lines.append(allocator, .{
                .start = line_start,
                .end = line_end,
                .width = meter.widthOf(self, text, line_start, line_end, pixel_size),
            });
        }
        return lines.toOwnedSlice(allocator);
    }

    /// A codepoint's advance in pixels, from the face of the fallback chain
    /// that carries it, at that face's own scale.
    fn codepointAdvance(self: *const Self, codepoint: u21, pixel_size: f32) f32 {
        const resolved = self.face.resolve(codepoint);
        const scale = resolved.face.scaleForPixelSize(pixel_size);
        return @as(f32, @floatFromInt(resolved.face.advanceWidth(resolved.glyph))) * scale;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// `wrapText` as it was, re-measuring the line from its start for every word.
/// The tests check the running width against it bit for bit.
const TestQuadraticWrap = struct {
    const Self = @This();

    /// Wrap `text` the original way.
    fn wrap(shaper: *const TextShaper, allocator: std.mem.Allocator, text: []const u8, pixel_size: f32, max_width: f32) ![]mod.WrappedLine {
        var lines: std.ArrayList(mod.WrappedLine) = .empty;
        errdefer lines.deinit(allocator);
        var line_start: usize = 0;
        var line_end: usize = 0;
        var index: usize = 0;
        while (index < text.len) {
            const word_start = index;
            while (index < text.len and text[index] != ' ' and text[index] != '\n') : (index += 1) {}
            const word_end = index;
            if (shaper.measureLineWidth(text[line_start..word_end], pixel_size) > max_width and line_end > line_start) {
                try lines.append(allocator, .{ .start = line_start, .end = line_end, .width = shaper.measureLineWidth(text[line_start..line_end], pixel_size) });
                line_start = word_start;
            }
            if (line_start == word_start and shaper.measureLineWidth(text[word_start..word_end], pixel_size) > max_width) {
                var iterator = CodepointIterator.init(text[word_start..word_end]);
                var chunk_start = word_start;
                var chunk_width: f32 = 0;
                while (true) {
                    const offset = word_start + iterator.index;
                    const codepoint = iterator.next() orelse break;
                    const resolved = shaper.face.resolve(codepoint);
                    const advance = @as(f32, @floatFromInt(resolved.face.advanceWidth(resolved.glyph))) * resolved.face.scaleForPixelSize(pixel_size);
                    if (chunk_width + advance > max_width and offset > chunk_start) {
                        try lines.append(allocator, .{ .start = chunk_start, .end = offset, .width = chunk_width });
                        chunk_start = offset;
                        chunk_width = advance;
                    } else {
                        chunk_width += advance;
                    }
                }
                line_start = chunk_start;
            }
            line_end = word_end;
            if (index < text.len and text[index] == '\n') {
                try lines.append(allocator, .{ .start = line_start, .end = line_end, .width = shaper.measureLineWidth(text[line_start..line_end], pixel_size) });
                index += 1;
                line_start = index;
                line_end = index;
            } else {
                while (index < text.len and text[index] == ' ') : (index += 1) {}
            }
        }
        if (line_end > line_start or lines.items.len == 0) {
            try lines.append(allocator, .{ .start = line_start, .end = line_end, .width = shaper.measureLineWidth(text[line_start..line_end], pixel_size) });
        }
        return lines.toOwnedSlice(allocator);
    }
};

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "shape: measureLineWidth grows with text length" {
    var face = try mod.TtfFont.parse(mod.TtfFont.inter_ttf);
    const shaper = TextShaper.init(&face);
    const one = shaper.measureLineWidth("i", 16);
    const four = shaper.measureLineWidth("iiii", 16);
    try std.testing.expect(one > 0);
    try std.testing.expect(four > one * 3); // ~4x one glyph
    try std.testing.expectEqual(@as(f32, 0), shaper.measureLineWidth("", 16));
}

test "shape: lineHeight and ascent are positive and ordered" {
    var face = try mod.TtfFont.parse(mod.TtfFont.inter_ttf);
    const shaper = TextShaper.init(&face);
    const line_height = shaper.lineHeight(16);
    const ascent = shaper.ascentPixels(16);
    try std.testing.expect(line_height > 0);
    try std.testing.expect(ascent > 0 and ascent < line_height);
}

test "shape: layoutLine positions glyphs left to right" {
    var face = try mod.TtfFont.parse(mod.TtfFont.inter_ttf);
    const glyphs = try TextShaper.init(&face).layoutLine(std.testing.allocator, "Hi", 16, 0);
    defer std.testing.allocator.free(glyphs);
    try std.testing.expectEqual(@as(usize, 2), glyphs.len);
    try std.testing.expectEqual(@as(f32, 0), glyphs[0].x);
    try std.testing.expect(glyphs[1].x > 0); // second glyph advanced past the first
    try std.testing.expectApproxEqAbs(glyphs[0].advance, glyphs[1].x, 0.01);
}

test "shape: wrapText breaks on width and on newlines" {
    var face = try mod.TtfFont.parse(mod.TtfFont.inter_ttf);
    const shaper = TextShaper.init(&face);
    const max = shaper.measureLineWidth("hello hello", 16) - 1; // forces a break
    const lines = try shaper.wrapText(std.testing.allocator, "hello hello hello", 16, max);
    defer std.testing.allocator.free(lines);
    try std.testing.expect(lines.len >= 2);

    const newline = try shaper.wrapText(std.testing.allocator, "a\nb", 16, 10000);
    defer std.testing.allocator.free(newline);
    try std.testing.expectEqual(@as(usize, 2), newline.len);
}

test "shape: wrapText breaks an unbreakable over-long word mid-token" {
    var face = try mod.TtfFont.parse(mod.TtfFont.inter_ttf);
    const shaper = TextShaper.init(&face);
    // A path-like token with no spaces, wrapped far narrower than its width.
    const token = "/Users/david/models/unsloth/FLUX.2-klein-4B-GGUF.safetensors";
    const max = shaper.measureLineWidth(token, 16) / 3;
    const lines = try shaper.wrapText(std.testing.allocator, token, 16, max);
    defer std.testing.allocator.free(lines);
    try std.testing.expect(lines.len >= 3);
    // every emitted line fits, and together they cover the whole token
    var covered: usize = 0;
    for (lines) |line| {
        try std.testing.expect(line.width <= max);
        covered += line.end - line.start;
    }
    try std.testing.expectEqual(token.len, covered);

    // a broken word's tail still shares its line with the following word
    const text = "/an/over/long/unbreakable/path then words";
    const half = shaper.measureLineWidth(text, 16) / 2;
    const mixed = try shaper.wrapText(std.testing.allocator, text, 16, half);
    defer std.testing.allocator.free(mixed);
    for (mixed) |line| try std.testing.expect(line.width <= half + 0.01);
}

test "shape: invalid UTF-8 yields a measurable result (no crash)" {
    var face = try mod.TtfFont.parse(mod.TtfFont.inter_ttf);
    const bad = [_]u8{ 0xFF, 'A' };
    const width = TextShaper.init(&face).measureLineWidth(&bad, 16);
    try std.testing.expect(width > 0);
}

test "shape: wrapText's running width matches re-measuring every line, bit for bit" {
    const allocator = std.testing.allocator;
    var face = try mod.TtfFont.parse(mod.TtfFont.inter_ttf);
    var emoji = try mod.TtfFont.parse(mod.TtfFont.emoji_ttf);
    face.fallback = &emoji;
    const shaper = TextShaper.init(&face);
    // Words, runs of spaces, newlines, an unbreakable path, accents, CJK the
    // faces lack, emoji from the fallback, and invalid UTF-8 cut by a space.
    const pieces = [_][]const u8{
        "The quick brown fox jumps over the lazy dog. ",
        "naïve café déjà vu  ",
        "/Users/someone/a/very/long/unbreakable/path/to/a/file.safetensors ",
        "\u{1F600}\u{1F680} emoji\u{2764} ",
        "漢字かな ",
        "bad\xE2 bytes\xF0\x9F x\xFF y ",
        "\n",
        "end\xE2\x82",
    };
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(allocator);
    var piece_index: usize = 0;
    while (text.items.len < 6000) : (piece_index += 7) try text.appendSlice(allocator, pieces[piece_index % pieces.len]);
    for ([_]f32{ 1, 40, 97.5, 180, 333, 10000 }) |max_width| {
        const expected = try TestQuadraticWrap.wrap(&shaper, allocator, text.items, 15, max_width);
        defer allocator.free(expected);
        const lines = try shaper.wrapText(allocator, text.items, 15, max_width);
        defer allocator.free(lines);
        try std.testing.expectEqual(expected.len, lines.len);
        for (expected, lines) |want, got| {
            try std.testing.expectEqual(want.start, got.start);
            try std.testing.expectEqual(want.end, got.end);
            try std.testing.expectEqual(@as(u32, @bitCast(want.width)), @as(u32, @bitCast(got.width)));
        }
    }
}

test "CodepointIterator steps a sequence that does not decode one byte at a time" {
    // A bad continuation: the lead byte alone becomes U+FFFD, then `a` and `b`.
    var bad = CodepointIterator.init("\xE2ab");
    try std.testing.expectEqual(@as(?u21, 0xFFFD), bad.next());
    try std.testing.expectEqual(@as(?u21, 'a'), bad.next());
    try std.testing.expectEqual(@as(?u21, 'b'), bad.next());
    try std.testing.expectEqual(@as(?u21, null), bad.next());
    try std.testing.expect(!bad.truncated);

    // A sequence cut off by the end: one U+FFFD per byte, marked truncated.
    var cut = CodepointIterator.init("a\xE2\x82");
    try std.testing.expectEqual(@as(?u21, 'a'), cut.next());
    try std.testing.expectEqual(@as(?u21, 0xFFFD), cut.next());
    try std.testing.expectEqual(@as(?u21, 0xFFFD), cut.next());
    try std.testing.expectEqual(@as(?u21, null), cut.next());
    try std.testing.expect(cut.truncated);

    // Valid text is unchanged.
    var valid = CodepointIterator.init("é€");
    try std.testing.expectEqual(@as(?u21, 0xE9), valid.next());
    try std.testing.expectEqual(@as(?u21, 0x20AC), valid.next());
    try std.testing.expectEqual(@as(?u21, null), valid.next());
}
