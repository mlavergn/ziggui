//! Inline-styled, word-wrapped text: a paragraph made of spans that differ in
//! weight/italic/mono/colour/background/underline/link. Pure layout (no
//! Canvas/Context): `RichLayout.layOut` places runs into lines; the view layer
//! paints them.

const std = @import("std");
const log = std.log.scoped(.ziggui_rich_layout);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A word, a run of spaces and tabs, or a newline in a span's text.
const Token = struct {
    const Self = @This();

    /// The first byte.
    start: usize,

    /// One past the last byte.
    end: usize,

    /// Spaces, tabs or a newline rather than a word.
    space: bool,

    /// The token starting at `index`.
    ///
    /// - `text`: the span's text.
    /// - `index`: where the token starts.
    /// - Returns: the token, or null at the end of the text.
    fn next(text: []const u8, index: usize) ?Self {
        if (index >= text.len) return null;
        if (text[index] == '\n') return .{ .start = index, .end = index + 1, .space = true };
        const space = text[index] == ' ' or text[index] == '\t';
        var stop = index;
        while (stop < text.len and text[stop] != '\n' and (text[stop] == ' ' or text[stop] == '\t') == space) stop += 1;
        return .{ .start = index, .end = stop, .space = space };
    }
};

/// The lines laid out so far and the one being filled.
const LineBreaker = struct {
    const Self = @This();

    /// Where lines and runs are allocated.
    arena: std.mem.Allocator,

    /// Line height as a multiple of the tallest run's.
    line_multiple: f32,

    /// The finished lines.
    lines: std.ArrayList(mod.RichLine) = .empty,

    /// Every run so far; the current line's start at `line_start_run`.
    runs: std.ArrayList(mod.RichRun) = .empty,

    /// The current line's width so far.
    x: f32 = 0,

    /// The current line's top.
    y: f32 = 0,

    /// The current line's tallest ascent.
    max_ascent: f32 = 0,

    /// The current line's deepest descent.
    max_descent: f32 = 0,

    /// The current line's first run.
    line_start_run: usize = 0,

    /// The widest finished line.
    widest: f32 = 0,

    /// Adds a run at the current `x`, merged with the previous run on this
    /// line when it continues the same span.
    ///
    /// - `self`: the breaker.
    /// - `span`: the span's index.
    /// - `start`: the run's first byte.
    /// - `end`: one past its last byte.
    /// - `width`: its width.
    /// - Returns: nothing; propagates allocation failure.
    fn appendRun(self: *Self, span: u32, start: usize, end: usize, width: f32) std.mem.Allocator.Error!void {
        // Merge with the previous run on THIS line when it continues the same span.
        if (self.runs.items.len > self.line_start_run) {
            const last = &self.runs.items[self.runs.items.len - 1];
            if (last.span == span and last.end == start) {
                last.end = @intCast(end);
                last.width += width;
                return;
            }
        }
        try self.runs.append(self.arena, .{ .span = span, .start = @intCast(start), .end = @intCast(end), .x = self.x, .width = width });
    }

    /// Ends the current line and starts the next below it.
    ///
    /// - `self`: the breaker.
    /// - `fallback_height`: the line's height when it holds no runs.
    /// - Returns: nothing; propagates allocation failure.
    fn finishLine(self: *Self, fallback_height: f32) std.mem.Allocator.Error!void {
        const content_height = self.max_ascent + self.max_descent;
        const height = (if (content_height > 0) content_height else fallback_height) * self.line_multiple;
        const owned = try self.arena.dupe(mod.RichRun, self.runs.items[self.line_start_run..]);
        try self.lines.append(self.arena, .{
            .runs = owned,
            .y = self.y,
            .height = height,
            .baseline = (height - content_height) / 2 + self.max_ascent,
            .width = self.x,
        });
        self.widest = @max(self.widest, self.x);
        self.y += height;
        self.max_ascent = 0;
        self.max_descent = 0;
        self.x = 0;
        self.line_start_run = self.runs.items.len;
    }
};

/// A laid-out rich paragraph: its lines and its size.
pub const RichLayout = struct {
    const Self = @This();

    /// The lines, top to bottom.
    lines: []mod.RichLine = &.{},

    /// The widest line's width.
    width: f32 = 0,

    /// The lines' total height.
    height: f32 = 0,

    /// Lays `spans` out in `max_width`.
    ///
    /// - `arena`: where the lines and runs are allocated.
    /// - `spans`: the paragraph.
    /// - `faces`: the faces the spans are measured in.
    /// - `pixel_size`: the base text size.
    /// - `line_multiple`: line height as a multiple of the tallest run's.
    /// - `max_width`: the width lines wrap at.
    /// - `preformatted`: preformatted: leading spaces survive and lines never wrap (code).
    /// - Returns: the layout; propagates allocation failure.
    pub fn layOut(
        arena: std.mem.Allocator,
        spans: []const mod.Span,
        faces: mod.RichFaces,
        pixel_size: f32,
        line_multiple: f32,
        max_width: f32,
        preformatted: bool,
    ) std.mem.Allocator.Error!Self {
        const wrap_width: f32 = if (preformatted) 1.0e9 else max_width;
        var breaker = LineBreaker{ .arena = arena, .line_multiple = line_multiple };
        var line_has_content = false;

        for (spans, 0..) |span, span_index| {
            const face = faces.forSpan(span);
            const span_pixel_size = pixel_size * span.size_scale;
            const ascent = renderer.TextShaper.init(face).ascentPixels(span_pixel_size);
            const line_height = renderer.TextShaper.init(face).lineHeight(span_pixel_size);
            var index: usize = 0;
            while (Token.next(span.text, index)) |token| {
                index = token.end;
                const piece = span.text[token.start..token.end];
                if (piece.len == 1 and piece[0] == '\n') {
                    try breaker.finishLine(line_height);
                    line_has_content = false;
                    continue;
                }
                const width = renderer.TextShaper.init(face).measureLineWidth(piece, span_pixel_size);
                if (token.space) {
                    if (!line_has_content and !preformatted) continue; // no leading spaces on a wrapped line
                    if (breaker.x + width > wrap_width) {
                        // A space that would overflow ends the line instead of wrapping.
                        try breaker.finishLine(line_height);
                        line_has_content = false;
                        continue;
                    }
                } else if (breaker.x + width > wrap_width and line_has_content) {
                    try breaker.finishLine(line_height);
                    line_has_content = false;
                }
                // A single word wider than the line breaks at codepoint boundaries.
                if (!token.space and width > wrap_width) {
                    var piece_start: usize = token.start;
                    while (piece_start < token.end) {
                        var piece_end = piece_start;
                        var piece_width: f32 = 0;
                        while (piece_end < token.end) {
                            const next_end = @min(mod.TextLines.init(span.text).nextCodepointEnd(piece_end), token.end);
                            const glyph_width = renderer.TextShaper.init(face).measureLineWidth(span.text[piece_end..next_end], span_pixel_size);
                            if (piece_width + glyph_width > wrap_width - breaker.x and piece_end > piece_start) break;
                            piece_width += glyph_width;
                            piece_end = next_end;
                        }
                        try breaker.appendRun(@intCast(span_index), piece_start, piece_end, piece_width);
                        breaker.max_ascent = @max(breaker.max_ascent, ascent);
                        breaker.max_descent = @max(breaker.max_descent, line_height - ascent);
                        breaker.x += piece_width;
                        line_has_content = true;
                        piece_start = piece_end;
                        if (piece_start < token.end) {
                            try breaker.finishLine(line_height);
                            line_has_content = false;
                        }
                    }
                    continue;
                }
                try breaker.appendRun(@intCast(span_index), token.start, token.end, width);
                breaker.max_ascent = @max(breaker.max_ascent, ascent);
                breaker.max_descent = @max(breaker.max_descent, line_height - ascent);
                breaker.x += width;
                if (!token.space) line_has_content = true;
            }
        }
        if (breaker.runs.items.len > breaker.line_start_run or breaker.lines.items.len == 0) {
            const base_face = faces.fallback;
            try breaker.finishLine(renderer.TextShaper.init(base_face).lineHeight(pixel_size));
        }
        const self = Self{ .lines = try breaker.lines.toOwnedSlice(arena), .width = breaker.widest, .height = breaker.y };
        return self;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "richtext: one short span is one line" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const font = try renderer.TtfFont.parse(renderer.TtfFont.inter_ttf);
    const faces = mod.RichFaces{ .fallback = &font };
    const layout = try RichLayout.layOut(arena_state.allocator(), &.{.{ .text = "hello world" }}, faces, 14, 1.2, 500, false);
    try std.testing.expectEqual(@as(usize, 1), layout.lines.len);
    try std.testing.expect(layout.height > 14);
}

test "richtext: wraps at a space and drops the leading space" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const font = try renderer.TtfFont.parse(renderer.TtfFont.inter_ttf);
    const faces = mod.RichFaces{ .fallback = &font };
    const width = renderer.TextShaper.init(&font).measureLineWidth("hello wor", 14);
    const layout = try RichLayout.layOut(arena_state.allocator(), &.{.{ .text = "hello world again" }}, faces, 14, 1.0, width, false);
    try std.testing.expect(layout.lines.len >= 2);
    const first = layout.lines[1].runs[0];
    try std.testing.expect("hello world again"[first.start] != ' ');
}

test "richtext: explicit newline breaks a line" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const font = try renderer.TtfFont.parse(renderer.TtfFont.inter_ttf);
    const faces = mod.RichFaces{ .fallback = &font };
    const layout = try RichLayout.layOut(arena_state.allocator(), &.{.{ .text = "a\nb" }}, faces, 14, 1.0, 500, false);
    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);
}

test "richtext: a word wider than the line splits across lines" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const font = try renderer.TtfFont.parse(renderer.TtfFont.inter_ttf);
    const faces = mod.RichFaces{ .fallback = &font };
    const layout = try RichLayout.layOut(arena_state.allocator(), &.{.{ .text = "supercalifragilisticexpialidocious" }}, faces, 14, 1.0, 60, false);
    try std.testing.expect(layout.lines.len >= 3);
    for (layout.lines) |line| try std.testing.expect(line.width <= 60.5);
}

test "richtext: pre mode keeps leading spaces and never wraps" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const font = try renderer.TtfFont.parse(renderer.TtfFont.inter_ttf);
    const faces = mod.RichFaces{ .fallback = &font };
    const layout = try RichLayout.layOut(arena_state.allocator(), &.{.{ .text = "    return value_that_is_quite_long_indeed" }}, faces, 14, 1.0, 40, true);
    try std.testing.expectEqual(@as(usize, 1), layout.lines.len);
    try std.testing.expectEqual(@as(u32, 0), layout.lines[0].runs[0].start);
}

test "richtext: styled spans share a line and keep order" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const font = try renderer.TtfFont.parse(renderer.TtfFont.inter_ttf);
    const faces = mod.RichFaces{ .fallback = &font };
    const layout = try RichLayout.layOut(arena_state.allocator(), &.{
        .{ .text = "see " },
        .{ .text = "code", .mono = true },
        .{ .text = " here" },
    }, faces, 14, 1.0, 500, false);
    try std.testing.expectEqual(@as(usize, 1), layout.lines.len);
    var previous: f32 = -1;
    for (layout.lines[0].runs) |run| {
        try std.testing.expect(run.x >= previous);
        previous = run.x;
    }
    try std.testing.expectEqual(@as(u32, 1), layout.lines[0].runs[1].span);
}
