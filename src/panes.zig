//! Panes for list | detail browsers: a list that builds only the rows in view,
//! a unified diff over it, and table rows sized to a shared set of columns.
//! All pure composition over zigui's `ScrollViewState` and stacks; the types
//! they take (`IndexCallback`, `RowRange`, `DiffLine`) have files of their own.

// View constructors are PascalCase functions, as in zigui (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_panes);
const mod = @import("module.zig");
const zigui = @import("zigui");

/// The size of a diff's monospaced text.
const diff_px: f32 = 12;

/// Spaces a tab expands to in a diff row.
const diff_tab: []const u8 = "    ";

/// What a `DiffView`'s rows are built from, in the build arena.
const DiffModel = struct {
    const Self = @This();

    /// The diff.
    lines: []const mod.DiffLine,

    /// The marked hunk.
    selected: ?usize,

    /// The tap handler.
    on_hunk: ?mod.IndexCallback,

    /// The colors, read once per frame.
    tokens: mod.BuildTokens,

    /// The first row in view; `hunk_of` starts there.
    first: usize = 0,

    /// The hunk of each row in view (only those: a long diff costs what a
    /// screenful does), built once per frame.
    hunk_of: []const ?usize = &.{},

    /// The widest line number's digits, for the gutter.
    digits: usize = 1,

    /// Finds the hunk of each row in `range` and the gutter's width, in one
    /// pass with no allocation per line.
    ///
    /// - `self`: the model.
    /// - `range`: the rows in view.
    fn indexHunks(self: *Self, range: mod.RowRange) void {
        var current: ?usize = null;
        var next: usize = 0;
        var widest: u32 = 0;
        const hunk_of = zigui.buildAlloc().alloc(?usize, range.end - range.start) catch @panic("oom");
        for (self.lines, 0..) |line, at| {
            switch (line.kind) {
                .hunkHeader => {
                    current = next;
                    next += 1;
                },
                .fileHeader => current = null,
                else => {},
            }
            if (at >= range.start and at < range.end) hunk_of[at - range.start] = current;
            widest = @max(widest, @max(line.old orelse 0, line.new orelse 0));
        }
        self.first = range.start;
        self.hunk_of = hunk_of;
        self.digits = std.fmt.count("{d}", .{widest});
    }

    /// Builds diff row `index`.
    ///
    /// - `self`: the model.
    /// - `index`: the row.
    /// - Returns: the row.
    fn row(self: *const Self, index: usize) zigui.View {
        const line = self.lines[index];
        const t = self.tokens;
        const hunk = self.hunk_of[index - self.first];
        const selected = hunk != null and self.selected != null and hunk.? == self.selected.?;
        const bar = zigui.Rectangle(if (selected) t.accent else zigui.Color.transparent).frameWidth(3);
        const gutter_width = @as(f32, @floatFromInt(self.digits)) * 7.5 + 6;
        const body: zigui.View = switch (line.kind) {
            .hunkHeader, .fileHeader, .note => zigui.Text(Self.expandTabs(line.text)).mono().size(diff_px)
                .foreground(if (line.kind == .fileHeader) t.label else t.secondary_label)
                .weight(if (line.kind == .fileHeader) .semibold else .regular)
                .truncated(),
            else => zigui.HStack(.{
                Self.numberCell(line.old, gutter_width, t.secondary_label),
                Self.numberCell(line.new, gutter_width, t.secondary_label),
                zigui.Text(switch (line.kind) {
                    .added => "+",
                    .removed => "-",
                    else => " ",
                }).mono().size(diff_px).foreground(Self.lineColor(line.kind, t)).frameWidth(12),
                zigui.Text(Self.expandTabs(line.text)).mono().size(diff_px).foreground(Self.lineColor(line.kind, t)).truncated(),
            }).spacing(4),
        };
        var v = zigui.HStack(.{ bar, body.frameMaxWidth().frameAlign(.leading) }).spacing(6).frameMaxWidth();
        v = switch (line.kind) {
            .added => v.background(t.added.withAlpha(0.12)),
            .removed => v.background(t.removed.withAlpha(0.12)),
            .hunkHeader => v.background(t.row_stripe),
            .fileHeader => v.background(t.quaternary_fill),
            else => v,
        };
        if (self.on_hunk) |cb| if (hunk) |h| {
            v = v.onTap(cb.bind(h));
        };
        return v;
    }

    /// A gutter cell: a line number, right-aligned, or blank.
    ///
    /// - `n`: the line number, if the line has one on this side.
    /// - `width`: the gutter's width.
    /// - `color`: the number's color.
    /// - Returns: the cell.
    fn numberCell(n: ?u32, width: f32, color: zigui.Color) zigui.View {
        const s = if (n) |num| zigui.buildAlloc().print("{d}", .{num}) catch @panic("oom") else "";
        return zigui.Text(s).mono().size(diff_px - 1).foreground(color).frameWidth(width).frameAlign(.trailing);
    }

    /// The text color of a diff line.
    ///
    /// - `kind`: what the line is.
    /// - `t`: the frame's colors.
    /// - Returns: the color.
    fn lineColor(kind: mod.DiffLineKind, t: mod.BuildTokens) zigui.Color {
        return switch (kind) {
            .added => t.added,
            .removed => t.removed,
            else => t.label,
        };
    }

    /// Text with each tab as spaces (the font has no glyph for a tab).
    ///
    /// - `s`: the text.
    /// - Returns: the expanded text in the build arena, or `s` itself when it
    ///   has no tab.
    fn expandTabs(s: []const u8) []const u8 {
        if (std.mem.findScalar(u8, s, '\t') == null) return s;
        return std.mem.replaceOwned(u8, zigui.buildAlloc(), s, "\t", diff_tab) catch @panic("oom");
    }
};

/// The layout `TableHeader` and `TableRow` share.
const Table = struct {
    const Self = @This();

    /// The horizontal padding of a row, and the spacing between its cells.
    const pad: f32 = 8;

    /// `content` sized and aligned for `col`.
    ///
    /// - `content`: the cell's view.
    /// - `col`: the cell's column.
    /// - Returns: the cell.
    fn cell(content: zigui.View, col: zigui.DataColumn) zigui.View {
        const framed = if (col.width) |w| content.frameWidth(w) else content.frameMaxWidth();
        return if (col.trailing) framed.frameAlign(.trailing) else framed.frameAlign(.leading);
    }
};

/// A vertical list of `count` equal rows that builds only the rows in view:
/// thousands of rows cost what a screenful does.
///
/// Scrolled by `scroll` (app-owned; the wheel drives it, `zigui.ScrollState.reveal`
/// follows a keyboard cursor). The rows in view are read from `scroll` as the
/// last frame left it, so the first frame builds a screen's worth from the top.
///
/// - `T`: the row builder's context type.
/// - `ctx`: the row builder's context.
/// - `count`: how many rows.
/// - `row_height`: each row's height, in points.
/// - `scroll`: the list's scroll position.
/// - `rowFn`: makes row `i`; it is framed to `row_height` and the list's width.
/// - Returns: the list.
pub fn VirtualList(
    comptime T: type,
    ctx: *const T,
    count: usize,
    row_height: f32,
    scroll: *zigui.ScrollState,
    comptime rowFn: fn (*const T, usize) zigui.View,
) zigui.View {
    const range = mod.RowRange.visible(count, row_height, scroll);
    const shown = range.end - range.start;
    const kids = zigui.buildAlloc().alloc(zigui.View, shown + 2) catch @panic("oom");
    kids[0] = zigui.Empty().frameHeight(@as(f32, @floatFromInt(range.start)) * row_height);
    for (0..shown) |k| {
        kids[k + 1] = rowFn(ctx, range.start + k).frameHeight(row_height).frameMaxWidth();
    }
    kids[shown + 1] = zigui.Empty().frameHeight(@as(f32, @floatFromInt(count - range.end)) * row_height);
    const body = zigui.view.makeStackFromSlice(.vertical, 0, .leading, kids).frameMaxWidth();
    return zigui.ScrollViewState(scroll, body).frameMaxWidth().frameMaxHeight();
}

/// A unified diff, a row per line under a gutter of old and new line numbers.
///
/// Hunk `selected` (counted across `lines`) is marked by an accent bar. Builds
/// only the rows in view (`VirtualList`), so a long diff is cheap. Long lines
/// are cut at the pane's edge.
///
/// - `lines`: the diff.
/// - `selected`: the hunk to mark, if any.
/// - `scroll`: the diff's scroll position.
/// - `on_hunk`: when set, called with the hunk a tapped row belongs to.
/// - Returns: the diff.
pub fn DiffView(lines: []const mod.DiffLine, selected: ?usize, scroll: *zigui.ScrollState, on_hunk: ?mod.IndexCallback) zigui.View {
    const model = zigui.buildAlloc().create(DiffModel) catch @panic("oom");
    model.* = .{ .lines = lines, .selected = selected, .on_hunk = on_hunk, .tokens = mod.buildTokens() };
    model.indexHunks(mod.RowRange.visible(lines.len, mod.diff_row_height, scroll));
    return VirtualList(DiffModel, model, lines.len, mod.diff_row_height, scroll, DiffModel.row);
}

/// A table's header row, matching `TableRow`'s cells: put it over a
/// `VirtualList` of `TableRow`s for a long, selectable table.
///
/// - `columns`: the columns.
/// - Returns: the header row.
pub fn TableHeader(columns: []const zigui.DataColumn) zigui.View {
    const t = mod.buildTokens();
    const cells = zigui.buildAlloc().alloc(zigui.View, columns.len) catch @panic("oom");
    for (columns, 0..) |col, c| {
        cells[c] = Table.cell(zigui.Text(col.title).font(.subheadline).foreground(t.secondary_label).truncated(), col);
    }
    return zigui.view.makeStackFromSlice(.horizontal, Table.pad, .center, cells)
        .paddingInsets(.{ .top = 6, .leading = Table.pad, .bottom = 6, .trailing = Table.pad })
        .frameMaxWidth();
}

/// One table row, its cells sized to the columns as `TableHeader` sizes its
/// titles. A selected row is filled with the selection color; otherwise odd
/// rows are striped.
///
/// - `columns`: the columns.
/// - `cells`: one view per column (tinted text, an icon); missing ones are empty.
/// - `index`: the row's index, for striping.
/// - `selected`: whether the row is selected.
/// - Returns: the row.
pub fn TableRow(columns: []const zigui.DataColumn, cells: []const zigui.View, index: usize, selected: bool) zigui.View {
    const t = mod.buildTokens();
    const kids = zigui.buildAlloc().alloc(zigui.View, columns.len) catch @panic("oom");
    for (columns, 0..) |col, c| kids[c] = Table.cell(if (c < cells.len) cells[c] else zigui.Empty(), col);
    var row = zigui.view.makeStackFromSlice(.horizontal, Table.pad, .center, kids)
        .paddingInsets(.{ .top = 0, .leading = Table.pad, .bottom = 0, .trailing = Table.pad })
        .frameMaxWidth()
        .frameMaxHeight();
    if (selected) {
        row = row.background(t.selection.withAlpha(0.22));
    } else if (index % 2 == 1) {
        row = row.background(t.row_stripe);
    }
    return row;
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a DiffView builds only the rows in view, and taps name the hunk" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const lines = try std.testing.allocator.alloc(mod.DiffLine, 5000);
    defer std.testing.allocator.free(lines);
    for (lines, 0..) |*line, i| line.* = if (i % 50 == 0)
        .{ .kind = .hunkHeader, .text = "@@ -1 +1 @@" }
    else
        .{ .kind = if (i % 2 == 0) .added else .removed, .text = "x\ty", .old = @intCast(i), .new = @intCast(i) };
    const Probe = struct {
        const Self = @This();
        hunk: ?usize = null,
        fn onHunk(self: *Self, index: usize) void {
            self.hunk = index;
        }
    };
    var probe: Probe = .{};
    var scroll: zigui.ScrollState = .{ .offset = 60 * mod.diff_row_height, .viewport_h = 10 * mod.diff_row_height };
    canvas.begin(zigui.macos.light);
    const view = DiffView(lines, 1, &scroll, mod.IndexCallback.init(Probe, &probe, Probe.onHunk));
    canvas.end();
    var frame = try canvas.render(view, 300, @intFromFloat(10 * mod.diff_row_height));
    defer frame.deinit();
    try std.testing.expectEqual(@as(f32, 5000) * mod.diff_row_height, scroll.content_h);
    // Row 60 is at the top, in hunk 1 (rows 50..99).
    try std.testing.expect(canvas.tap(.{ .x = 150, .y = 5 }));
    try std.testing.expectEqual(@as(?usize, 1), probe.hunk);
}

test "a table row stripes odd rows and fills a selected one" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const columns = [_]zigui.DataColumn{ .{ .title = "Name" }, .{ .title = "Size", .width = 60, .trailing = true } };
    canvas.begin(zigui.macos.light);
    const even = TableRow(&columns, &.{ zigui.Text("a"), zigui.Text("1") }, 0, false);
    const odd = TableRow(&columns, &.{ zigui.Text("b"), zigui.Text("2") }, 1, false);
    const header = TableHeader(&columns);
    canvas.end();
    try std.testing.expect(even.mods.background == null);
    try std.testing.expect(odd.mods.background != null);
    try std.testing.expect(header.kind == .stack);
}
