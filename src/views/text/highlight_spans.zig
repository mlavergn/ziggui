//! A line of text with some of its byte ranges marked, as the spans a
//! preformatted `RichText` draws: the text between the ranges in one style,
//! each range in another, and one of them, the current, in a third. Shared
//! by `HighlightedText` (a search result) and a diff find's rows. A range
//! end inside a character widens to the whole character, so a bad byte or a
//! multi-byte character is never cut.

const std = @import("std");
const log = std.log.scoped(.ziggui_highlight_spans);
const mod = @import("module.zig");

/// How each part of a highlighted line is drawn: three spans whose `text` is ignored.
pub const HighlightStyle = struct {
    const Self = @This();

    /// The text between the ranges.
    plain: mod.Span = .{ .text = "" },
    /// Each range.
    marked: mod.Span,
    /// The current range; null draws it as `marked`.
    current: ?mod.Span = null,
};

/// Builds a highlighted line's spans.
pub const HighlightSpans = struct {
    const Self = @This();

    /// The spans of `text` with `ranges` marked: at most a gap before each
    /// range, the range, and the rest after the last, `2·ranges+1` in all.
    /// A range overlapping the one before, empty, or past the text is skipped.
    ///
    /// - `arena`: where the spans are allocated (the build arena, in a view).
    /// - `text`: the line; the spans borrow it.
    /// - `ranges`: byte ranges of `text`, left to right.
    /// - `current`: the index in `ranges` of the current one, if any.
    /// - `style`: how each part is drawn.
    /// - Returns: the spans; propagates allocation failure.
    pub fn build(arena: std.mem.Allocator, text: []const u8, ranges: []const mod.TextRange, current: ?usize, style: HighlightStyle) std.mem.Allocator.Error![]const mod.Span {
        const characters = mod.TextLines.init(text);
        const spans = try arena.alloc(mod.Span, 2 * ranges.len + 1);
        var count: usize = 0;
        var cursor: usize = 0;
        for (ranges, 0..) |range, index| {
            if (range.start < cursor or range.start >= range.end or range.end > text.len) continue;
            const start = Self.characterStart(&characters, cursor, range.start);
            const end = Self.characterEnd(&characters, start, range.end);
            if (start > cursor) {
                spans[count] = Self.part(style.plain, text[cursor..start]);
                count += 1;
            }
            const is_current = current != null and current.? == index;
            spans[count] = Self.part(if (is_current) style.current orelse style.marked else style.marked, text[start..end]);
            count += 1;
            cursor = end;
        }
        if (cursor < text.len or count == 0) {
            spans[count] = Self.part(style.plain, text[cursor..]);
            count += 1;
        }
        return spans[0..count];
    }

    /// A style's span over some text.
    ///
    /// - `template`: the style.
    /// - `text`: the text.
    /// - Returns: the span.
    fn part(template: mod.Span, text: []const u8) mod.Span {
        var span = template;
        span.text = text;
        return span;
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

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "highlight spans: gaps and ranges alternate, the current drawn apart, a bad range skipped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const style: HighlightStyle = .{ .plain = .{ .text = "", .mono = true }, .marked = .{ .text = "", .italic = true }, .current = .{ .text = "", .underline = true } };
    const ranges = [_]mod.TextRange{ .{ .start = 0, .end = 1 }, .{ .start = 4, .end = 5 }, .{ .start = 4, .end = 6 }, .{ .start = 9, .end = 20 } };
    const spans = try HighlightSpans.build(arena.allocator(), "a b a c", &ranges, 1, style);
    try std.testing.expectEqual(@as(usize, 4), spans.len);
    try std.testing.expectEqualStrings("a", spans[0].text);
    try std.testing.expect(spans[0].italic and !spans[0].underline);
    try std.testing.expectEqualStrings(" b ", spans[1].text);
    try std.testing.expect(spans[1].mono);
    try std.testing.expectEqualStrings("a", spans[2].text);
    try std.testing.expect(spans[2].underline);
    try std.testing.expectEqualStrings(" c", spans[3].text);
}

test "highlight spans: a range ending inside a character takes the whole character" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // "é" is two bytes; a range of its first byte widens to both.
    const spans = try HighlightSpans.build(arena.allocator(), "caf\xc3\xa9!", &.{.{ .start = 3, .end = 4 }}, null, .{ .marked = .{ .text = "", .italic = true } });
    try std.testing.expectEqualStrings("caf", spans[0].text);
    try std.testing.expectEqualStrings("\xc3\xa9", spans[1].text);
    try std.testing.expectEqualStrings("!", spans[2].text);
}
