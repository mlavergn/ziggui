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

    /// The drag area under a hunk action's link: it takes the press, so the
    /// row's line selection does not start, and does nothing as it moves.
    const link_drag: mod.DragCallback = .{ .function = Self.ignoreDrag };

    /// The diff.
    lines: []const mod.DiffLine,

    /// The marked hunk.
    selected: ?usize,

    /// The tap handler.
    on_hunk: ?mod.IndexCallback,

    /// The selected lines, for a `SelectableDiffView`; null for a plain `DiffView`.
    selection: ?*mod.DiffSelection = null,

    /// The links on every hunk header, for a `SelectableDiffViewWithActions`.
    actions: []const mod.HunkAction = &.{},

    /// How wide a hunk header's text is drawn before its links, so they end
    /// at the pane's right edge however far it scrolled sideways; null while
    /// the pane's width is unknown (the first frame), the links then
    /// following the text.
    pin: ?f32 = null,

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
            .hunkHeader, .fileHeader, .note => blk: {
                const text = mod.Text(Self.expandTabs(line.text)).mono().size(mod.DiffLayout.font_size)
                    .foreground(if (line.kind == .fileHeader) tokens.label else tokens.secondary_label)
                    .weight(if (line.kind == .fileHeader) .semibold else .regular);
                if (line.kind != .hunkHeader or line.continued or self.actions.len == 0) break :blk text;
                break :blk self.withActions(text, hunk orelse break :blk text);
            },
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
        const selection = self.selection orelse return row_view;
        if (selection.contains(index)) row_view = row_view.background(tokens.selection.withAlpha(0.28));
        // Beneath the row's own tap, so a press both picks the hunk and starts the selection.
        return mod.HStack(.{row_view}).spacing(0).frameMaxWidth().onDrag(selection.dragCallback(index));
    }

    /// A hunk header's text, cut where its links begin, then the links. A
    /// copy of the whole text at zero height keeps the row as wide as its
    /// text, so the diff still scrolls sideways as far as it did.
    ///
    /// - `self`: the model.
    /// - `text`: the header's text.
    /// - `hunk`: the hunk the header starts.
    /// - Returns: the header's body.
    fn withActions(self: *const Self, text: mod.View, hunk: usize) mod.View {
        const links = mod.BuildScope.shared().allocator().alloc(mod.View, self.actions.len) catch @panic("oom");
        for (self.actions, links) |action, *link| link.* = Self.actionLink(action, hunk, self.tokens);
        const group = mod.StackBuilder.fromSlice(.horizontal, mod.HunkAction.spacing, .center, links);
        const pin = self.pin orelse return mod.HStack(.{ text, group }).spacing(mod.DiffLayout.cell_spacing);
        return mod.StackBuilder.make(.vertical, 0, .leading, .{
            // A cell of space between the cut text and the first link.
            mod.HStack(.{ text.frameWidth(@max(0, pin - mod.DiffLayout.cell_width)).frameAlign(.leading).clipped(), group }).spacing(@min(pin, mod.DiffLayout.cell_width)),
            text.frameHeight(0).clipped(),
        });
    }

    /// One hunk action's link: its label in the accent color (the secondary
    /// label color, and no tap, when disabled), over a drag area of its own,
    /// so a press on it starts no line selection in the row beneath.
    ///
    /// - `action`: the action.
    /// - `hunk`: the hunk it is called with.
    /// - `tokens`: the frame's colors.
    /// - Returns: the link.
    fn actionLink(action: mod.HunkAction, hunk: usize, tokens: mod.BuildTokens) mod.View {
        const label = mod.Text(action.label).mono().size(mod.DiffLayout.font_size)
            .foreground(if (action.disabled) tokens.secondary_label else tokens.accent)
            .paddingInsets(.{ .leading = mod.HunkAction.padding, .trailing = mod.HunkAction.padding })
            .frameHeight(mod.diff_row_height);
        if (action.disabled) return label;
        return mod.HStack(.{label.onTap(action.callback.bind(hunk))}).spacing(0).onDrag(Self.link_drag);
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

    /// A drag handler that does nothing: a hunk action's link takes the
    /// press, so the row's line selection does not start.
    fn ignoreDrag(_: ?*anyopaque, _: f32, _: f32) void {}
};

/// The stack a `VirtualList` scrolls: the rows in view between two spacers.
const ListBody = struct {
    const Self = @This();

    /// The rows in view, a spacer for those above and one for those below,
    /// and, when `sizer` names a row, that row again at zero height (clipped,
    /// so it draws nothing, and with no overlays at any depth, so a popover
    /// or menu open on that row, or on a view in it, is presented once) to
    /// set the stack's width.
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
        if (sizer) |at| {
            // A measure, not a row: an overlay on it, or on a view inside it,
            // would be presented a second time.
            children[0] = Self.withoutOverlays(rowFn(context, at)).frameHeight(0).clipped();
        }
        children[extra] = mod.Empty().frameHeight(@as(f32, @floatFromInt(range.start)) * row_height);
        for (0..shown) |offset| {
            children[extra + offset + 1] = rowFn(context, range.start + offset).frameHeight(row_height).frameMaxWidth();
        }
        children[extra + shown + 1] = mod.Empty().frameHeight(@as(f32, @floatFromInt(count - range.end)) * row_height);
        return mod.StackBuilder.fromSlice(.vertical, 0, .leading, children).frameMaxWidth();
    }

    /// A copy of `view` with no overlays (`.sheet`, `.alert`, `.popover`) on
    /// it or on any view inside it (stacks, groups, scroll views); the rest
    /// as it was. Copied, never changed in place: a child may be shared.
    ///
    /// - `view`: the view.
    /// - Returns: the copy, its new children in the build arena.
    fn withoutOverlays(view: mod.View) mod.View {
        const arena = mod.BuildScope.shared().allocator();
        var bare = view;
        bare.modifiers.overlay = &.{};
        switch (bare.kind) {
            .stack => |stack| {
                const children = arena.alloc(mod.View, stack.children.len) catch @panic("oom");
                for (stack.children, children) |child, *copy| copy.* = Self.withoutOverlays(child);
                bare.kind.stack.children = children;
            },
            .group => |members| {
                const copies = arena.alloc(mod.View, members.len) catch @panic("oom");
                for (members, copies) |member, *copy| copy.* = Self.withoutOverlays(member);
                bare.kind.group = copies;
            },
            .scroll => |scroll| {
                const content = arena.create(mod.View) catch @panic("oom");
                content.* = Self.withoutOverlays(scroll.content.*);
                bare.kind.scroll.content = content;
            },
            .scrollState => |scroll| {
                const content = arena.create(mod.View) catch @panic("oom");
                content.* = Self.withoutOverlays(scroll.content.*);
                bare.kind.scrollState.content = content;
            },
            else => {},
        }
        return bare;
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
    return diffList(lines, selected, scroll, on_hunk, null, &.{});
}

/// A `DiffView` whose lines can be selected and copied: a press selects a
/// line (and still picks its hunk), a drag or a shift-press extends the run
/// row by row, and ⌘C (Ctrl+C) copies the lines' text, without the gutter or
/// the `+`/`-` marks (`DiffSelection`). Selected rows are tinted in the
/// theme's selection color. A selection ends with a press elsewhere, as a
/// text selection does, and when the view draws other rows.
///
/// - `lines`: the diff.
/// - `selected`: the hunk to mark, if any.
/// - `scroll`: the diff's scroll position, both ways.
/// - `on_hunk`: when set, called with the hunk a tapped row belongs to.
/// - `selection`: the selected lines, kept by the app beside `scroll`.
/// - Returns: the diff.
pub fn SelectableDiffView(lines: []const mod.DiffLine, selected: ?usize, scroll: *mod.ScrollState, on_hunk: ?mod.IndexCallback, selection: *mod.DiffSelection) mod.View {
    selection.track(lines);
    return diffList(lines, selected, scroll, on_hunk, selection, &.{});
}

/// A `SelectableDiffView` with links on every hunk header (a hunk's Stage and
/// Discard, say): borderless labels in the accent color, pinned to the pane's
/// right edge, so they stay put as the diff scrolls sideways and cover the
/// end of a header too long for the pane (the row is still as wide as its
/// text). A tap calls the action with the header's hunk and starts no line
/// selection; a disabled action is drawn in the secondary label color and a
/// tap on it is the row's. Rows stay `diff_row_height` tall; a wrapped
/// header's continued rows have none. No actions draws as `SelectableDiffView`.
///
/// - `lines`: the diff.
/// - `selected`: the hunk to mark, if any.
/// - `scroll`: the diff's scroll position, both ways.
/// - `on_hunk`: when set, called with the hunk a tapped row belongs to.
/// - `selection`: the selected lines, kept by the app beside `scroll`.
/// - `actions`: the links, in order, on every hunk header.
/// - Returns: the diff.
pub fn SelectableDiffViewWithActions(lines: []const mod.DiffLine, selected: ?usize, scroll: *mod.ScrollState, on_hunk: ?mod.IndexCallback, selection: *mod.DiffSelection, actions: []const mod.HunkAction) mod.View {
    selection.track(lines);
    return diffList(lines, selected, scroll, on_hunk, selection, actions);
}

/// The diff's rows over a `VirtualListBoth`, selectable when `selection` is set.
///
/// - `lines`: the diff.
/// - `selected`: the hunk to mark, if any.
/// - `scroll`: the diff's scroll position, both ways.
/// - `on_hunk`: the hunk tap handler, if any.
/// - `selection`: the selected lines, or null for none.
/// - `actions`: the links on every hunk header; empty for none.
/// - Returns: the diff.
fn diffList(lines: []const mod.DiffLine, selected: ?usize, scroll: *mod.ScrollState, on_hunk: ?mod.IndexCallback, selection: ?*mod.DiffSelection, actions: []const mod.HunkAction) mod.View {
    const model = mod.BuildScope.shared().allocator().create(DiffModel) catch @panic("oom");
    model.* = .{ .lines = lines, .selected = selected, .on_hunk = on_hunk, .selection = selection, .actions = actions, .tokens = mod.BuildScope.shared().tokens() };
    if (actions.len > 0 and scroll.viewport_width > 0) {
        // The pane's right edge, in the row's coordinates, less the links and the row's bar.
        const edge = scroll.offset_x + scroll.viewport_width - mod.HunkAction.groupWidth(actions);
        model.pin = @max(0, edge - mod.DiffLayout.bar_width - mod.DiffLayout.bar_spacing);
    }
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
        /// Notes the hunk.
        ///
        /// - `self`: the probe.
        /// - `index`: the hunk's index.
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

test "a SelectableDiffView's press picks the hunk and selects the line; a drag and a shift-press extend it" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const lines = [_]mod.DiffLine{
        .{ .kind = .hunkHeader, .text = "@@ -1,3 +1,3 @@" },
        .{ .kind = .removed, .text = "one", .old = 1 },
        .{ .kind = .added, .text = "two", .new = 1 },
        .{ .kind = .context, .text = "three", .old = 2, .new = 2 },
    };
    const Probe = struct {
        const Self = @This();
        hunk: ?usize = null,
        /// Notes the hunk.
        ///
        /// - `self`: the probe.
        /// - `index`: the hunk's index.
        fn onHunk(self: *Self, index: usize) void {
            self.hunk = index;
        }
    };
    var probe: Probe = .{};
    var selection: mod.DiffSelection = .{};
    defer selection.clear();
    var scroll: mod.ScrollState = .{ .viewport_height = 4 * mod.diff_row_height };
    canvas.begin(renderer.MacosTheme.light);
    const view = SelectableDiffView(&lines, 0, &scroll, mod.IndexCallback.init(Probe, &probe, Probe.onHunk), &selection);
    canvas.end();
    var frame = try canvas.render(view, 300, @intFromFloat(4 * mod.diff_row_height));
    defer frame.deinit();
    const pointer = mod.PointerInput.shared();
    // A press on row 1: its hunk, and the line.
    try std.testing.expect(canvas.tap(.{ .x = 150, .y = 1.5 * mod.diff_row_height }));
    try std.testing.expectEqual(@as(?usize, 0), probe.hunk);
    try std.testing.expect(selection.contains(1) and !selection.contains(2));
    // Dragged a row down, then let go: two lines, copied whole.
    pointer.drag(canvas.hits.items, .{ .x = 150, .y = 2.5 * mod.diff_row_height });
    pointer.endDrag();
    try std.testing.expect(selection.contains(2));
    try std.testing.expectEqualStrings("one\ntwo\n", mod.TextSelection.shared().selectedText().?);
    // A shift-press on row 3 extends from row 1.
    pointer.setClickModifiers(true, false);
    defer pointer.setClickModifiers(false, false);
    try std.testing.expect(canvas.tap(.{ .x = 150, .y = 3.5 * mod.diff_row_height }));
    pointer.endDrag();
    try std.testing.expectEqualStrings("one\ntwo\nthree\n", mod.TextSelection.shared().selectedText().?);
    // A plain DiffView selects nothing.
    selection.clear();
    canvas.begin(renderer.MacosTheme.light);
    const plain = DiffView(&lines, 0, &scroll, null);
    canvas.end();
    var plain_frame = try canvas.render(plain, 300, @intFromFloat(4 * mod.diff_row_height));
    defer plain_frame.deinit();
    _ = canvas.tap(.{ .x = 150, .y = 1.5 * mod.diff_row_height });
    pointer.endDrag();
    try std.testing.expect(mod.TextSelection.shared().selectedText() == null);
}

test "a SelectableDiffViewWithActions pins its links to the pane's right edge, and a tap calls the header's hunk" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const long: [120]u8 = @splat('x');
    const lines = [_]mod.DiffLine{
        .{ .kind = .hunkHeader, .text = "@@ -1 +1 @@" },
        .{ .kind = .added, .text = "one", .new = 1 },
        .{ .kind = .hunkHeader, .text = "@@ -9 +9 @@ " ++ long },
        .{ .kind = .removed, .text = "two", .old = 9 },
    };
    const Probe = struct {
        const Self = @This();
        hunk: ?usize = null,
        staged: ?usize = null,
        discarded: ?usize = null,
        /// Notes the hunk a row tap names.
        ///
        /// - `self`: the probe.
        /// - `index`: the hunk.
        fn onHunk(self: *Self, index: usize) void {
            self.hunk = index;
        }
        /// Notes the hunk Stage was tapped on.
        ///
        /// - `self`: the probe.
        /// - `index`: the hunk.
        fn onStage(self: *Self, index: usize) void {
            self.staged = index;
        }
        /// Notes the hunk Discard was tapped on.
        ///
        /// - `self`: the probe.
        /// - `index`: the hunk.
        fn onDiscard(self: *Self, index: usize) void {
            self.discarded = index;
        }
    };
    var probe: Probe = .{};
    var selection: mod.DiffSelection = .{};
    defer selection.clear();
    const on_hunk = mod.IndexCallback.init(Probe, &probe, Probe.onHunk);
    var actions = [_]mod.HunkAction{
        .{ .label = "Stage", .callback = mod.IndexCallback.init(Probe, &probe, Probe.onStage) },
        .{ .label = "Discard", .callback = mod.IndexCallback.init(Probe, &probe, Probe.onDiscard) },
    };
    const width: u32 = 300;
    const height: u32 = @intFromFloat(4 * mod.diff_row_height);
    var scroll: mod.ScrollState = .{ .viewport_height = 4 * mod.diff_row_height };
    // Discard's middle and Stage's, from the pane's right edge.
    const discard_x: f32 = 300 - mod.HunkAction.trailing - 25;
    const stage_x: f32 = discard_x - 55;
    const pointer = mod.PointerInput.shared();

    // The first frame learns the pane's width; the second pins the links.
    for (0..2) |_| {
        canvas.begin(renderer.MacosTheme.light);
        const view = SelectableDiffViewWithActions(&lines, 0, &scroll, on_hunk, &selection, &actions);
        canvas.end();
        var frame = try canvas.render(view, width, height);
        frame.deinit();
    }
    const content_width = scroll.content_width;
    try std.testing.expect(content_width > 300);
    // Discard on the second header: hunk 1, and no line selected.
    try std.testing.expect(canvas.tap(.{ .x = discard_x, .y = 2.5 * mod.diff_row_height }));
    pointer.endDrag();
    try std.testing.expectEqual(@as(?usize, 1), probe.discarded);
    try std.testing.expectEqual(@as(?usize, null), probe.hunk);
    try std.testing.expect(!selection.contains(2));
    try std.testing.expect(canvas.tap(.{ .x = stage_x, .y = 0.5 * mod.diff_row_height }));
    pointer.endDrag();
    try std.testing.expectEqual(@as(?usize, 0), probe.staged);

    // Scrolled sideways, the links stay at the pane's right edge, and the
    // diff is as wide as before: the long header still sets it.
    scroll.offset_x = 200;
    probe = .{};
    canvas.begin(renderer.MacosTheme.light);
    const scrolled = SelectableDiffViewWithActions(&lines, 0, &scroll, on_hunk, &selection, &actions);
    canvas.end();
    var scrolled_frame = try canvas.render(scrolled, width, height);
    defer scrolled_frame.deinit();
    try std.testing.expectEqual(content_width, scroll.content_width);
    try std.testing.expect(canvas.tap(.{ .x = discard_x, .y = 2.5 * mod.diff_row_height }));
    pointer.endDrag();
    try std.testing.expectEqual(@as(?usize, 1), probe.discarded);

    // A disabled link takes no tap: the row beneath does.
    for (&actions) |*action| action.disabled = true;
    probe = .{};
    canvas.begin(renderer.MacosTheme.light);
    const disabled = SelectableDiffViewWithActions(&lines, 0, &scroll, on_hunk, &selection, &actions);
    canvas.end();
    var disabled_frame = try canvas.render(disabled, width, height);
    defer disabled_frame.deinit();
    try std.testing.expect(canvas.tap(.{ .x = discard_x, .y = 2.5 * mod.diff_row_height }));
    pointer.endDrag();
    try std.testing.expectEqual(@as(?usize, null), probe.discarded);
    try std.testing.expectEqual(@as(?usize, 1), probe.hunk);
}

test "a wrapped hunk header carries its links on its first row only, and a narrow pane cuts its text" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const long: [80]u8 = @splat('x');
    const lines = [_]mod.DiffLine{
        .{ .kind = .hunkHeader, .text = "@@ -1 +1 @@ " ++ long },
        .{ .kind = .hunkHeader, .text = &long, .continued = true },
        .{ .kind = .added, .text = "one", .new = 1 },
    };
    const Probe = struct {
        const Self = @This();
        hunk: ?usize = null,
        acted: ?usize = null,
        /// Notes the hunk a row tap names.
        ///
        /// - `self`: the probe.
        /// - `index`: the hunk.
        fn onHunk(self: *Self, index: usize) void {
            self.hunk = index;
        }
        /// Notes the hunk the link was tapped on.
        ///
        /// - `self`: the probe.
        /// - `index`: the hunk.
        fn onAction(self: *Self, index: usize) void {
            self.acted = index;
        }
    };
    var probe: Probe = .{};
    var selection: mod.DiffSelection = .{};
    defer selection.clear();
    const actions = [_]mod.HunkAction{.{ .label = "Stage", .callback = mod.IndexCallback.init(Probe, &probe, Probe.onAction) }};
    const width: u32 = 200;
    const height: u32 = @intFromFloat(3 * mod.diff_row_height);
    var scroll: mod.ScrollState = .{ .viewport_height = 3 * mod.diff_row_height };
    for (0..2) |_| {
        canvas.begin(renderer.MacosTheme.light);
        const view = SelectableDiffViewWithActions(&lines, null, &scroll, mod.IndexCallback.init(Probe, &probe, Probe.onHunk), &selection, &actions);
        canvas.end();
        var frame = try canvas.render(view, width, height);
        frame.deinit();
    }
    const link_x: f32 = 200 - mod.HunkAction.trailing - 10;
    // The continued row has no link: a tap there is the row's.
    try std.testing.expect(canvas.tap(.{ .x = link_x, .y = 1.5 * mod.diff_row_height }));
    mod.PointerInput.shared().endDrag();
    try std.testing.expectEqual(@as(?usize, null), probe.acted);
    try std.testing.expectEqual(@as(?usize, 0), probe.hunk);
    try std.testing.expect(canvas.tap(.{ .x = link_x, .y = 0.5 * mod.diff_row_height }));
    mod.PointerInput.shared().endDrag();
    try std.testing.expectEqual(@as(?usize, 0), probe.acted);

    // The header's text is drawn cut a cell before the link, inside the pane.
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    mod.BuildScope.shared().begin(arena.allocator());
    defer mod.BuildScope.shared().end();
    const model: DiffModel = .{ .lines = &lines, .selected = null, .on_hunk = null, .actions = &actions, .pin = 100, .tokens = mod.BuildScope.shared().tokens() };
    const body = model.withActions(mod.Text(lines[0].text), 0);
    const shown = body.kind.stack.children[0].kind.stack.children[0];
    try std.testing.expectEqual(@as(?f32, 100 - mod.DiffLayout.cell_width), shown.modifiers.frame.?.width);
    // The whole text again, at zero height, keeps the row as wide.
    try std.testing.expectEqual(@as(?f32, 0), body.kind.stack.children[1].modifiers.frame.?.height);
}

test "a SelectableDiffViewWithActions with no actions draws as a SelectableDiffView" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const lines = [_]mod.DiffLine{
        .{ .kind = .hunkHeader, .text = "@@ -1 +1 @@" },
        .{ .kind = .added, .text = "one", .new = 1 },
    };
    var selection: mod.DiffSelection = .{};
    defer selection.clear();
    var scroll: mod.ScrollState = .{ .viewport_height = 2 * mod.diff_row_height, .viewport_width = 200 };
    const height: u32 = @intFromFloat(2 * mod.diff_row_height);
    canvas.begin(renderer.MacosTheme.light);
    const plain = SelectableDiffView(&lines, 0, &scroll, null, &selection);
    canvas.end();
    var plain_frame = try canvas.render(plain, 200, height);
    defer plain_frame.deinit();
    canvas.begin(renderer.MacosTheme.light);
    const bare = SelectableDiffViewWithActions(&lines, 0, &scroll, null, &selection, &.{});
    canvas.end();
    var bare_frame = try canvas.render(bare, 200, height);
    defer bare_frame.deinit();
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(plain_frame.pixels), std.mem.sliceAsBytes(bare_frame.pixels));
}

test "the widest row, built again to set the width, presents no popover of its own" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    mod.BuildScope.shared().begin(arena.allocator());
    defer mod.BuildScope.shared().end();
    const Rows = struct {
        const Self = @This();

        /// Whether row 0's popover is open.
        open: bool = true,

        /// Row `index`, with a popover open on row 0.
        ///
        /// - `self`: the rows.
        /// - `index`: the row.
        /// - Returns: the row.
        fn row(self: *const Self, index: usize) mod.View {
            const text = mod.Text("row");
            if (index != 0) return text;
            const presented: renderer.Binding(bool) = .{ .context = @constCast(self), .get_fn = Self.get, .set_fn = Self.set };
            return text.popover(presented, mod.Text("menu"));
        }

        /// The popover binding's reader.
        ///
        /// - `context`: the rows.
        /// - Returns: whether the popover is open.
        fn get(context: *anyopaque) bool {
            const self: *Self = @ptrCast(@alignCast(context));
            return self.open;
        }

        /// The popover binding's writer.
        ///
        /// - `context`: the rows.
        /// - `value`: whether the popover is open.
        fn set(context: *anyopaque, value: bool) void {
            const self: *Self = @ptrCast(@alignCast(context));
            self.open = value;
        }
    };
    const rows: Rows = .{};
    var scroll: mod.ScrollState = .{ .viewport_height = 100 };
    const body = ListBody.build(Rows, &rows, 3, 20, &scroll, Rows.row, 0);
    const children = body.kind.stack.children;
    // The measure first, bare; row 0 in view keeps its popover.
    try std.testing.expectEqual(@as(usize, 0), children[0].modifiers.overlay.len);
    try std.testing.expectEqual(@as(usize, 1), children[2].modifiers.overlay.len);
}

test "the widest row, built again to set the width, presents no popover from inside it either" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    mod.BuildScope.shared().begin(arena.allocator());
    defer mod.BuildScope.shared().end();
    var open = renderer.State(bool).init(std.testing.allocator, true);
    defer open.deinit();
    const nested = mod.HStack(.{ mod.Text("row"), mod.Text("more").popover(open.binding(), mod.Text("menu")) });
    const bare = ListBody.withoutOverlays(nested);
    try std.testing.expectEqual(@as(usize, 0), bare.kind.stack.children[1].modifiers.overlay.len);
    // The row it was copied from keeps its popover.
    try std.testing.expectEqual(@as(usize, 1), nested.kind.stack.children[1].modifiers.overlay.len);
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
        /// Notes the hunk.
        ///
        /// - `self`: the probe.
        /// - `index`: the hunk's index.
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
