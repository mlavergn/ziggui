//! Panes for list | detail browsers: a list that builds only the rows in view
//! (scrolling sideways too, for rows wider than the pane), a unified diff over
//! it (its lines run on, or wrap when the caller wraps them), and table rows
//! sized to a shared set of columns.
//! All pure composition over ziggui's `ScrollViewState` and stacks; the types
//! they take (`IndexCallback`, `RowRange`, `DiffLine`) have files of their own.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_panes);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A hunk or file header's row, where the hunk the rows below belong to changes.
const DiffMark = struct {
    const Self = @This();

    /// The header's row.
    row: usize,

    /// The hunk it starts; null for a file header, whose rows belong to none.
    hunk: ?usize,

    /// Whether `mark` lies at or before `row`, for a binary search.
    ///
    /// - `row`: the row looked up.
    /// - `mark`: a mark.
    /// - Returns: true when the mark's row is at most `row`.
    fn startsBy(row: usize, mark: Self) bool {
        return mark.row <= row;
    }
};

/// What a `DiffView` learns from its whole diff (the gutter's digits, the
/// widest row, where hunks start), kept between frames for the diff shown
/// last: a frame then costs what its rows in view do, not the whole diff.
/// One per thread, as `BuildScope` is.
const DiffIndex = struct {
    const Self = @This();

    /// The diff indexed: a hash of all its lines (see `keyFor`).
    key: u64 = 0,

    /// Whether `key` names an indexed diff.
    indexed: bool = false,

    /// The widest line number's digits, for the gutter.
    digits: usize = 1,

    /// The row with the longest text (tabs expanded).
    widest: usize = 0,

    /// Every hunk and file header, in row order.
    marks: std.ArrayList(DiffMark) = .empty,

    /// The current thread's index.
    threadlocal var shared_index: Self = .{};

    /// The current thread's index.
    ///
    /// - Returns: the shared index.
    fn shared() *Self {
        return &shared_index;
    }

    /// Indexes `lines` in one pass with no allocation per line, unless it is
    /// the diff indexed last.
    ///
    /// - `self`: the index.
    /// - `lines`: the diff.
    fn update(self: *Self, lines: []const mod.DiffLine) void {
        const key = Self.keyFor(lines);
        if (self.indexed and self.key == key) return;
        self.marks.clearRetainingCapacity();
        var next: usize = 0;
        var widest: u32 = 0;
        var longest: usize = 0;
        self.widest = 0;
        for (lines, 0..) |line, at| {
            if (!line.continued) switch (line.kind) {
                .hunkHeader => {
                    self.marks.append(std.heap.page_allocator, .{ .row = at, .hunk = next }) catch @panic("oom");
                    next += 1;
                },
                .fileHeader => self.marks.append(std.heap.page_allocator, .{ .row = at, .hunk = null }) catch @panic("oom"),
                else => {},
            };
            widest = @max(widest, @max(line.old orelse 0, line.new orelse 0));
            const cells = mod.DiffLayout.columns(line.text);
            if (cells > longest) {
                longest = cells;
                self.widest = at;
            }
        }
        self.digits = std.fmt.count("{d}", .{widest});
        self.key = key;
        self.indexed = true;
    }

    /// The hunk of each row in `range`, in the build arena.
    ///
    /// - `self`: the index, updated for the diff.
    /// - `range`: the rows in view.
    /// - Returns: one hunk (or null) per row.
    fn hunks(self: *const Self, range: mod.RowRange) []const ?usize {
        const hunk_of = mod.BuildScope.shared().allocator().alloc(?usize, range.end - range.start) catch @panic("oom");
        const marks = self.marks.items;
        // The marks at or before the first row; the last of them holds.
        var after = std.sort.partitionPoint(DiffMark, marks, range.start, DiffMark.startsBy);
        var current: ?usize = if (after > 0) marks[after - 1].hunk else null;
        for (hunk_of, range.start..) |*hunk, row| {
            while (after < marks.len and marks[after].row <= row) : (after += 1) current = marks[after].hunk;
            hunk.* = current;
        }
        return hunk_of;
    }

    /// What tells one diff from another: every line's kind, numbers, text
    /// and whether it is continued. Hashing is several times cheaper than
    /// the pass it saves, and a diff rebuilt at the same address (an arena
    /// reused) is still told apart.
    ///
    /// - `lines`: the diff.
    /// - Returns: the key.
    fn keyFor(lines: []const mod.DiffLine) u64 {
        var hasher = std.hash.Wyhash.init(0xd1ff);
        hasher.update(std.mem.asBytes(&lines.len));
        for (lines) |line| {
            const fields = [_]usize{ @backingInt(line.kind), if (line.old) |old| @as(usize, old) + 1 else 0, if (line.new) |new| @as(usize, new) + 1 else 0, @intFromPtr(line.text.ptr), line.text.len, @intFromBool(line.continued) };
            hasher.update(std.mem.asBytes(&fields));
            hasher.update(line.text);
        }
        return hasher.final();
    }
};

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

    /// The row with the longest text (tabs expanded), which sets how far the
    /// diff scrolls sideways.
    widest: usize = 0,

    /// Finds the hunk of each row in `range`, the gutter's width and the
    /// widest row: the whole diff is read once (`DiffIndex`), each frame
    /// only its rows in view.
    ///
    /// - `self`: the model.
    /// - `range`: the rows in view.
    fn indexHunks(self: *Self, range: mod.RowRange) void {
        const index = DiffIndex.shared();
        index.update(self.lines);
        self.first = range.start;
        self.hunk_of = index.hunks(range);
        self.digits = index.digits;
        self.widest = index.widest;
    }

    /// Builds diff row `index`.
    ///
    /// - `self`: the model.
    /// - `index`: the row.
    /// - Returns: the row.
    fn row(self: *const Self, index: usize) mod.View {
        const line = self.lines[index];
        const tokens = self.tokens;
        // Only the rows in view have a hunk recorded; the widest row, built
        // to size the list, may lie outside them.
        const hunk = if (index >= self.first and index - self.first < self.hunk_of.len) self.hunk_of[index - self.first] else null;
        const selected = hunk != null and self.selected != null and hunk.? == self.selected.?;
        const bar = mod.Rectangle(if (selected) tokens.accent else renderer.Color.transparent).frameWidth(mod.DiffLayout.bar_width);
        const gutter_width = mod.DiffLayout.gutterWidth(self.digits);
        const body: mod.View = switch (line.kind) {
            .hunkHeader, .fileHeader, .note => mod.Text(Self.expandTabs(line.text)).mono().size(mod.DiffLayout.font_size)
                .foreground(if (line.kind == .fileHeader) tokens.label else tokens.secondary_label)
                .weight(if (line.kind == .fileHeader) .semibold else .regular),
            else => mod.HStack(.{
                Self.numberCell(line.old, gutter_width, tokens.secondary_label),
                Self.numberCell(line.new, gutter_width, tokens.secondary_label),
                // A continued row has no marker: it is the line above, wrapped.
                mod.Text(if (line.continued) " " else switch (line.kind) {
                    .added => "+",
                    .removed => "-",
                    else => " ",
                }).mono().size(mod.DiffLayout.font_size).foreground(Self.lineColor(line.kind, tokens)).frameWidth(mod.DiffLayout.marker_width),
                mod.Text(Self.expandTabs(line.text)).mono().size(mod.DiffLayout.font_size).foreground(Self.lineColor(line.kind, tokens)),
            }).spacing(mod.DiffLayout.cell_spacing),
        };
        var row_view = mod.HStack(.{ bar, body.frameMaxWidth().frameAlign(.leading) }).spacing(mod.DiffLayout.bar_spacing).frameMaxWidth();
        row_view = switch (line.kind) {
            .added => row_view.background(tokens.added.withAlpha(0.12)),
            .removed => row_view.background(tokens.removed.withAlpha(0.12)),
            .hunkHeader => row_view.background(tokens.row_stripe),
            .fileHeader => row_view.background(tokens.quaternary_fill),
            else => row_view,
        };
        if (self.on_hunk) |callback| if (hunk) |hunk_index| {
            row_view = row_view.onTap(callback.bind(hunk_index));
        };
        return row_view;
    }

    /// A gutter cell: a line number, right-aligned, or blank.
    ///
    /// - `line_number`: the line number, if the line has one on this side.
    /// - `width`: the gutter's width.
    /// - `color`: the number's color.
    /// - Returns: the cell.
    fn numberCell(line_number: ?u32, width: f32, color: renderer.Color) mod.View {
        const text = if (line_number) |number| mod.BuildScope.shared().allocator().print("{d}", .{number}) catch @panic("oom") else "";
        return mod.Text(text).mono().size(mod.DiffLayout.number_size).foreground(color).frameWidth(width).frameAlign(.trailing);
    }

    /// The text color of a diff line.
    ///
    /// - `kind`: what the line is.
    /// - `tokens`: the frame's colors.
    /// - Returns: the color.
    fn lineColor(kind: mod.DiffLineKind, tokens: mod.BuildTokens) renderer.Color {
        return switch (kind) {
            .added => tokens.added,
            .removed => tokens.removed,
            else => tokens.label,
        };
    }

    /// Text with each tab as spaces (`DiffLayout.expandTabs`), in the build arena.
    ///
    /// - `text`: the text.
    /// - Returns: the expanded text, or `text` itself when it has no tab.
    fn expandTabs(text: []const u8) []const u8 {
        return mod.DiffLayout.expandTabs(mod.BuildScope.shared().allocator(), text) catch @panic("oom");
    }
};

/// The stack a `VirtualList` scrolls: the rows in view between two spacers.
const ListBody = struct {
    const Self = @This();

    /// The rows in view, a spacer for those above and one for those below,
    /// and, when `sizer` names a row, that row again at zero height (clipped,
    /// so it draws nothing) to set the stack's width.
    ///
    /// - `T`: the row builder's context type.
    /// - `context`: the row builder's context.
    /// - `count`: how many rows.
    /// - `row_height`: each row's height, in points.
    /// - `scroll`: the list's scroll position.
    /// - `rowFn`: makes row `i`.
    /// - `sizer`: the row that sets the width, if any.
    /// - Returns: the stack.
    fn build(
        comptime T: type,
        context: *const T,
        count: usize,
        row_height: f32,
        scroll: *mod.ScrollState,
        comptime rowFn: fn (*const T, usize) mod.View,
        sizer: ?usize,
    ) mod.View {
        const range = mod.RowRange.visible(count, row_height, scroll);
        const shown = range.end - range.start;
        const extra: usize = if (sizer != null) 1 else 0;
        const children = mod.BuildScope.shared().allocator().alloc(mod.View, shown + 2 + extra) catch @panic("oom");
        if (sizer) |at| children[0] = rowFn(context, at).frameHeight(0).clipped();
        children[extra] = mod.Empty().frameHeight(@as(f32, @floatFromInt(range.start)) * row_height);
        for (0..shown) |offset| {
            children[extra + offset + 1] = rowFn(context, range.start + offset).frameHeight(row_height).frameMaxWidth();
        }
        children[extra + shown + 1] = mod.Empty().frameHeight(@as(f32, @floatFromInt(count - range.end)) * row_height);
        return mod.StackBuilder.fromSlice(.vertical, 0, .leading, children).frameMaxWidth();
    }
};

/// The layout `TableHeader` and `TableRow` share.
const Table = struct {
    const Self = @This();

    /// The horizontal padding of a row, and the spacing between its cells.
    const pad: f32 = 8;

    /// `content` sized and aligned for `column`.
    ///
    /// - `content`: the cell's view.
    /// - `column`: the cell's column.
    /// - Returns: the cell.
    fn cell(content: mod.View, column: mod.DataColumn) mod.View {
        const framed = if (column.width) |width| content.frameWidth(width) else content.frameMaxWidth();
        return if (column.trailing) framed.frameAlign(.trailing) else framed.frameAlign(.leading);
    }
};

/// A vertical list of `count` equal rows that builds only the rows in view:
/// thousands of rows cost what a screenful does.
///
/// Scrolled by `scroll` (app-owned; the wheel drives it, `mod.ScrollState.reveal`
/// follows a keyboard cursor). The rows in view are read from `scroll` as the
/// last frame left it, so the first frame builds a screen's worth from the top.
///
/// - `T`: the row builder's context type.
/// - `context`: the row builder's context.
/// - `count`: how many rows.
/// - `row_height`: each row's height, in points.
/// - `scroll`: the list's scroll position.
/// - `rowFn`: makes row `i`; it is framed to `row_height` and the list's width.
/// - Returns: the list.
pub fn VirtualList(
    comptime T: type,
    context: *const T,
    count: usize,
    row_height: f32,
    scroll: *mod.ScrollState,
    comptime rowFn: fn (*const T, usize) mod.View,
) mod.View {
    const body = ListBody.build(T, context, count, row_height, scroll, rowFn, null);
    return mod.ScrollViewState(scroll, body).frameMaxWidth().frameMaxHeight();
}

/// A `VirtualList` that also scrolls sideways (ziggui's `ScrollViewStateBoth`):
/// rows are laid out as wide as row `widest`, so a row wider than the pane
/// runs on instead of being cut, and the pane scrolls across to it.
///
/// Only the rows in view are built, so the caller names the widest row (by
/// its text's length, say); it is built once more at zero height to set the
/// width, so the sideways extent stays put as the list scrolls down. Rows
/// that fill their width (`.frameMaxWidth()`) fill the wider of the pane and
/// that row.
///
/// - `T`: the row builder's context type.
/// - `context`: the row builder's context.
/// - `count`: how many rows.
/// - `row_height`: each row's height, in points.
/// - `scroll`: the list's scroll position, both ways.
/// - `rowFn`: makes row `i`; it is framed to `row_height` and the list's width.
/// - `widest`: the row that sets the width; null leaves it to the rows in view.
/// - Returns: the list.
pub fn VirtualListBoth(
    comptime T: type,
    context: *const T,
    count: usize,
    row_height: f32,
    scroll: *mod.ScrollState,
    comptime rowFn: fn (*const T, usize) mod.View,
    widest: ?usize,
) mod.View {
    const sizer = if (widest) |at| (if (at < count) at else null) else null;
    const body = ListBody.build(T, context, count, row_height, scroll, rowFn, sizer);
    return mod.ScrollViewStateBoth(scroll, body).frameMaxWidth().frameMaxHeight();
}

/// A unified diff, a row per line under a gutter of old and new line numbers.
///
/// Hunk `selected` (counted across `lines`) is marked by an accent bar. Builds
/// only the rows in view (`VirtualListBoth`), so a long diff is cheap. A line
/// wider than the pane runs on and the diff scrolls sideways to it, the gutter
/// with it; set `scroll.offset_x` to 0 to show a new diff from its left edge.
/// To wrap instead, pass `DiffLine.wrap(arena, lines, DiffLine.wrapColumns(digits,
/// scroll.viewport_width))`, `digits` being `DiffLayout.digitsOf(lines)`: its
/// continued rows draw with no line numbers or marker, and keep their line's
/// hunk. Both read the whole diff, so keep the wrapped rows until the diff or
/// the column count changes, never wrap per frame; when they change, carry
/// `scroll.offset` over with `DiffLine.anchorAt` (old rows) and
/// `DiffLine.offsetAt` (new rows), or the rows above it move it to other text.
///
/// The pass over the whole diff (the gutter's width, the widest line, where
/// hunks start) is kept between frames for the diff shown last, known by a
/// hash of all its lines, so a changed diff is read afresh however it changed.
///
/// - `lines`: the diff.
/// - `selected`: the hunk to mark, if any.
/// - `scroll`: the diff's scroll position, both ways.
/// - `on_hunk`: when set, called with the hunk a tapped row belongs to.
/// - Returns: the diff.
pub fn DiffView(lines: []const mod.DiffLine, selected: ?usize, scroll: *mod.ScrollState, on_hunk: ?mod.IndexCallback) mod.View {
    const model = mod.BuildScope.shared().allocator().create(DiffModel) catch @panic("oom");
    model.* = .{ .lines = lines, .selected = selected, .on_hunk = on_hunk, .tokens = mod.BuildScope.shared().tokens() };
    model.indexHunks(mod.RowRange.visible(lines.len, mod.diff_row_height, scroll));
    return VirtualListBoth(DiffModel, model, lines.len, mod.diff_row_height, scroll, DiffModel.row, if (lines.len > 0) model.widest else null);
}

/// A table's header row, matching `TableRow`'s cells: put it over a
/// `VirtualList` of `TableRow`s for a long, selectable table.
///
/// - `columns`: the columns.
/// - Returns: the header row.
pub fn TableHeader(columns: []const mod.DataColumn) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const cells = mod.BuildScope.shared().allocator().alloc(mod.View, columns.len) catch @panic("oom");
    for (columns, 0..) |column, column_index| {
        cells[column_index] = Table.cell(mod.Text(column.title).font(.subheadline).foreground(tokens.secondary_label).truncated(), column);
    }
    return mod.StackBuilder.fromSlice(.horizontal, Table.pad, .center, cells)
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
pub fn TableRow(columns: []const mod.DataColumn, cells: []const mod.View, index: usize, selected: bool) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const children = mod.BuildScope.shared().allocator().alloc(mod.View, columns.len) catch @panic("oom");
    for (columns, 0..) |column, column_index| children[column_index] = Table.cell(if (column_index < cells.len) cells[column_index] else mod.Empty(), column);
    var row = mod.StackBuilder.fromSlice(.horizontal, Table.pad, .center, children)
        .paddingInsets(.{ .top = 0, .leading = Table.pad, .bottom = 0, .trailing = Table.pad })
        .frameMaxWidth()
        .frameMaxHeight();
    if (selected) {
        row = row.background(tokens.selection.withAlpha(0.22));
    } else if (index % 2 == 1) {
        row = row.background(tokens.row_stripe);
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
    for (lines, 0..) |*line, index| line.* = if (index % 50 == 0)
        .{ .kind = .hunkHeader, .text = "@@ -1 +1 @@" }
    else
        .{ .kind = if (index % 2 == 0) .added else .removed, .text = "x\ty", .old = @intCast(index), .new = @intCast(index) };
    const Probe = struct {
        const Self = @This();
        hunk: ?usize = null,
        fn onHunk(self: *Self, index: usize) void {
            self.hunk = index;
        }
    };
    var probe: Probe = .{};
    var scroll: mod.ScrollState = .{ .offset = 60 * mod.diff_row_height, .viewport_height = 10 * mod.diff_row_height };
    canvas.begin(renderer.MacosTheme.light);
    const view = DiffView(lines, 1, &scroll, mod.IndexCallback.init(Probe, &probe, Probe.onHunk));
    canvas.end();
    var frame = try canvas.render(view, 300, @intFromFloat(10 * mod.diff_row_height));
    defer frame.deinit();
    try std.testing.expectEqual(@as(f32, 5000) * mod.diff_row_height, scroll.content_height);
    // Row 60 is at the top, in hunk 1 (rows 50..99).
    try std.testing.expect(canvas.tap(.{ .x = 150, .y = 5 }));
    try std.testing.expectEqual(@as(?usize, 1), probe.hunk);
}

test "a DiffView runs long lines on and scrolls sideways as far as the widest" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const long: [400]u8 = @splat('x');
    var lines: [200]mod.DiffLine = undefined;
    for (&lines, 0..) |*line, index| line.* = .{ .kind = .context, .text = if (index == 150) &long else "x", .old = @intCast(index), .new = @intCast(index) };
    var scroll: mod.ScrollState = .{ .viewport_height = 10 * mod.diff_row_height };
    const height: u32 = @intFromFloat(10 * mod.diff_row_height);

    // The long line is far below the rows in view, yet it sets the width.
    canvas.begin(renderer.MacosTheme.light);
    var view = DiffView(&lines, null, &scroll, null);
    canvas.end();
    var first = try canvas.render(view, 300, height);
    first.deinit();
    try std.testing.expect(scroll.content_width > 1000);
    try std.testing.expectEqual(@as(f32, 300), scroll.viewport_width);

    // Scrolled past the end, it clamps to the long line's end.
    scroll.offset_x = 1_000_000;
    canvas.begin(renderer.MacosTheme.light);
    view = DiffView(&lines, null, &scroll, null);
    canvas.end();
    var second = try canvas.render(view, 300, height);
    second.deinit();
    try std.testing.expectEqual(scroll.content_width - 300, scroll.offset_x);

    // Short lines only: nothing to scroll across.
    var short: [3]mod.DiffLine = .{
        .{ .kind = .context, .text = "a", .old = 1, .new = 1 },
        .{ .kind = .added, .text = "b", .new = 2 },
        .{ .kind = .removed, .text = "c", .old = 2 },
    };
    var fits: mod.ScrollState = .{};
    canvas.begin(renderer.MacosTheme.light);
    view = DiffView(&short, null, &fits, null);
    canvas.end();
    var third = try canvas.render(view, 300, height);
    third.deinit();
    try std.testing.expectEqual(@as(f32, 0), fits.maxOffsetX());
}

test "a DiffView over lines wrapped to its width has nothing to scroll across" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const long: [400]u8 = @splat('x');
    const lines = [_]mod.DiffLine{
        .{ .kind = .hunkHeader, .text = "@@ -1200,2 +1200,2 @@" },
        .{ .kind = .removed, .text = &long, .old = 1234 },
        .{ .kind = .added, .text = "y", .new = 1234 },
    };
    const Probe = struct {
        const Self = @This();
        hunk: ?usize = null,
        fn onHunk(self: *Self, index: usize) void {
            self.hunk = index;
        }
    };
    var probe: Probe = .{};
    const width: u32 = 300;
    const height: u32 = @intFromFloat(20 * mod.diff_row_height);

    // Run on, the long line scrolls across.
    var scroll: mod.ScrollState = .{ .viewport_height = 20 * mod.diff_row_height };
    canvas.begin(renderer.MacosTheme.light);
    var view = DiffView(&lines, null, &scroll, null);
    canvas.end();
    var first = try canvas.render(view, width, height);
    first.deinit();
    try std.testing.expect(scroll.maxOffsetX() > 0);

    // Wrapped to the width the last frame measured, it does not.
    const columns = mod.DiffLine.wrapColumns(mod.DiffLayout.digitsOf(&lines), scroll.viewport_width);
    try std.testing.expect(columns > 1);
    const rows = try mod.DiffLine.wrap(arena.allocator(), &lines, columns);
    try std.testing.expect(rows.len > lines.len);
    var wrapped: mod.ScrollState = .{ .viewport_height = 20 * mod.diff_row_height };
    for (0..2) |_| {
        canvas.begin(renderer.MacosTheme.light);
        view = DiffView(rows, 0, &wrapped, mod.IndexCallback.init(Probe, &probe, Probe.onHunk));
        canvas.end();
        var frame = try canvas.render(view, width, height);
        frame.deinit();
    }
    try std.testing.expectEqual(@as(f32, 0), wrapped.maxOffsetX());
    try std.testing.expectEqual(@as(f32, @floatFromInt(rows.len)) * mod.diff_row_height, wrapped.content_height);
    // A continued row taps as its line's hunk.
    try std.testing.expect(rows[2].continued);
    try std.testing.expect(canvas.tap(.{ .x = 150, .y = 2.5 * mod.diff_row_height }));
    try std.testing.expectEqual(@as(?usize, 0), probe.hunk);
}

test "a DiffView finds each row's hunk as a pass over the whole diff does" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    mod.BuildScope.shared().begin(arena.allocator());
    defer mod.BuildScope.shared().end();
    var lines: [437]mod.DiffLine = undefined;
    for (&lines, 0..) |*line, index| line.* = if (index == 300)
        .{ .kind = .context, .text = "\t\tthe longest line of all", .old = 1, .new = 1 }
    else switch (index * 7919 % 23) {
        0 => .{ .kind = .fileHeader, .text = "diff --git a/f b/f" },
        1, 2 => .{ .kind = .hunkHeader, .text = "@@ -1 +1 @@" },
        3 => .{ .kind = .note, .text = "\\ No newline at end of file" },
        else => .{ .kind = .added, .text = "x", .new = @intCast(index * 3) },
    };
    // Each row's hunk as a pass over every line finds it.
    var expected: [437]?usize = undefined;
    var current: ?usize = null;
    var next: usize = 0;
    for (lines, &expected) |line, *hunk| {
        switch (line.kind) {
            .hunkHeader => {
                current = next;
                next += 1;
            },
            .fileHeader => current = null,
            else => {},
        }
        hunk.* = current;
    }
    var model: DiffModel = .{ .lines = &lines, .selected = null, .on_hunk = null, .tokens = .{} };
    var start: usize = 0;
    while (start <= lines.len) : (start += 13) {
        const range: mod.RowRange = .{ .start = start, .end = @min(lines.len, start + 40) };
        model.indexHunks(range);
        try std.testing.expectEqualSlices(?usize, expected[range.start..range.end], model.hunk_of);
    }
    try std.testing.expectEqual(@as(usize, 300), model.widest);
    try std.testing.expectEqual(@as(usize, 4), model.digits); // 436 * 3 = 1308
}

test "a DiffView reads a diff whole once, until the diff changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    mod.BuildScope.shared().begin(arena.allocator());
    defer mod.BuildScope.shared().end();
    var lines: [11]mod.DiffLine = undefined;
    for (&lines, 0..) |*line, index| line.* = .{ .kind = .context, .text = "a", .old = @intCast(index), .new = @intCast(index) };
    lines[0] = .{ .kind = .hunkHeader, .text = "@@ -1,9 +1,9 @@" };
    var model: DiffModel = .{ .lines = &lines, .selected = null, .on_hunk = null, .tokens = .{} };
    model.indexHunks(.{ .start = 0, .end = lines.len });
    try std.testing.expectEqual(@as(usize, 0), model.widest);

    // The same diff next frame is not read again: the index keeps its key.
    const key = DiffIndex.shared().key;
    model.indexHunks(.{ .start = 0, .end = lines.len });
    try std.testing.expectEqual(key, DiffIndex.shared().key);

    // A line changed in place is seen.
    lines[5].text = "a line longer than the header";
    model.indexHunks(.{ .start = 0, .end = lines.len });
    try std.testing.expectEqual(@as(usize, 5), model.widest);

    // So is another diff at the same address and length (an arena reused).
    lines[5].text = "a";
    lines[8].text = "the longest line of the rebuilt diff";
    model.indexHunks(.{ .start = 0, .end = lines.len });
    try std.testing.expectEqual(@as(usize, 8), model.widest);
}

test "a table row stripes odd rows and fills a selected one" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const columns = [_]mod.DataColumn{ .{ .title = "Name" }, .{ .title = "Size", .width = 60, .trailing = true } };
    canvas.begin(renderer.MacosTheme.light);
    const even = TableRow(&columns, &.{ mod.Text("a"), mod.Text("1") }, 0, false);
    const odd = TableRow(&columns, &.{ mod.Text("b"), mod.Text("2") }, 1, false);
    const header = TableHeader(&columns);
    canvas.end();
    try std.testing.expect(even.modifiers.background == null);
    try std.testing.expect(odd.modifiers.background != null);
    try std.testing.expect(header.kind == .stack);
}
