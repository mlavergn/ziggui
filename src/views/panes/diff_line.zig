//! One row of a `DiffView`, what kind of line it is, and the diff row height;
//! a diff's lines wrapped to a width (`DiffLine.wrap`), and a scroll position
//! carried from one wrapping to another (`DiffAnchor`).

const std = @import("std");
const log = std.log.scoped(.ziggui_diff_line);
const mod = @import("module.zig");

/// The height of one diff row, in points.
pub const diff_row_height: f32 = 18;

/// What a `DiffLine` is.
pub const DiffLineKind = enum {
    const Self = @This();

    /// An unchanged line.
    context,

    /// A line only the new side has.
    added,

    /// A line only the old side has.
    removed,

    /// A hunk's `@@` header.
    hunkHeader,

    /// A file's header.
    fileHeader,

    /// Any other line (`\ No newline at end of file`).
    note,
};

/// Where a scroll offset over a diff's rows falls (`DiffLine.anchorAt`), so
/// the same place can be found in the same lines wrapped to another width or
/// not at all (`DiffLine.offsetAt`).
pub const DiffAnchor = struct {
    const Self = @This();

    /// The line at the top, counted over the rows that start one (not
    /// `continued`).
    line: usize = 0,

    /// How far into the line's text the top row starts, in bytes.
    byte: usize = 0,

    /// How far past the top row's top the offset is, in points.
    within: f32 = 0,
};

/// One row of a `DiffView`: a diff line without its `+`, `-` or space, and
/// its line numbers on each side. Knows nothing of any version-control tool.
pub const DiffLine = struct {
    const Self = @This();

    /// What the line is.
    kind: DiffLineKind,

    /// The line's text.
    text: []const u8,

    /// Its number on the old side, if it has one.
    old: ?u32 = null,

    /// Its number on the new side, if it has one.
    new: ?u32 = null,

    /// Whether the row continues the line above it, wrapped (`wrap`): drawn
    /// with no line numbers or marker, and never a hunk or file of its own.
    continued: bool = false,

    /// How many hunks a diff holds.
    ///
    /// - `lines`: the diff.
    /// - Returns: the hunk count.
    pub fn hunkCount(lines: []const Self) usize {
        var count: usize = 0;
        for (lines) |line| count += @intFromBool(line.startsHunk());
        return count;
    }

    /// The row of a hunk's header.
    ///
    /// - `lines`: the diff.
    /// - `index`: the hunk.
    /// - Returns: the header's row, or null when there is no such hunk.
    pub fn hunkRow(lines: []const Self, index: usize) ?usize {
        var hunk: usize = 0;
        for (lines, 0..) |line, at| {
            if (!line.startsHunk()) continue;
            if (hunk == index) return at;
            hunk += 1;
        }
        return null;
    }

    /// Scrolls a `DiffView` so a hunk sits at its top, header first, from
    /// the left edge (a sideways scroll goes back to 0).
    ///
    /// - `scroll`: the diff's scroll position.
    /// - `lines`: the diff.
    /// - `index`: the hunk.
    pub fn revealHunk(scroll: *mod.ScrollState, lines: []const Self, index: usize) void {
        const at = Self.hunkRow(lines, index) orelse return;
        scroll.offset = @as(f32, @floatFromInt(at)) * diff_row_height;
        scroll.offset_x = 0;
    }

    /// The rows of `lines` with every line wider than `columns` cells (tabs as
    /// `DiffLayout.tab`'s spaces) split by code point into the line and rows
    /// that continue it (`continued`, no line numbers, the same kind). Hunks
    /// and their indices are unchanged, so `hunkRow` and `revealHunk` work on
    /// the wrapped rows as on the lines. A byte that does not decode is a
    /// cell of its own, as drawn (`TextLines.nextCodepointEnd`).
    ///
    /// - `allocator`: allocator for the rows and any line whose tabs were
    ///   expanded; meant for an arena, as nothing else is freed separately.
    ///   Other text borrows from `lines`.
    /// - `lines`: the diff.
    /// - `columns`: the cells a row holds (`wrapColumns`); 0 wraps nothing.
    /// - Returns: the rows, always a new slice; propagates allocation failure.
    pub fn wrap(allocator: std.mem.Allocator, lines: []const Self, columns: usize) std.mem.Allocator.Error![]const Self {
        var rows: std.ArrayList(Self) = try .initCapacity(allocator, lines.len);
        errdefer rows.deinit(allocator);
        for (lines) |line| {
            if (columns == 0 or mod.DiffLayout.columns(line.text) <= columns) {
                try rows.append(allocator, line);
                continue;
            }
            const text = try mod.DiffLayout.expandTabs(allocator, line.text);
            const steps = mod.TextLines.init(text);
            var start: usize = 0;
            var first = true;
            while (start < text.len) {
                var end = start;
                var cells: usize = 0;
                while (end < text.len and cells < columns) : (cells += 1) end = steps.nextCodepointEnd(end);
                try rows.append(allocator, if (first)
                    .{ .kind = line.kind, .text = text[start..end], .old = line.old, .new = line.new, .continued = line.continued }
                else
                    .{ .kind = line.kind, .text = text[start..end], .continued = true });
                first = false;
                start = end;
            }
        }
        return rows.toOwnedSlice(allocator);
    }

    /// How many cells of text fit in a row of a `DiffView` `width` points
    /// wide: the width less the bar, both line-number cells and the marker,
    /// in monospaced cells, less `DiffLayout.wrap_margin`. Callable while a
    /// frame is built: the cell is the bundled monospaced face's
    /// (`DiffLayout.cell_width`).
    ///
    /// - `digits`: the diff's widest line number's digits
    ///   (`DiffLayout.digitsOf`), counted once per diff rather than per
    ///   frame; a wrapped diff's are its lines' (continued rows have no
    ///   numbers).
    /// - `width`: the view's width (a `ScrollState`'s `viewport_width`).
    /// - Returns: the cells, at least 1; 0 when `width` is not yet known (0
    ///   or less) or not finite, which `wrap` takes as no wrapping.
    pub fn wrapColumns(digits: usize, width: f32) usize {
        if (!(width > 0) or !std.math.isFinite(width)) return 0;
        const room = width - mod.DiffLayout.textInset(digits) - mod.DiffLayout.wrap_margin;
        if (!(room >= mod.DiffLayout.cell_width)) return 1;
        return @intFromFloat(@floor(room / mod.DiffLayout.cell_width));
    }

    /// Where scroll offset `offset` over `rows` falls (the line at the top,
    /// how far into its text, how far into its row), for `offsetAt` to find
    /// in the same lines wrapped anew.
    ///
    /// - `rows`: the rows scrolled, wrapped or not.
    /// - `offset`: the scroll offset over them (a `ScrollState`'s `offset`).
    /// - Returns: the anchor; the first line's top when `rows` is empty or the
    ///   offset is not past 0.
    pub fn anchorAt(rows: []const Self, offset: f32) DiffAnchor {
        if (rows.len == 0 or !(offset > 0)) return .{};
        const rows_above = offset / diff_row_height;
        const last = rows.len - 1;
        const top: usize = if (rows_above >= @as(f32, @floatFromInt(last))) last else @intFromFloat(rows_above);
        var anchor: DiffAnchor = .{ .within = @min(offset - @as(f32, @floatFromInt(top)) * diff_row_height, diff_row_height) };
        var started = false;
        for (rows[0 .. top + 1], 0..) |row, at| {
            if (!row.continued) {
                if (started) anchor.line += 1;
                started = true;
                anchor.byte = 0;
            } else if (at > 0) anchor.byte += rows[at - 1].text.len;
        }
        return anchor;
    }

    /// The scroll offset over `rows` that puts `anchor` where it was: at its
    /// line's row holding the same text, as far into that row.
    ///
    /// - `rows`: the same lines as the anchor's, wrapped or not.
    /// - `anchor`: where the offset fell (`anchorAt`).
    /// - Returns: the offset; the last row's when `rows` holds fewer lines.
    pub fn offsetAt(rows: []const Self, anchor: DiffAnchor) f32 {
        if (rows.len == 0) return 0;
        var line: usize = 0;
        var started = false;
        const start = for (rows, 0..) |row, at| {
            if (row.continued) continue;
            if (started) line += 1;
            started = true;
            if (line == anchor.line) break at;
        } else return @as(f32, @floatFromInt(rows.len - 1)) * diff_row_height;
        var top = start;
        var consumed: usize = 0;
        while (top + 1 < rows.len and rows[top + 1].continued and consumed + rows[top].text.len <= anchor.byte) : (top += 1) {
            consumed += rows[top].text.len;
        }
        return @as(f32, @floatFromInt(top)) * diff_row_height + anchor.within;
    }

    /// Whether the row is a hunk's header, not one continued.
    ///
    /// - `self`: the row.
    /// - Returns: true when a hunk starts here.
    fn startsHunk(self: *const Self) bool {
        return self.kind == .hunkHeader and !self.continued;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "diff hunks are counted and located across files" {
    const lines = [_]DiffLine{
        .{ .kind = .fileHeader, .text = "a" },
        .{ .kind = .hunkHeader, .text = "@@ -1 +1 @@" },
        .{ .kind = .removed, .text = "x", .old = 1 },
        .{ .kind = .added, .text = "y", .new = 1 },
        .{ .kind = .fileHeader, .text = "b" },
        .{ .kind = .hunkHeader, .text = "@@ -3 +3 @@" },
        .{ .kind = .context, .text = "z", .old = 3, .new = 3 },
    };
    try std.testing.expectEqual(@as(usize, 2), DiffLine.hunkCount(&lines));
    try std.testing.expectEqual(@as(?usize, 5), DiffLine.hunkRow(&lines, 1));
    try std.testing.expectEqual(@as(?usize, null), DiffLine.hunkRow(&lines, 2));
    var scroll: mod.ScrollState = .{ .offset_x = 120 };
    DiffLine.revealHunk(&scroll, &lines, 1);
    try std.testing.expectEqual(5 * diff_row_height, scroll.offset);
    try std.testing.expectEqual(@as(f32, 0), scroll.offset_x);
}

test "wrapping splits long lines into continued rows and keeps short ones" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lines = [_]DiffLine{
        .{ .kind = .context, .text = "abcd", .old = 1, .new = 1 },
        .{ .kind = .added, .text = "abcdefghij", .new = 2 },
    };
    const rows = try DiffLine.wrap(allocator, &lines, 4);
    try std.testing.expectEqual(@as(usize, 4), rows.len);
    // Exactly the width: not wrapped.
    try std.testing.expectEqualStrings("abcd", rows[0].text);
    try std.testing.expect(!rows[0].continued);
    try std.testing.expectEqualStrings("abcd", rows[1].text);
    try std.testing.expectEqual(@as(?u32, 2), rows[1].new);
    try std.testing.expect(!rows[1].continued);
    try std.testing.expectEqualStrings("efgh", rows[2].text);
    try std.testing.expectEqualStrings("ij", rows[3].text);
    for (rows[2..]) |row| {
        try std.testing.expect(row.continued);
        try std.testing.expectEqual(DiffLineKind.added, row.kind);
        try std.testing.expectEqual(@as(?u32, null), row.new);
        try std.testing.expectEqual(@as(?u32, null), row.old);
    }
    // No width yet: a copy.
    const copied = try DiffLine.wrap(allocator, &lines, 0);
    try std.testing.expectEqual(lines.len, copied.len);
    try std.testing.expect(copied.ptr != &lines);
}

test "wrapping counts a tab as its spaces and never cuts a code point" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const tabbed = try DiffLine.wrap(allocator, &.{.{ .kind = .context, .text = "\tab", .old = 1, .new = 1 }}, 3);
    try std.testing.expectEqual(@as(usize, 2), tabbed.len);
    try std.testing.expectEqualStrings("   ", tabbed[0].text);
    try std.testing.expectEqualStrings(" ab", tabbed[1].text);

    const wide = try DiffLine.wrap(allocator, &.{.{ .kind = .added, .text = "é漢字ü", .new = 1 }}, 3);
    try std.testing.expectEqual(@as(usize, 2), wide.len);
    try std.testing.expectEqualStrings("é漢字", wide[0].text);
    try std.testing.expectEqualStrings("ü", wide[1].text);

    const invalid = try DiffLine.wrap(allocator, &.{.{ .kind = .removed, .text = "\xffab\xfe", .old = 1 }}, 2);
    try std.testing.expectEqual(@as(usize, 2), invalid.len);
    try std.testing.expectEqualStrings("\xffa", invalid[0].text);
    try std.testing.expectEqualStrings("b\xfe", invalid[1].text);

    // A bad byte is one cell; the code points around it are never cut.
    const mixed = try DiffLine.wrap(allocator, &.{.{ .kind = .added, .text = "漢\xff字字ü", .new = 1 }}, 2);
    try std.testing.expectEqual(@as(usize, 3), mixed.len);
    try std.testing.expectEqualStrings("漢\xff", mixed[0].text);
    try std.testing.expectEqualStrings("字字", mixed[1].text);
    try std.testing.expectEqualStrings("ü", mixed[2].text);
}

test "a wrapped diff keeps its hunks, header rows wrapping inside theirs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const lines = [_]DiffLine{
        .{ .kind = .fileHeader, .text = "src/a/very/long/path.zig" },
        .{ .kind = .hunkHeader, .text = "@@ -1,2 +1,2 @@ fn first() void {" },
        .{ .kind = .removed, .text = "a line long enough to wrap twice over", .old = 1 },
        .{ .kind = .added, .text = "y", .new = 1 },
        .{ .kind = .hunkHeader, .text = "@@ -9 +9 @@ fn second() void {" },
        .{ .kind = .note, .text = "\\ No newline at end of file" },
    };
    const rows = try DiffLine.wrap(arena.allocator(), &lines, 10);
    try std.testing.expect(rows.len > lines.len);
    try std.testing.expect(rows[1].kind == .fileHeader and rows[1].continued);
    try std.testing.expectEqual(DiffLine.hunkCount(&lines), DiffLine.hunkCount(rows));
    for (0..DiffLine.hunkCount(&lines)) |hunk| {
        const at = DiffLine.hunkRow(rows, hunk).?;
        try std.testing.expect(rows[at].kind == .hunkHeader and !rows[at].continued);
        try std.testing.expectEqualStrings(lines[DiffLine.hunkRow(&lines, hunk).?].text[0..10], rows[at].text);
    }
    var scroll: mod.ScrollState = .{ .offset_x = 40 };
    DiffLine.revealHunk(&scroll, rows, 1);
    try std.testing.expectEqual(@as(f32, @floatFromInt(DiffLine.hunkRow(rows, 1).?)) * diff_row_height, scroll.offset);
    try std.testing.expectEqual(@as(f32, 0), scroll.offset_x);
}

test "wrap columns grow with the width and shrink with the gutter" {
    try std.testing.expectEqual(@as(usize, 0), DiffLine.wrapColumns(1, 0));
    try std.testing.expectEqual(@as(usize, 0), DiffLine.wrapColumns(1, std.math.inf(f32)));
    try std.testing.expectEqual(@as(usize, 0), DiffLine.wrapColumns(1, std.math.nan(f32)));
    try std.testing.expectEqual(@as(usize, 1), DiffLine.wrapColumns(1, 10));
    try std.testing.expect(DiffLine.wrapColumns(1, 800) > DiffLine.wrapColumns(1, 400));
    try std.testing.expect(DiffLine.wrapColumns(5, 400) < DiffLine.wrapColumns(1, 400));
}

test "a scroll anchor finds the same text after the lines wrap anew" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const lines = [_]DiffLine{
        .{ .kind = .hunkHeader, .text = "@@" },
        .{ .kind = .added, .text = "xxxxxxxxxxxxxxxxxxxxxxxxx", .new = 1 },
        .{ .kind = .context, .text = "ab", .old = 1, .new = 2 },
        .{ .kind = .removed, .text = "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyy", .old = 2 },
    };
    const ten = try DiffLine.wrap(allocator, &lines, 10);
    const five = try DiffLine.wrap(allocator, &lines, 5);

    // The long line's second row, 3 points down: bytes 10 on of line 1.
    const anchor = DiffLine.anchorAt(ten, 2 * diff_row_height + 3);
    try std.testing.expectEqual(@as(usize, 1), anchor.line);
    try std.testing.expectEqual(@as(usize, 10), anchor.byte);
    try std.testing.expectEqual(@as(f32, 3), anchor.within);
    // Five cells a row: the third of the line's rows starts at byte 10.
    try std.testing.expectEqual(3 * diff_row_height + 3, DiffLine.offsetAt(five, anchor));
    // Unwrapped: the line's only row.
    try std.testing.expectEqual(diff_row_height + 3, DiffLine.offsetAt(&lines, anchor));
    // And back again.
    try std.testing.expectEqual(2 * diff_row_height + 3, DiffLine.offsetAt(ten, DiffLine.anchorAt(five, 3 * diff_row_height + 3)));

    // The last line, from unwrapped to wrapped: its first row.
    try std.testing.expectEqual(5 * diff_row_height, DiffLine.offsetAt(ten, DiffLine.anchorAt(&lines, 3 * diff_row_height)));
    // At the top, past the end, or over nothing.
    try std.testing.expectEqual(@as(f32, 0), DiffLine.offsetAt(five, DiffLine.anchorAt(ten, 0)));
    try std.testing.expectEqual(@as(usize, 3), DiffLine.anchorAt(ten, std.math.inf(f32)).line);
    try std.testing.expectEqual(@as(f32, @floatFromInt(five.len - 1)) * diff_row_height, DiffLine.offsetAt(five, .{ .line = 99 }));
    try std.testing.expectEqual(@as(f32, 0), DiffLine.offsetAt(&.{}, .{ .line = 1 }));
}
