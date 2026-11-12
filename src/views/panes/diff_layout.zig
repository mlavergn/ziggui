//! How a `DiffView` lays out a row: its text's size and cells, tabs, and the
//! gutter beside it, shared by the view and by `DiffLine.wrap`.

const std = @import("std");
const log = std.log.scoped(.ziggui_diff_layout);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The measures of a `DiffView` row, so the view and what wraps its lines
/// (`DiffLine.wrap`, `DiffLine.wrapColumns`) agree on how wide a line is.
pub const DiffLayout = struct {
    const Self = @This();

    /// The size of a diff's monospaced text.
    pub const font_size: f32 = 12;

    /// The size of the gutter's line numbers.
    pub const number_size: f32 = font_size - 1;

    /// One cell of the monospaced face (JetBrains Mono: 600 of 1000 units to
    /// the em, every glyph alike) at `font_size`, in points. A code point the
    /// face lacks draws from a fallback face and may be wider.
    pub const cell_width: f32 = 0.6 * font_size;

    /// Spaces a tab expands to.
    pub const tab: []const u8 = "    ";

    /// The width of the bar that marks the selected hunk.
    pub const bar_width: f32 = 3;

    /// The spacing between the bar and the row's body.
    pub const bar_spacing: f32 = 6;

    /// The spacing between the gutter's cells and the text.
    pub const cell_spacing: f32 = 4;

    /// The width of the `+`/`-` marker's cell.
    pub const marker_width: f32 = 12;

    /// Points kept free at a row's end, so a line wrapped to fit never needs
    /// a sideways scroll for a rounding.
    pub const wrap_margin: f32 = 4;

    /// The width of one line-number cell.
    ///
    /// - `digits`: the widest line number's digits.
    /// - Returns: the width, in points.
    pub fn gutterWidth(digits: usize) f32 {
        return @as(f32, @floatFromInt(digits)) * 7.5 + 6;
    }

    /// Where a numbered row's text starts: the bar, both line numbers and the
    /// marker, with the spacing between them.
    ///
    /// - `digits`: the widest line number's digits.
    /// - Returns: the inset, in points.
    pub fn textInset(digits: usize) f32 {
        return bar_width + bar_spacing + 2 * Self.gutterWidth(digits) + marker_width + 3 * cell_spacing;
    }

    /// The digits of the widest line number in `lines`.
    ///
    /// - `lines`: the diff.
    /// - Returns: the digit count, at least 1.
    pub fn digitsOf(lines: []const mod.DiffLine) usize {
        var widest: u32 = 0;
        for (lines) |line| widest = @max(widest, @max(line.old orelse 0, line.new orelse 0));
        return std.fmt.count("{d}", .{widest});
    }

    /// How many monospaced cells a line takes: its code points, a tab as
    /// `tab`'s spaces. A byte that does not decode is one cell, as the
    /// renderer draws it (`TextLines.nextCodepointEnd`), so valid text around
    /// it still counts by code point.
    ///
    /// - `line`: the line.
    /// - Returns: the cell count.
    pub fn columns(line: []const u8) usize {
        const steps = mod.TextLines.init(line);
        var cells: usize = 0;
        var at: usize = 0;
        while (at < line.len) : (at = steps.nextCodepointEnd(at)) {
            cells += if (line[at] == '\t') tab.len else 1;
        }
        return cells;
    }

    /// Text with each tab as spaces (the font has no glyph for a tab).
    ///
    /// - `allocator`: allocator for the expanded text.
    /// - `text`: the text.
    /// - Returns: the expanded text, or `text` itself when it has no tab;
    ///   propagates allocation failure.
    pub fn expandTabs(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
        if (std.mem.findScalar(u8, text, '\t') == null) return text;
        return std.mem.replaceOwned(u8, allocator, text, "\t", tab);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a diff row's measures: cells, tabs and the gutter" {
    try std.testing.expectEqual(@as(usize, 3), DiffLayout.columns("abc"));
    try std.testing.expectEqual(@as(usize, 6), DiffLayout.columns("\tab"));
    try std.testing.expectEqual(@as(usize, 2), DiffLayout.columns("é漢"));
    try std.testing.expectEqual(@as(usize, 2), DiffLayout.columns("\xff\xfe"));
    // One bad byte counts as one cell; the code points around it still count as one each.
    try std.testing.expectEqual(@as(usize, 7), DiffLayout.columns("漢\xff字\t"));
    const expanded = try DiffLayout.expandTabs(std.testing.allocator, "a\tb");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("a    b", expanded);
    try std.testing.expect(DiffLayout.textInset(4) > DiffLayout.textInset(1));
    const lines = [_]mod.DiffLine{ .{ .kind = .added, .text = "x", .new = 1234 }, .{ .kind = .removed, .text = "y", .old = 7 } };
    try std.testing.expectEqual(@as(usize, 4), DiffLayout.digitsOf(&lines));
    try std.testing.expectEqual(@as(usize, 1), DiffLayout.digitsOf(&.{}));
}

test "a diff cell is the monospaced face's advance at the diff's size" {
    const fonts = try renderer.FontSet.create(std.testing.allocator);
    defer fonts.destroy();
    const shaper = renderer.TextShaper.init(fonts.cache(.{ .mono = true }).face);
    for ([_][]const u8{ "x", "W", "m", "@", "-" }) |glyph| {
        try std.testing.expectApproxEqAbs(DiffLayout.cell_width, shaper.measureLineWidth(glyph, DiffLayout.font_size), 0.001);
    }
}
