//! How a multi-line editor indents: with tab characters or with spaces, and
//! how many columns a level (and a tab stop) is.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_indentation);

/// What Tab inserts.
pub const IndentationStyle = enum {
    const Self = @This();

    /// Spaces up to the next stop.
    spaces,

    /// One tab character.
    tabs,
};

/// An editor's indentation: its style and its width in columns, which is
/// also where tab characters stop.
pub const TextIndentation = struct {
    const Self = @This();

    /// What Tab inserts.
    style: IndentationStyle = .spaces,

    /// A level's width in columns, and the tab stop (1 to `max_width`).
    width: u8 = 4,

    /// The widest level `detect` and the editor take.
    pub const max_width: u8 = 16;

    /// The width, at least 1 and at most `max_width`.
    ///
    /// - `self`: the indentation.
    /// - Returns: the columns a level takes.
    pub fn columns(self: *const Self) usize {
        return std.math.clamp(self.width, 1, max_width);
    }

    /// The columns a line's leading whitespace reaches, tabs stopping at
    /// multiples of the width.
    ///
    /// - `self`: the indentation.
    /// - `leading`: the line's leading spaces and tabs.
    /// - Returns: the column the text after them starts at.
    pub fn visualColumns(self: *const Self, leading: []const u8) usize {
        const width = self.columns();
        var column: usize = 0;
        for (leading) |byte| {
            column = if (byte == '\t') (column / width + 1) * width else column + 1;
        }
        return column;
    }

    /// The leading whitespace that reaches `column` in this style: tabs then
    /// spaces for `.tabs`, only spaces for `.spaces`.
    ///
    /// - `self`: the indentation.
    /// - `allocator`: where the string goes.
    /// - `column`: the column to reach.
    /// - Returns: the whitespace, owned; propagates allocation failure.
    pub fn leadingAlloc(self: *const Self, allocator: std.mem.Allocator, column: usize) std.mem.Allocator.Error![]u8 {
        const width = self.columns();
        const tab_count = if (self.style == .tabs) column / width else 0;
        const space_count = column - tab_count * width;
        const leading = try allocator.alloc(u8, tab_count + space_count);
        @memset(leading[0..tab_count], '\t');
        @memset(leading[tab_count..], ' ');
        return leading;
    }

    /// Guesses a text's indentation from its lines' leading whitespace: tabs
    /// when more lines start with a tab than with spaces, else spaces with
    /// the step most often seen between one indented line and the next.
    ///
    /// - `text`: the text.
    /// - Returns: the indentation, or null when no line is indented.
    pub fn detect(text: []const u8) ?Self {
        var tab_lines: usize = 0;
        var space_lines: usize = 0;
        // How often each step (1 to `max_width` columns) appears between neighbours.
        var steps: [max_width + 1]usize = @splat(0);
        var previous_spaces: usize = 0;
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trimEnd(u8, raw, "\r");
            if (std.mem.trim(u8, line, " \t").len == 0) continue;
            if (line[0] == '\t') {
                tab_lines += 1;
                continue;
            }
            var spaces: usize = 0;
            while (spaces < line.len and line[spaces] == ' ') spaces += 1;
            if (spaces > 0) space_lines += 1;
            const step = if (spaces > previous_spaces) spaces - previous_spaces else previous_spaces - spaces;
            if (step > 0 and step <= max_width) steps[step] += 1;
            previous_spaces = spaces;
        }
        if (tab_lines == 0 and space_lines == 0) return null;
        if (tab_lines > space_lines) return .{ .style = .tabs };
        // The most frequent step, the narrower on a tie; 4 when none was seen.
        var best: usize = 4;
        var best_count: usize = 0;
        for (steps[1..], 1..) |count, step| {
            if (count > best_count) {
                best = step;
                best_count = count;
            }
        }
        return .{ .style = .spaces, .width = @intCast(best) };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "indentation: detect reads tabs, two spaces and four" {
    try std.testing.expectEqual(IndentationStyle.tabs, TextIndentation.detect("a\n\tb\n\t\tc\n").?.style);
    const two = TextIndentation.detect("a {\n  b {\n    c\n  }\n}\n").?;
    try std.testing.expectEqual(IndentationStyle.spaces, two.style);
    try std.testing.expectEqual(@as(u8, 2), two.width);
    const four = TextIndentation.detect("fn a() {\r\n    b();\r\n    if (c) {\r\n        d();\r\n    }\r\n}\r\n").?;
    try std.testing.expectEqual(@as(u8, 4), four.width);
    try std.testing.expect(TextIndentation.detect("flat\ntext\n") == null);
}

test "indentation: columns and leading whitespace" {
    const tabs: TextIndentation = .{ .style = .tabs, .width = 4 };
    try std.testing.expectEqual(@as(usize, 8), tabs.visualColumns("\t  \t"));
    const leading = try tabs.leadingAlloc(std.testing.allocator, 10);
    defer std.testing.allocator.free(leading);
    try std.testing.expectEqualStrings("\t\t  ", leading);
    const spaces: TextIndentation = .{ .width = 2 };
    const spaced = try spaces.leadingAlloc(std.testing.allocator, 3);
    defer std.testing.allocator.free(spaced);
    try std.testing.expectEqualStrings("   ", spaced);
}
