//! Text views: one line, a wrapped paragraph, and styled rich text.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_text);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The helpers `HighlightedText` lays its runs out with.
const Highlight = struct {
    const Self = @This();

    /// The text with each line break (`\n`, `\r`) as a space, byte for
    /// byte, so ranges into the text still index it.
    ///
    /// - `arena`: the build arena, for the copy.
    /// - `string`: the text.
    /// - Returns: `string` itself when it has no line break, else the copy.
    fn oneLine(arena: std.mem.Allocator, string: []const u8) []const u8 {
        if (std.mem.findAny(u8, string, "\r\n") == null) return string;
        const copy = arena.dupe(u8, string) catch @panic("oom");
        for (copy) |*byte| {
            if (byte.* == '\n' or byte.* == '\r') byte.* = ' ';
        }
        return copy;
    }

    /// The first byte of the character holding byte `index`, stepping
    /// forward from `from` as the text is drawn.
    ///
    /// - `characters`: the text.
    /// - `from`: a character's first byte at or before `index`.
    /// - `index`: a byte inside the text.
    /// - Returns: the character's first byte, at least `from`.
    fn characterStart(characters: *const mod.TextLines, from: usize, index: usize) usize {
        var boundary = from;
        while (boundary < index) {
            const next = characters.nextCodepointEnd(boundary);
            if (next > index) break;
            boundary = next;
        }
        return boundary;
    }

    /// The first character boundary at or past byte `index`.
    ///
    /// - `characters`: the text.
    /// - `from`: a character's first byte at or before `index`.
    /// - `index`: a byte index, at most the text's length.
    /// - Returns: the boundary.
    fn characterEnd(characters: *const mod.TextLines, from: usize, index: usize) usize {
        var boundary = from;
        while (boundary < index) boundary = characters.nextCodepointEnd(boundary);
        return boundary;
    }
};

/// One line of text.
///
/// - `string`: the text.
/// - Returns: the view.
pub fn Text(string: []const u8) mod.View {
    return .{ .kind = .{ .text = .{ .string = string } } };
}

/// Multi-line text: word-wraps to the width it is proposed, growing taller as it
/// wraps. Use this (rather than `Text`) for paragraphs and chat bubbles.
///
/// - `string`: the text.
/// - Returns: the view.
pub fn WrappedText(string: []const u8) mod.View {
    return .{ .kind = .{ .wrappedText = .{ .string = string } } };
}

/// A wrapped paragraph of styled spans (bold/italic/mono/link/background...).
///
/// - `spans`: the spans, copied into the build arena.
/// - Returns: the view.
pub fn RichText(spans: []const mod.Span) mod.View {
    return RichTextSpaced(spans, 1.25);
}

/// Preformatted spans (code): leading spaces survive and lines do not wrap.
///
/// - `spans`: the spans, copied into the build arena.
/// - `line_multiple`: line height as a multiple of the font size.
/// - Returns: the view.
pub fn RichTextPreformatted(spans: []const mod.Span, line_multiple: f32) mod.View {
    var view = RichTextSpaced(spans, line_multiple);
    view.kind.richText.preformatted = true;
    return view;
}

/// A wrapped paragraph of styled spans at a given line height.
///
/// - `spans`: the spans, copied into the build arena.
/// - `line_multiple`: line height as a multiple of the font size.
/// - Returns: the view.
pub fn RichTextSpaced(spans: []const mod.Span, line_multiple: f32) mod.View {
    // Copied into the build arena: the caller's slice is usually a stack array.
    const owned = mod.BuildScope.shared().allocator().dupe(mod.Span, spans) catch @panic("oom");
    return .{ .kind = .{ .richText = .{ .spans = owned, .line_multiple = line_multiple } } };
}

/// One line of text with runs of it marked: bold on the accent's soft
/// ground, as search results mark what matched. Finding the runs is the
/// caller's, so they agree with whatever did the matching.
///
/// It is one line whatever the text holds: a line break draws as a space.
/// It takes its natural width when there is room and the width it is given
/// when there is not, clipped to it, so a narrow cell cuts it rather than
/// letting it draw over its neighbours.
///
/// - `string`: the text.
/// - `ranges`: the runs to mark, left to right and not overlapping. A run's
///   ends that fall inside a character are widened to the whole character;
///   a run that starts before the previous one ends (once widened), is
///   empty, or reaches past the text, is skipped.
/// - `weight`: the weight of the unmarked text, or null for the base weight.
/// - Returns: the view, one line high.
pub fn HighlightedText(string: []const u8, ranges: []const mod.TextRange, weight: ?renderer.FontWeight) mod.View {
    const scope = mod.BuildScope.shared();
    const tokens = scope.tokens();
    const line = Highlight.oneLine(scope.allocator(), string);
    const characters = mod.TextLines.init(line);
    // At most a gap before each run, the run, and the rest after the last.
    const spans = scope.allocator().alloc(mod.Span, 2 * ranges.len + 1) catch @panic("oom");
    var count: usize = 0;
    var cursor: usize = 0;
    for (ranges) |range| {
        if (range.start < cursor or range.start >= range.end or range.end > line.len) continue;
        const start = Highlight.characterStart(&characters, cursor, range.start);
        const end = Highlight.characterEnd(&characters, start, range.end);
        if (start > cursor) {
            spans[count] = .{ .text = line[cursor..start], .weight = weight };
            count += 1;
        }
        spans[count] = .{ .text = line[start..end], .weight = .bold, .background = tokens.accent_soft };
        count += 1;
        cursor = end;
    }
    if (cursor < line.len or count == 0) {
        spans[count] = .{ .text = line[cursor..], .weight = weight };
        count += 1;
    }
    // Built in the build arena already, so not copied again as `RichText` would.
    const view: mod.View = .{ .kind = .{ .richText = .{ .spans = spans[0..count], .line_multiple = 1, .preformatted = true } } };
    return view.clipped();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "highlighted text marks each range and keeps the text between them" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    mod.BuildScope.shared().begin(arena.allocator());
    defer mod.BuildScope.shared().end();

    const ranges = [_]mod.TextRange{ .{ .start = 3, .end = 5 }, .{ .start = 7, .end = 9 } };
    const view = HighlightedText("createdAt", &ranges, .medium);
    const spans = view.kind.richText.spans;
    try std.testing.expectEqual(@as(usize, 4), spans.len);
    try std.testing.expectEqualStrings("cre", spans[0].text);
    try std.testing.expectEqual(@as(?renderer.FontWeight, .medium), spans[0].weight);
    try std.testing.expectEqualStrings("at", spans[1].text);
    try std.testing.expectEqual(@as(?renderer.FontWeight, .bold), spans[1].weight);
    try std.testing.expectEqual(@as(?renderer.Color, mod.BuildScope.shared().tokens().accent_soft), spans[1].background);
    try std.testing.expectEqualStrings("ed", spans[2].text);
    try std.testing.expectEqual(@as(?renderer.Color, null), spans[2].background);
    try std.testing.expectEqualStrings("At", spans[3].text);
    try std.testing.expect(view.kind.richText.preformatted);
}

test "highlighted text skips ranges out of order or past the text" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    mod.BuildScope.shared().begin(arena.allocator());
    defer mod.BuildScope.shared().end();

    const ranges = [_]mod.TextRange{ .{ .start = 4, .end = 6 }, .{ .start = 2, .end = 5 }, .{ .start = 6, .end = 6 }, .{ .start = 7, .end = 40 } };
    const spans = HighlightedText("abcdefgh", &ranges, null).kind.richText.spans;
    try std.testing.expectEqual(@as(usize, 3), spans.len);
    try std.testing.expectEqualStrings("abcd", spans[0].text);
    try std.testing.expectEqualStrings("ef", spans[1].text);
    try std.testing.expectEqualStrings("gh", spans[2].text);

    // No ranges, or an empty text, is the text as one unmarked span.
    try std.testing.expectEqual(@as(usize, 1), HighlightedText("plain", &.{}, null).kind.richText.spans.len);
    try std.testing.expectEqual(@as(usize, 1), HighlightedText("", &.{}, null).kind.richText.spans.len);
}

test "highlighted text widens a range cut inside a character to the whole character" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    mod.BuildScope.shared().begin(arena.allocator());
    defer mod.BuildScope.shared().end();

    // "é" is bytes 1..3 and "ü" bytes 4..6: the first range ends inside "é",
    // the second starts inside "ü".
    const ranges = [_]mod.TextRange{ .{ .start = 0, .end = 2 }, .{ .start = 5, .end = 7 } };
    const spans = HighlightedText("aébüc", &ranges, null).kind.richText.spans;
    try std.testing.expectEqual(@as(usize, 3), spans.len);
    try std.testing.expectEqualStrings("aé", spans[0].text);
    try std.testing.expectEqualStrings("b", spans[1].text);
    try std.testing.expectEqualStrings("üc", spans[2].text);
    for (spans) |span| try std.testing.expect(std.unicode.utf8ValidateSlice(span.text));

    // A range that starts inside the character the last one widened over is skipped.
    const overlapping = [_]mod.TextRange{ .{ .start = 0, .end = 2 }, .{ .start = 2, .end = 4 } };
    const merged = HighlightedText("aébüc", &overlapping, null).kind.richText.spans;
    try std.testing.expectEqual(@as(usize, 2), merged.len);
    try std.testing.expectEqualStrings("aé", merged[0].text);
    try std.testing.expectEqualStrings("büc", merged[1].text);
}

test "highlighted text is one line, clipped to its frame" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    mod.BuildScope.shared().begin(arena.allocator());
    defer mod.BuildScope.shared().end();

    const source = "first\nsecond\r\nthird";
    const ranges = [_]mod.TextRange{.{ .start = 6, .end = 12 }};
    const view = HighlightedText(source, &ranges, null);
    const spans = view.kind.richText.spans;
    try std.testing.expectEqual(@as(usize, 3), spans.len);
    try std.testing.expectEqualStrings("first ", spans[0].text);
    try std.testing.expectEqualStrings("second", spans[1].text);
    try std.testing.expectEqualStrings("  third", spans[2].text);
    try std.testing.expect(view.modifiers.clipped);
    // The caller's text is left as it was.
    try std.testing.expectEqualStrings("first\nsecond\r\nthird", source);

    // Text without a line break is drawn from the caller's bytes, uncopied.
    const plain = "no breaks here";
    try std.testing.expectEqual(@as([*]const u8, plain.ptr), HighlightedText(plain, &.{}, null).kind.richText.spans[0].text.ptr);
}

test "highlighted text never draws past a narrow frame" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();

    window.begin(renderer.MacosTheme.light);
    const ranges = [_]mod.TextRange{.{ .start = 0, .end = 4 }};
    const cell = mod.HStack(.{ HighlightedText("a long result that cannot fit its cell", &ranges, null), mod.Spacer() }).frameWidth(60);
    const root = mod.HStack(.{ cell, mod.Spacer() });
    window.end();
    var frame = try window.render(root, 200, 30);
    defer frame.deinit();
    // The cell is drawn in, and nothing right of it (the window is cleared white).
    var inked_inside = false;
    var y: u32 = 0;
    while (y < frame.height) : (y += 1) {
        var x: u32 = 0;
        while (x < frame.width) : (x += 1) {
            const pixel = frame.rgba8At(x, y);
            const white = pixel.r == 255 and pixel.g == 255 and pixel.b == 255;
            if (x < 60 and !white) inked_inside = true;
            if (x >= 61) try std.testing.expect(white);
        }
    }
    try std.testing.expect(inked_inside);
}
