//! What a `Table` keeps between frames: its scroll, sort, column widths
//! and selection.

const std = @import("std");
const log = std.log.scoped(.ziggui_table_state);
const mod = @import("module.zig");

/// What a `Table` selects.
pub const TableSelectionMode = enum {
    const Self = @This();

    /// Nothing; a double click or Enter still activates a row.
    none,

    /// Rows: several by ID with ⌘ and ⇧ when the table has an `idFn`, one by
    /// position when it has none.
    row,

    /// One cell, the cursor, by position.
    cell,
};

/// A cell of a `Table`, by position.
pub const TableCell = struct {
    const Self = @This();

    /// The row's position in the table's order.
    row: usize,

    /// The column's index.
    column: usize,
};

/// A ⇧-range of a `Table`'s rows, by position in the last frame's order.
pub const TableSpan = struct {
    const Self = @This();

    /// The first row's position.
    first: usize,

    /// The last row's position, inclusive.
    last: usize,

    /// Whether a row lies in the span.
    ///
    /// - `self`: the span.
    /// - `row`: the row's position.
    /// - Returns: true for a row from `first` to `last`.
    pub fn contains(self: *const Self, row: usize) bool {
        return row >= self.first and row <= self.last;
    }
};

/// A table's row IDs, type-erased: the app's context and its `idFn`, as the
/// last frame handed them over.
pub const TableIdSource = struct {
    const Self = @This();

    /// The app's context.
    context: *const anyopaque,

    /// The ID of a row.
    ///
    /// - `context`: the app's context.
    /// - `row`: the row's position.
    /// - Returns: the row's ID.
    function: *const fn (context: *const anyopaque, row: usize) u64,

    /// The ID of a row.
    ///
    /// - `self`: the source.
    /// - `row`: the row's position.
    /// - Returns: the row's ID.
    pub fn id(self: *const Self, row: usize) u64 {
        return self.function(self.context, row);
    }
};

/// A `Table`'s state, app-owned at a stable address (taps and drags
/// point back at it): the scroll both ways, the header's sideways scroll
/// kept level with it, the sort, the widths the user dragged, and the
/// selection.
///
/// Rows are selected by the app's IDs (`idFn`), so a selection survives a
/// re-sort or a filter: `ids`, `all` (⌘A) less `excluded`, or a ⇧-range
/// (`span`) less `excluded`. A range is held as positions, so selecting a
/// million rows costs nothing; `invalidate`, which the app calls before its
/// rows change order, turns it into IDs. While `all` or `span` is set the app
/// walks its own rows with `isRowSelected`. The cursor (the keyboard's row or
/// cell) and the anchor a ⇧ selection extends from are positions too,
/// cleared by `invalidate`.
///
/// Each frame `Table` records what the handlers need: the row count,
/// the columns' laid-out widths, the mode, the ID source and the callbacks.
/// They are used only while that frame is its window's last (`drawn_in`,
/// the main window's or the popover window's), so a table the app stopped drawing never calls into a
/// context it may have freed: its keys go unhandled, a row selected from
/// code waits for the next frame that draws the table (`pending_id`), and
/// `invalidate` drops a range it can no longer read.
pub const TableState = struct {
    const Self = @This();

    /// The room before the first column and after the last; the columns
    /// themselves abut, as a `Table`'s do.
    pub const side_inset: f32 = 8;
    /// The most IDs an ID set keeps room for once emptied: a larger one,
    /// left by a big range, gives its memory back.
    const retained_ids = 4096;

    /// The selected rows' IDs, beside `all` and `span`.
    ids: std.AutoHashMapUnmanaged(u64, void) = .empty,
    /// The IDs taken out of `all` or `span` with ⌘-click.
    excluded: std.AutoHashMapUnmanaged(u64, void) = .empty,
    /// The rows a ⇧-range selected, as positions in the last frame's order,
    /// until `invalidate` turns them into IDs; null for none.
    span: ?TableSpan = null,
    /// The frame, in the window that drew it (the main window or the tray
    /// popover window), that last drew the table, or null before the first: the ID
    /// source and the callbacks are used only while it is that window's last
    /// frame (`BuildScope.isLatest`).
    drawn_in: ?mod.FrameStamp = null,
    /// The widths the user dragged; negative for a column never dragged.
    widths: std.ArrayList(f32) = .empty,
    /// Each column's width at the last layout.
    laid_out: std.ArrayList(f32) = .empty,
    /// Each column's narrowest width at the last layout.
    minimums: std.ArrayList(f32) = .empty,
    /// Where the ID sets and widths live.
    allocator: std.mem.Allocator,
    /// The rows' scroll position, both ways.
    scroll: mod.ScrollState = .{},
    /// The header's scroll position, kept level with the rows' sideways.
    header_scroll: mod.ScrollState = .{},
    /// The sideways offset both shared at the last frame: whichever moved since leads.
    shared_offset_x: f32 = 0,
    /// The sort; `index` is -1 when unsorted.
    sort: mod.SortColumn = .{},
    /// Whether the table has the keyboard: the cell cursor shows only then.
    focused: bool = false,
    /// The keyboard's cell: the selected cell in `.cell` mode, the selected
    /// row in `.row` mode without IDs, the row ⌘ and ⇧ last acted on otherwise.
    cursor: ?TableCell = null,
    /// The row a ⇧ selection extends from.
    anchor: ?usize = null,
    /// Every row selected (⌘A), less `excluded`.
    all: bool = false,
    /// A row was selected before the table had an ID source: the next frame
    /// that has one selects the cursor's row by its ID (`settleIds`).
    pending_id: bool = false,
    /// The rows at the last frame.
    count: usize = 0,
    /// The selection mode at the last frame.
    mode: TableSelectionMode = .row,
    /// Each row's height at the last frame.
    row_height: f32 = 24,
    /// Whether ⌘ and ⇧ select several rows, at the last frame.
    multiple: bool = true,
    /// The rows' IDs at the last frame, or null for a table without them.
    id_source: ?TableIdSource = null,
    /// What a double click or Enter calls with the row.
    on_activate: ?mod.IndexCallback = null,
    /// What a sorting header tap calls, after `sort` changed.
    on_sort: ?mod.Callback = null,
    /// What every selection change calls.
    on_selection: ?mod.Callback = null,
    /// The column whose trailing edge a drag holds.
    drag_column: usize = 0,
    /// The held column's width when the press came.
    drag_start: f32 = 0,
    /// How far the pointer moved since the press, unclamped.
    drag_offset: f32 = 0,

    /// A state with nothing selected, sorted or dragged.
    ///
    /// - `allocator`: where the ID sets and widths live.
    /// - Returns: the state.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Frees the ID sets and widths.
    ///
    /// - `self`: the state.
    pub fn deinit(self: *Self) void {
        self.ids.deinit(self.allocator);
        self.excluded.deinit(self.allocator);
        self.widths.deinit(self.allocator);
        self.laid_out.deinit(self.allocator);
        self.minimums.deinit(self.allocator);
    }

    /// Keeps the header level with the rows sideways: whichever moved since
    /// the last frame leads the other. `Table` calls it as it builds.
    ///
    /// - `self`: the state.
    pub fn syncSideways(self: *Self) void {
        if (self.header_scroll.offset_x != self.shared_offset_x) {
            self.scroll.offset_x = self.header_scroll.offset_x;
        } else {
            self.header_scroll.offset_x = self.scroll.offset_x;
        }
        self.shared_offset_x = self.scroll.offset_x;
    }

    /// Gives a row selected before the table had IDs (an app selecting
    /// before the first frame, or while the table showed nothing) its ID, now
    /// that the frame has an ID source. `Table` calls it as it builds.
    ///
    /// - `self`: the state.
    pub fn settleIds(self: *Self) void {
        if (!self.pending_id) return;
        self.pending_id = false;
        const source = self.liveSource() orelse return;
        const cursor = self.cursor orelse return;
        if (cursor.row >= self.count) return;
        self.dropIds();
        self.addId(source.id(cursor.row));
    }

    /// Lays the columns out: a dragged width, else the column's own, else an
    /// equal share of what those leave of `room` (the last sharing column
    /// taking the rest), none under its `min_width`: a sharing column its
    /// minimum holds takes that, and the others split what it leaves, so the
    /// table overflows the pane only when the minimums alone do. `Table`
    /// calls it as it builds; the widths land in `laid_out`.
    ///
    /// - `self`: the state.
    /// - `columns`: the table's columns.
    /// - `room`: the pane's width, or null when no column shares it.
    /// - Returns: nothing; propagates allocation failure.
    pub fn layOut(self: *Self, columns: []const mod.TableColumn, room: ?f32) std.mem.Allocator.Error!void {
        while (self.widths.items.len < columns.len) try self.widths.append(self.allocator, -1);
        try self.laid_out.resize(self.allocator, columns.len);
        try self.minimums.resize(self.allocator, columns.len);
        var used: f32 = 2 * side_inset;
        var sharing: usize = 0;
        for (columns, 0..) |column, index| {
            self.minimums.items[index] = column.min_width;
            const own = if (self.widths.items[index] >= 0) self.widths.items[index] else column.width;
            if (own) |width| {
                self.laid_out.items[index] = @max(width, column.min_width);
                used += self.laid_out.items[index];
            } else {
                sharing += 1;
            }
        }
        if (sharing == 0) return;
        var left = @max(0, (room orelse 0) - used);
        // Hold at its minimum each sharing column an equal share would put
        // under it; the share only shrinks as columns are held, so one pass
        // more finds every column the smaller share now puts under.
        var open = sharing;
        for (0..columns.len) |index| {
            if (self.isSharing(columns, index)) self.laid_out.items[index] = -1;
        }
        var held = true;
        while (held and open > 0) {
            held = false;
            const share = @floor(left / @as(f32, @floatFromInt(open)));
            for (columns, 0..) |column, index| {
                if (!self.isSharing(columns, index) or self.laid_out.items[index] >= 0 or column.min_width <= share) continue;
                self.laid_out.items[index] = column.min_width;
                left = @max(0, left - column.min_width);
                open -= 1;
                held = true;
            }
        }
        // The rest split what is left, the last of them taking the remainder.
        const share = if (open > 0) @floor(left / @as(f32, @floatFromInt(open))) else 0;
        var given: f32 = 0;
        var last_open: usize = 0;
        for (0..columns.len) |index| {
            if (self.isSharing(columns, index) and self.laid_out.items[index] < 0) last_open = index;
        }
        for (columns, 0..) |column, index| {
            if (!self.isSharing(columns, index) or self.laid_out.items[index] >= 0) continue;
            const width = if (index == last_open) left - given else share;
            given += width;
            self.laid_out.items[index] = @max(width, column.min_width);
        }
    }

    /// Whether a column shares what the others leave of the pane: it has no
    /// width of its own and was never dragged.
    ///
    /// - `self`: the state.
    /// - `columns`: the table's columns.
    /// - `index`: the column.
    /// - Returns: true for a sharing column.
    fn isSharing(self: *const Self, columns: []const mod.TableColumn, index: usize) bool {
        return self.widths.items[index] < 0 and columns[index].width == null;
    }

    /// A column's width as the user dragged it.
    ///
    /// - `self`: the state.
    /// - `index`: the column.
    /// - Returns: the width, or null for a column never dragged.
    pub fn columnWidth(self: *const Self, index: usize) ?f32 {
        if (index >= self.widths.items.len or self.widths.items[index] < 0) return null;
        return self.widths.items[index];
    }

    /// Forgets every dragged width: each column goes back to its own.
    ///
    /// - `self`: the state.
    pub fn resetWidths(self: *Self) void {
        for (self.widths.items) |*width| width.* = -1;
    }

    /// Where a column starts, across a row, at the last layout.
    ///
    /// - `self`: the state.
    /// - `column`: the column.
    /// - Returns: its leading edge, in points.
    pub fn leadingEdge(self: *const Self, column: usize) f32 {
        var edge: f32 = side_inset;
        for (self.laid_out.items[0..@min(column, self.laid_out.items.len)]) |width| edge += width;
        return edge;
    }

    /// Selects one row, alone, and makes it the anchor.
    ///
    /// - `self`: the state.
    /// - `row`: the row's position.
    pub fn select(self: *Self, row: usize) void {
        self.cursor = .{ .row = row, .column = if (self.cursor) |cursor| cursor.column else 0 };
        self.anchor = row;
        if (self.liveSource()) |source| {
            self.dropIds();
            self.addId(source.id(row));
        } else self.pending_id = true;
        self.notify();
    }

    /// Selects the rows from the anchor to `row` (⇧-click), in place of the
    /// selection, as a `span` of positions, however many rows it covers;
    /// without IDs or `multiple`, selects `row` alone.
    ///
    /// - `self`: the state.
    /// - `row`: the row's position.
    pub fn extend(self: *Self, row: usize) void {
        if (self.liveSource() == null or !self.multiple) return self.select(row);
        const from = self.anchor orelse return self.select(row);
        self.dropIds();
        self.span = .{ .first = @min(from, row), .last = @max(from, row) };
        self.cursor = .{ .row = row, .column = 0 };
        self.notify();
    }

    /// Adds `row` to the selection, or takes it out (⌘-click), and makes it
    /// the anchor; without IDs or `multiple`, selects it alone.
    ///
    /// - `self`: the state.
    /// - `row`: the row's position.
    pub fn toggle(self: *Self, row: usize) void {
        const source = self.liveSource() orelse return self.select(row);
        if (!self.multiple) return self.select(row);
        const id = source.id(row);
        // A row of `all` or the span is taken out (or put back) through
        // `excluded`; any other row through `ids`.
        const set = if (self.inRange(row)) &self.excluded else &self.ids;
        if (!set.remove(id)) set.put(self.allocator, id, {}) catch |err| log.warn("row not selected: {s}", .{@errorName(err)});
        self.cursor = .{ .row = row, .column = 0 };
        self.anchor = row;
        self.notify();
    }

    /// Selects every row (⌘A) at no cost: the `all` flag, nothing excluded.
    /// Only a `.row` table with IDs selects several rows.
    ///
    /// - `self`: the state.
    pub fn selectAll(self: *Self) void {
        if (self.mode != .row or self.liveSource() == null or !self.multiple) return;
        self.dropIds();
        self.all = true;
        self.notify();
    }

    /// Selects one cell, the cursor (`.cell` mode).
    ///
    /// - `self`: the state.
    /// - `cell`: the cell.
    pub fn selectCell(self: *Self, cell: TableCell) void {
        self.cursor = cell;
        self.anchor = cell.row;
        self.notify();
    }

    /// Selects nothing, and drops the cursor and the anchor.
    ///
    /// - `self`: the state.
    pub fn clearSelection(self: *Self) void {
        self.dropIds();
        self.pending_id = false;
        self.cursor = null;
        self.anchor = null;
        self.notify();
    }

    /// Whether anything is selected.
    ///
    /// - `self`: the state.
    /// - Returns: true with a selected row or cell.
    pub fn hasSelection(self: *const Self) bool {
        return self.all or self.span != null or self.ids.count() > 0 or (self.id_source == null and self.cursor != null);
    }

    /// Whether a row shows as selected (`.row` mode): by its ID, in `all`
    /// or the span less `excluded`, or among `ids`.
    ///
    /// - `self`: the state.
    /// - `row`: the row's position.
    /// - Returns: true when it is selected; false for a table with IDs the
    ///   last frame did not draw.
    pub fn isRowSelected(self: *const Self, row: usize) bool {
        if (self.mode != .row) return false;
        if (self.id_source != null) {
            const source = self.liveSource() orelse return false;
            const id = source.id(row);
            return (self.inRange(row) and !self.excluded.contains(id)) or self.ids.contains(id);
        }
        const cursor = self.cursor orelse return false;
        return cursor.row == row;
    }

    /// Whether the row with an ID is selected, by `all` or `ids`. A ⇧-range's
    /// rows are positions until `invalidate` (`span`): while one is held,
    /// `isRowSelected` answers for them.
    ///
    /// - `self`: the state.
    /// - `id`: the row's ID.
    /// - Returns: true when it is selected.
    pub fn isSelectedId(self: *const Self, id: u64) bool {
        return (self.all and !self.excluded.contains(id)) or self.ids.contains(id);
    }

    /// Whether a cell is the cursor (`.cell` mode).
    ///
    /// - `self`: the state.
    /// - `row`: the row's position.
    /// - `column`: the column.
    /// - Returns: true for the cursor.
    pub fn isCursor(self: *const Self, row: usize, column: usize) bool {
        const cursor = self.cursor orelse return false;
        return self.mode == .cell and cursor.row == row and cursor.column == column;
    }

    /// Forgets the positions before a re-sort, a re-filter or a new row
    /// count: a ⇧-range becomes the IDs of its rows (read while the rows are
    /// still in the order it was made in, so call it before they change),
    /// then the cursor and the anchor go (and so, without IDs, the selected
    /// row). The selected IDs stay; a row filtered out stays selected,
    /// unseen. A sorting header tap calls it before `sort` changes; the app
    /// calls it before it filters. A range on a table the last frame did not
    /// draw cannot be read, and is dropped.
    ///
    /// - `self`: the state.
    pub fn invalidate(self: *Self) void {
        self.settleSpan();
        const had_row = self.id_source == null and self.cursor != null;
        self.cursor = null;
        self.anchor = null;
        self.pending_id = false;
        if (had_row) self.notify();
    }

    /// Moves the cursor by rows and columns, clamped to the table, and
    /// scrolls it into view; with no cursor, goes to the first cell. In
    /// `.row` mode it selects the row, or with `extend` (⇧) extends to it.
    ///
    /// - `self`: the state.
    /// - `rows`: rows to move; negative moves up.
    /// - `columns`: columns to move (`.cell` mode); negative moves left.
    /// - `extend_selection`: extend the selection (⇧) rather than replace it.
    pub fn moveCursor(self: *Self, rows: i64, columns: i64, extend_selection: bool) void {
        if (self.count == 0 or self.mode == .none) return;
        const last_row: i64 = @intCast(self.count - 1);
        const last_column: i64 = @intCast(@max(1, self.laid_out.items.len) - 1);
        const target: TableCell = if (self.cursor) |from| .{
            .row = @intCast(std.math.clamp(@as(i64, @intCast(from.row)) + rows, 0, last_row)),
            .column = if (self.mode == .cell) @intCast(std.math.clamp(@as(i64, @intCast(from.column)) + columns, 0, last_column)) else 0,
        } else .{ .row = 0, .column = 0 };
        switch (self.mode) {
            .cell => self.selectCell(target),
            .row => if (extend_selection) self.extend(target.row) else self.select(target.row),
            .none => {},
        }
        self.reveal(target.row, if (self.mode == .cell) target.column else null);
    }

    /// Scrolls just enough to show a row and, given one, a column.
    ///
    /// - `self`: the state.
    /// - `row`: the row's position.
    /// - `column`: the column, or null to leave the sideways scroll.
    pub fn reveal(self: *Self, row: usize, column: ?usize) void {
        self.scroll.reveal(row, self.row_height);
        if (column) |index| self.revealColumn(index);
    }

    /// Scrolls sideways just enough to show a column, at the last layout.
    ///
    /// - `self`: the state.
    /// - `index`: the column.
    pub fn revealColumn(self: *Self, index: usize) void {
        if (index >= self.laid_out.items.len) return;
        const left = self.leadingEdge(index);
        const right = left + self.laid_out.items[index];
        const visible = self.scroll.viewport_width;
        if (left - side_inset < self.scroll.offset_x) {
            self.scroll.offset_x = @max(0, left - side_inset);
        } else if (visible > 0 and right + side_inset > self.scroll.offset_x + visible) {
            self.scroll.offset_x = right + side_inset - visible;
        }
    }

    /// Handles a key while the table has the keyboard: the arrows move the
    /// cursor (⇧ extends a row selection), Page Up/Down move a page, Home/End
    /// go to the first and last rows, ⌘A selects every row, Enter activates
    /// the cursor's row, Esc clears the selection.
    ///
    /// - `self`: the state.
    /// - `key`: the key.
    /// - Returns: whether the key was the table's.
    pub fn handleKey(self: *Self, key: mod.Key) bool {
        // A table the last frame did not draw takes no keys.
        if (!self.isLive()) return false;
        if (key.command and !key.alt and (key.char == 'a' or key.char == 'A')) {
            if (self.mode != .row or self.id_source == null or !self.multiple) return false;
            self.selectAll();
            return true;
        }
        // Before the row count: a selection a filter hid can still be cleared.
        if (key.isNamed(.escape)) {
            if (!self.hasSelection() and self.cursor == null) return false;
            self.clearSelection();
            return true;
        }
        if (self.count == 0) return false;
        const rows: i64 = @intCast(self.count);
        if (key.isNamed(.enter)) {
            const cursor = self.cursor orelse return false;
            const callback = self.on_activate orelse return false;
            callback.call(cursor.row);
            return true;
        }
        if (self.mode == .none) return false;
        const page = self.pageRows();
        const move: ?[2]i64 = if (key.isNamed(.up))
            .{ -1, 0 }
        else if (key.isNamed(.down))
            .{ 1, 0 }
        else if (key.isNamed(.left) and self.mode == .cell)
            .{ 0, -1 }
        else if (key.isNamed(.right) and self.mode == .cell)
            .{ 0, 1 }
        else if (key.isNamed(.pageUp))
            .{ -page, 0 }
        else if (key.isNamed(.pageDown))
            .{ page, 0 }
        else if (key.isNamed(.home))
            .{ -rows, 0 }
        else if (key.isNamed(.end))
            .{ rows, 0 }
        else
            null;
        const delta = move orelse return false;
        self.moveCursor(delta[0], delta[1], key.shift);
        return true;
    }

    /// A tap on a cell: a double click activates its row; otherwise it
    /// selects as the mode and the modifiers say (⌘ toggles, ⇧ extends).
    /// Gives the table the keyboard.
    ///
    /// - `self`: the state.
    /// - `tag`: the cell, `row * columns + column` at the last layout.
    pub fn tapCell(self: *Self, tag: usize) void {
        const columns = @max(1, self.laid_out.items.len);
        const cell = TableCell{ .row = tag / columns, .column = tag % columns };
        self.focused = true;
        const pointer = mod.PointerInput.shared();
        if (pointer.isDoubleClick()) {
            if (self.on_activate) |callback| callback.call(cell.row);
            return;
        }
        switch (self.mode) {
            .none => {},
            .cell => self.selectCell(cell),
            .row => if (pointer.clickCommand()) self.toggle(cell.row) else if (pointer.clickShift()) self.extend(cell.row) else self.select(cell.row),
        }
    }

    /// A tap on a sortable header: sorts by its column in the column's first
    /// order, or flips the order when already sorted by it, forgets the
    /// positions (`invalidate`) and tells the app to re-sort.
    ///
    /// - `self`: the state.
    /// - `tag`: `column * 2`, plus 1 when the column's first order is `.reverse`.
    pub fn tapHeader(self: *Self, tag: usize) void {
        const column: i64 = @intCast(tag / 2);
        const first: mod.SortOrder = if (tag % 2 == 1) .reverse else .forward;
        // While the rows are in the old order: an `idFn` may read `sort`.
        self.invalidate();
        if (self.sort.index == column) {
            self.sort.order = if (self.sort.order == .forward) .reverse else .forward;
        } else {
            self.sort = .{ .index = column, .order = first };
        }
        if (self.on_sort) |callback| callback.call();
    }

    /// A press on a column's trailing edge: holds it, and arms `PointerInput`
    /// to feed the drag its movement until the button is up.
    ///
    /// - `self`: the state; must outlive the drag.
    /// - `column`: the column whose edge was pressed.
    pub fn pressEdge(self: *Self, column: usize) void {
        if (column >= self.laid_out.items.len) return;
        self.drag_column = column;
        self.drag_start = self.laid_out.items[column];
        self.drag_offset = 0;
        mod.PointerInput.shared().armDrag(.{ .context = self, .function = Self.onDrag });
    }

    /// Moves a held edge: the column takes the drag's movement, never under
    /// its minimum; the table grows or shrinks with it.
    ///
    /// - `self`: the state.
    /// - `delta_x`: the drag's movement across.
    pub fn drag(self: *Self, delta_x: f32) void {
        const column = self.drag_column;
        if (column >= self.widths.items.len or column >= self.minimums.items.len) return;
        self.drag_offset += delta_x;
        self.widths.items[column] = @max(self.minimums.items[column], self.drag_start + self.drag_offset);
    }

    /// The drag handler `pressEdge` arms.
    ///
    /// - `context`: the state.
    /// - `delta_x`: the movement across.
    /// - `delta_y`: the movement down, unused.
    fn onDrag(context: ?*anyopaque, delta_x: f32, delta_y: f32) void {
        _ = delta_y;
        const self: *Self = @ptrCast(@alignCast(context.?));
        self.drag(delta_x);
    }

    /// Empties the ID sets, the span and the `all` flag.
    ///
    /// - `self`: the state.
    fn dropIds(self: *Self) void {
        self.emptySet(&self.ids);
        self.emptySet(&self.excluded);
        self.all = false;
        self.span = null;
    }

    /// Empties an ID set, keeping its room only while that is small.
    ///
    /// - `self`: the state.
    /// - `set`: `ids` or `excluded`.
    fn emptySet(self: *Self, set: *std.AutoHashMapUnmanaged(u64, void)) void {
        if (set.capacity() > retained_ids) set.clearAndFree(self.allocator) else set.clearRetainingCapacity();
    }

    /// Turns the span into the IDs of its rows, less `excluded`, at the last
    /// frame's row count; drops it when the last frame did not draw the table.
    ///
    /// - `self`: the state.
    fn settleSpan(self: *Self) void {
        const span = self.span orelse return;
        self.span = null;
        const source = self.liveSource() orelse return;
        if (span.first < self.count) {
            const last = @min(span.last, self.count - 1);
            self.ids.ensureUnusedCapacity(self.allocator, @intCast(@min(last - span.first + 1, std.math.maxInt(u32)))) catch |err| log.warn("range not kept whole: {s}", .{@errorName(err)});
            for (span.first..last + 1) |position| {
                const id = source.id(position);
                if (!self.excluded.contains(id)) self.addId(id);
            }
        }
        // `excluded` held only the range's exceptions (`all` is never set beside it).
        self.emptySet(&self.excluded);
    }

    /// Whether a row lies in `all` or the span.
    ///
    /// - `self`: the state.
    /// - `row`: the row's position.
    /// - Returns: true when it does.
    fn inRange(self: *const Self, row: usize) bool {
        if (self.all) return true;
        const span = self.span orelse return false;
        return span.contains(row);
    }

    /// Whether the last frame of the window that drew the table drew it, so
    /// what that frame recorded (the ID source, the callbacks) may be called.
    ///
    /// - `self`: the state.
    /// - Returns: true when it did.
    fn isLive(self: *const Self) bool {
        const frame = self.drawn_in orelse return false;
        return mod.BuildScope.shared().isLatest(frame);
    }

    /// The ID source, while the last frame drew the table.
    ///
    /// - `self`: the state.
    /// - Returns: the source; null without IDs or for a table not drawn.
    fn liveSource(self: *const Self) ?TableIdSource {
        return if (self.isLive()) self.id_source else null;
    }

    /// Adds an ID to the selection.
    ///
    /// - `self`: the state.
    /// - `id`: the row's ID.
    fn addId(self: *Self, id: u64) void {
        self.ids.put(self.allocator, id, {}) catch |err| log.warn("row not selected: {s}", .{@errorName(err)});
    }

    /// Tells the app the selection changed.
    ///
    /// - `self`: the state.
    fn notify(self: *const Self) void {
        if (!self.isLive()) return;
        if (self.on_selection) |callback| callback.call();
    }

    /// The rows a page key moves: a viewport's worth, less one for context.
    ///
    /// - `self`: the state.
    /// - Returns: at least 1.
    fn pageRows(self: *const Self) i64 {
        if (self.row_height <= 0) return 1;
        const shown: i64 = @intFromFloat(@floor(self.scroll.viewport_height / self.row_height));
        return @max(1, shown - 1);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(TableState);
}

/// Row IDs for the tests: row `i` has ID `1000 + i`.
const TestIds = struct {
    const Self = @This();

    /// The context the IDs are asked with; they need none.
    const context: u8 = 0;

    /// The ID of a row; the context (`TestIds.context`) goes unread.
    ///
    /// - `row`: the row's position.
    /// - Returns: `1000 + row`.
    fn id(_: *const anyopaque, row: usize) u64 {
        return 1000 + @as(u64, row);
    }

    /// A state of `count` rows with IDs, in `.row` mode, three columns laid out.
    ///
    /// - `count`: the rows.
    /// - Returns: the state, which the caller deinits; propagates allocation failure.
    fn state(count: usize) std.mem.Allocator.Error!TableState {
        var table = TableState.init(std.testing.allocator);
        errdefer table.deinit();
        table.count = count;
        table.id_source = .{ .context = &Self.context, .function = Self.id };
        table.drawn_in = mod.BuildScope.shared().stamp();
        const columns = [_]mod.TableColumn{ .{ .title = "A", .width = 100 }, .{ .title = "B", .width = 100 }, .{ .title = "C", .width = 100 } };
        try table.layOut(&columns, null);
        return table;
    }
};

test "a table state selects rows by ID with clicks, Command and Shift" {
    var state = try TestIds.state(1_000_000);
    defer state.deinit();
    state.select(5);
    try std.testing.expect(state.isRowSelected(5));
    try std.testing.expect(!state.isRowSelected(6));
    // Shift extends from the anchor, in place of the selection, as a span.
    state.extend(8);
    for (5..9) |row| try std.testing.expect(state.isRowSelected(row));
    try std.testing.expectEqual(TableSpan{ .first = 5, .last = 8 }, state.span.?);
    try std.testing.expectEqual(@as(usize, 0), state.ids.count());
    state.extend(3);
    try std.testing.expect(state.isRowSelected(3) and state.isRowSelected(5) and !state.isRowSelected(6));
    // Command toggles one row and moves the anchor.
    state.toggle(20);
    try std.testing.expect(state.isRowSelected(20));
    state.toggle(4);
    try std.testing.expect(!state.isRowSelected(4));
    try std.testing.expectEqual(@as(?usize, 4), state.anchor);
}

test "a table state selects a million rows with Command-A at no cost, and takes rows out of it" {
    var state = try TestIds.state(1_000_000);
    defer state.deinit();
    state.selectAll();
    try std.testing.expect(state.all);
    try std.testing.expectEqual(@as(usize, 0), state.ids.count());
    try std.testing.expect(state.isRowSelected(999_999));
    state.toggle(7);
    try std.testing.expect(!state.isRowSelected(7));
    try std.testing.expect(state.isSelectedId(1008));
    try std.testing.expectEqual(@as(usize, 1), state.excluded.count());
    // A plain click starts again.
    state.select(2);
    try std.testing.expect(!state.all and state.isRowSelected(2) and !state.isRowSelected(3));
}

test "a table state keeps its IDs through a re-sort and forgets the positions" {
    var state = try TestIds.state(100);
    defer state.deinit();
    state.select(10);
    state.extend(12);
    state.invalidate();
    try std.testing.expect(state.cursor == null and state.anchor == null);
    try std.testing.expect(state.isSelectedId(1010) and state.isSelectedId(1012));
    // Without IDs, the selected row is a position, and goes with it.
    state.id_source = null;
    state.select(3);
    try std.testing.expect(state.isRowSelected(3));
    state.extend(9);
    try std.testing.expect(state.isRowSelected(9) and !state.isRowSelected(3));
    state.invalidate();
    try std.testing.expect(!state.isRowSelected(9));
}

test "a table state's keys move the cursor and reveal it both ways" {
    var state = try TestIds.state(1000);
    defer state.deinit();
    state.mode = .cell;
    state.scroll.viewport_height = 240;
    state.scroll.viewport_width = 150;
    try std.testing.expect(state.handleKey(.{ .name = .down }));
    try std.testing.expectEqual(TableCell{ .row = 0, .column = 0 }, state.cursor.?);
    try std.testing.expect(state.handleKey(.{ .name = .right }));
    try std.testing.expect(state.handleKey(.{ .name = .right }));
    try std.testing.expectEqual(@as(usize, 2), state.cursor.?.column);
    // The third column ends at 8 + 3 × 100 = 308, the columns abutting; the view is 150 wide.
    try std.testing.expectEqual(@as(f32, 308 + 8 - 150), state.scroll.offset_x);
    try std.testing.expect(state.handleKey(.{ .name = .pageDown }));
    try std.testing.expectEqual(@as(usize, 9), state.cursor.?.row);
    try std.testing.expect(state.handleKey(.{ .name = .end }));
    try std.testing.expectEqual(@as(usize, 999), state.cursor.?.row);
    try std.testing.expectEqual(@as(f32, 1000 * 24 - 240), state.scroll.offset);
    try std.testing.expect(state.handleKey(.{ .name = .escape }));
    try std.testing.expect(state.cursor == null);
    try std.testing.expect(!state.handleKey(.{ .name = .escape }));
    // ⇧-arrows extend a row selection.
    state.mode = .row;
    state.select(4);
    try std.testing.expect(state.handleKey(.{ .name = .down, .shift = true }));
    try std.testing.expect(state.isRowSelected(4) and state.isRowSelected(5));
    try std.testing.expect(state.handleKey(.{ .char = 'a', .command = true }));
    try std.testing.expect(state.all);
}

test "a table state sorts in a column's first order, then flips it" {
    var state = try TestIds.state(10);
    defer state.deinit();
    state.select(3);
    state.tapHeader(2 * 1);
    try std.testing.expectEqual(mod.SortColumn{ .index = 1, .order = .forward }, state.sort);
    try std.testing.expect(state.cursor == null);
    state.tapHeader(2 * 1);
    try std.testing.expectEqual(mod.SortOrder.reverse, state.sort.order);
    state.tapHeader(2 * 2 + 1);
    try std.testing.expectEqual(mod.SortColumn{ .index = 2, .order = .reverse }, state.sort);
}

test "a table state keeps the header level with the rows, whichever moved" {
    var state = TableState.init(std.testing.allocator);
    defer state.deinit();
    state.scroll.offset_x = 40;
    state.syncSideways();
    try std.testing.expectEqual(@as(f32, 40), state.header_scroll.offset_x);
    state.header_scroll.offset_x = 90;
    state.syncSideways();
    try std.testing.expectEqual(@as(f32, 90), state.scroll.offset_x);
}

test "a table state lays out shared columns and drags one edge" {
    var state = TableState.init(std.testing.allocator);
    defer state.deinit();
    const columns = [_]mod.TableColumn{ .{ .title = "Fixed", .width = 100 }, .{ .title = "A" }, .{ .title = "B", .min_width = 150 } };
    // 400 of room less 8 at each end and the fixed 100 leaves 284: 142 each
    // would put B under 150, so B holds 150 and A takes the 134 left.
    try state.layOut(&columns, 400);
    try std.testing.expectEqualSlices(f32, &.{ 100, 134, 150 }, state.laid_out.items);
    state.pressEdge(0);
    defer mod.PointerInput.shared().endDrag();
    state.drag(30);
    try std.testing.expectEqual(@as(?f32, 130), state.columnWidth(0));
    state.drag(-200);
    try std.testing.expectEqual(@as(?f32, 40), state.columnWidth(0));
    try state.layOut(&columns, 400);
    try std.testing.expectEqual(@as(f32, 40), state.laid_out.items[0]);
    state.resetWidths();
    try std.testing.expectEqual(@as(?f32, null), state.columnWidth(0));
}

test "a table state without multiple selection keeps one row, by ID" {
    var state = try TestIds.state(100);
    defer state.deinit();
    state.multiple = false;
    state.select(3);
    state.extend(6);
    try std.testing.expect(state.isRowSelected(6) and !state.isRowSelected(3));
    state.toggle(8);
    try std.testing.expect(state.isRowSelected(8) and !state.isRowSelected(6));
    try std.testing.expect(!state.handleKey(.{ .char = 'a', .command = true }));
    try std.testing.expect(!state.all);
    // Still by ID: a re-sort keeps it.
    state.invalidate();
    try std.testing.expect(state.isSelectedId(1008));
}

test "a table state gives a row selected before it had IDs its ID once it has them" {
    var state = TableState.init(std.testing.allocator);
    defer state.deinit();
    state.select(4);
    try std.testing.expect(state.pending_id);
    state.count = 10;
    state.id_source = .{ .context = &TestIds.context, .function = TestIds.id };
    state.drawn_in = mod.BuildScope.shared().stamp();
    state.settleIds();
    try std.testing.expect(state.isSelectedId(1004) and state.isRowSelected(4));
    try std.testing.expect(!state.pending_id);
}

test "a table state holds a range of a million rows as a span, and takes rows out of it" {
    var state = try TestIds.state(1_000_000);
    defer state.deinit();
    state.select(0);
    state.extend(999_999);
    try std.testing.expectEqual(@as(usize, 0), state.ids.count());
    try std.testing.expect(state.isRowSelected(500_000) and state.isRowSelected(999_999));
    try std.testing.expect(state.hasSelection());
    // Command takes a row out of the span, and puts it back.
    state.toggle(10);
    try std.testing.expect(!state.isRowSelected(10) and state.isRowSelected(11));
    try std.testing.expectEqual(@as(usize, 1), state.excluded.count());
    state.toggle(10);
    try std.testing.expect(state.isRowSelected(10));
    // A row past the span is added by ID.
    state.select(5);
    state.extend(7);
    state.toggle(9);
    try std.testing.expect(state.isRowSelected(9) and !state.isRowSelected(8));
}

/// Row IDs that follow the state's sort, as an app's re-sorted rows do: row
/// `i` has ID `i`, or `99 - i` once sorted in reverse.
const SortedIds = struct {
    const Self = @This();

    /// The ID of a row in the state's current order.
    ///
    /// - `context`: the state.
    /// - `row`: the row's position.
    /// - Returns: the row's ID.
    fn id(context: *const anyopaque, row: usize) u64 {
        const state: *const TableState = @ptrCast(@alignCast(context));
        return if (state.sort.index >= 0 and state.sort.order == .reverse) 99 - row else row;
    }
};

test "a table state turns a range into the IDs of its rows before a sort reorders them" {
    var state = TableState.init(std.testing.allocator);
    defer state.deinit();
    state.count = 100;
    state.id_source = .{ .context = &state, .function = SortedIds.id };
    state.drawn_in = mod.BuildScope.shared().stamp();
    state.select(2);
    state.extend(5);
    state.toggle(3);
    // The first column's first order is reverse: IDs read after the sort would be 94 to 97.
    state.tapHeader(1);
    try std.testing.expect(state.span == null);
    try std.testing.expect(state.isSelectedId(2) and state.isSelectedId(4) and state.isSelectedId(5));
    try std.testing.expect(!state.isSelectedId(3) and !state.isSelectedId(97));
    try std.testing.expectEqual(@as(usize, 0), state.excluded.count());
    // In the new order, ID 2 is row 97.
    try std.testing.expect(state.isRowSelected(97) and !state.isRowSelected(2));
}

test "a table state gives back a large range's memory when the selection empties" {
    var state = try TestIds.state(20_000);
    defer state.deinit();
    state.select(0);
    state.extend(19_999);
    state.invalidate();
    try std.testing.expectEqual(@as(usize, 20_000), state.ids.count());
    state.select(3);
    try std.testing.expect(state.ids.capacity() <= TableState.retained_ids);
    try std.testing.expect(state.isSelectedId(1003));
}

test "a table state the last frame did not draw calls nothing of the app's" {
    var state = try TestIds.state(100);
    defer state.deinit();
    state.select(1);
    state.extend(4);
    state.drawn_in = .{ .popover_window = false, .number = mod.BuildScope.shared().frame_number -% 1 };
    try std.testing.expect(!state.handleKey(.{ .name = .down }));
    try std.testing.expect(!state.isRowSelected(2));
    // A row selected from code waits for a frame that draws the table.
    state.select(7);
    try std.testing.expect(state.pending_id);
    // A range it can no longer read goes.
    state.extend(9);
    state.invalidate();
    try std.testing.expect(state.span == null);
}

test "a table state clears its selection with Esc while it shows no rows" {
    var state = try TestIds.state(10);
    defer state.deinit();
    state.select(3);
    state.count = 0;
    try std.testing.expect(state.handleKey(.{ .name = .escape }));
    try std.testing.expect(!state.hasSelection());
}

test "a table state drawn in the popover window takes keys through the main window's frames, until the popover window hides" {
    var state = try TestIds.state(10);
    defer state.deinit();
    const scope = mod.BuildScope.shared();
    const saved_main = scope.frame_number;
    const saved_popover = scope.popover_window_frame_number;
    defer {
        scope.frame_number = saved_main;
        scope.popover_window_frame_number = saved_popover;
    }
    state.drawn_in = .{ .popover_window = true, .number = scope.popover_window_frame_number };
    // The main window draws a frame of its own: the popover window's table still takes keys.
    scope.frame_number +%= 1;
    try std.testing.expect(state.handleKey(.{ .name = .down }));
    try std.testing.expect(state.isRowSelected(0));
    scope.forgetPopoverWindow();
    try std.testing.expect(!state.handleKey(.{ .name = .down }));
}

test "a table state's sharing columns split what columns held at their minimum leave" {
    var state = TableState.init(std.testing.allocator);
    defer state.deinit();
    const columns = [_]mod.TableColumn{ .{ .title = "A", .min_width = 200 }, .{ .title = "B" }, .{ .title = "C", .min_width = 120 }, .{ .title = "D" } };
    // 500 less 8 at each end leaves 484: 121 each holds A at 200, then 94
    // each holds C at 120, and B and D split the 164 left.
    try state.layOut(&columns, 500);
    try std.testing.expectEqualSlices(f32, &.{ 200, 82, 120, 82 }, state.laid_out.items);
    // Room enough, and every column shares equally, the last taking the remainder.
    try state.layOut(&columns, 1043);
    try std.testing.expectEqualSlices(f32, &.{ 256, 256, 256, 259 }, state.laid_out.items);
    // Too little for the minimums: those hold, the rest at theirs, and the table overflows.
    try state.layOut(&columns, 300);
    try std.testing.expectEqualSlices(f32, &.{ 200, 40, 120, 40 }, state.laid_out.items);
}
