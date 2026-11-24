//! A table: a header over rows, built only while in view and scrolling both
//! ways, or laid out whole at its rows' height, with sortable and resizable
//! columns and row or cell selection.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_table);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// How a `Table` is measured and drawn: as a `Table` is, its rows and
/// header as tall as their text and 5 points above and below it, its columns
/// abutting, the text inset from a resize edge.
const TableLook = struct {
    const Self = @This();

    /// How many times its size a line of the bundled text face (Inter) is
    /// tall: its `hhea` ascent less descent, and no gap, over its units per
    /// em, as `TextShaper.lineHeight` measures (text cannot be measured while
    /// views are built; a test checks it against the face).
    const line_ratio: f32 = 2478.0 / 2048.0;
    /// The room above and below a row's or the header's text.
    const vertical_padding: f32 = 5;
    /// How tall a resize edge's hairline is, so the header's row is at least that.
    const edge_height: f32 = 14;
    /// What an accessory row adds to the header beside the theme's control
    /// height: the gap above it and room below.
    const accessory_extra: f32 = 8;
    /// How wide a column's resize edge is to press, inside the column at its
    /// trailing edge, where its hairline is.
    const edge_grab: f32 = 8;
    /// How far a resizable table's text keeps from a column edge.
    const edge_gap: f32 = 6;

    /// A row's height when the app gives none: a line of the theme's body
    /// text and the room above and below it, as a `Table` row is.
    ///
    /// - `theme`: the theme the table draws with.
    /// - Returns: the height, in points.
    fn rowHeight(theme: renderer.Theme) f32 {
        return theme.typography.body.size * line_ratio + 2 * vertical_padding;
    }

    /// The header's height when the app gives none: a line of the theme's
    /// subheadline (or a resize edge, if taller) and the room around it, and
    /// with accessories the theme's control height and their gap too.
    ///
    /// - `theme`: the theme the table draws with.
    /// - `accessory`: whether a view sits under each title.
    /// - Returns: the height, in points.
    fn headerHeight(theme: renderer.Theme, accessory: bool) f32 {
        const titles = @max(theme.typography.subheadline.size * line_ratio, edge_height) + 2 * vertical_padding;
        return if (accessory) titles + accessory_extra + theme.metrics.control_height else titles;
    }

    /// How far a column's text keeps from its edges: in a resizable table,
    /// `edge_gap` from each edge between columns, none at the table's ends;
    /// none at all otherwise, as a `Table`'s.
    ///
    /// - `column`: the column.
    /// - `count`: how many columns.
    /// - `resizable`: whether the table's columns resize.
    /// - Returns: the insets.
    fn insets(column: usize, count: usize, resizable: bool) renderer.EdgeInsets {
        if (!resizable) return .{};
        return .{
            .leading = if (column > 0) edge_gap else 0,
            .trailing = if (column + 1 < count) edge_gap else 0,
        };
    }

    /// A cell's content in its column: inset from the edges, as wide as the
    /// column, pinned to its leading edge (or trailing). A stack carries the
    /// frame, so the content's own frame and padding stay its own.
    ///
    /// - `content`: the cell's view.
    /// - `width`: the column's width.
    /// - `trailing`: pins the content to the trailing edge.
    /// - `edges`: how far the content keeps from the edges.
    /// - Returns: the cell.
    fn framed(content: mod.View, width: f32, trailing: bool, edges: renderer.EdgeInsets) mod.View {
        const sized = mod.HStack(.{content}).spacing(0).paddingInsets(edges).frameWidth(width);
        return if (trailing) sized.frameAlign(.trailing) else sized.frameAlign(.leading);
    }
};

/// What one `Table` builds from, in the build arena: the app's rows and
/// the state, for a context of `T`.
///
/// - `T`: the app's context type.
/// - `cellFn`: makes a cell.
/// - `idFn`: gives a row's ID, or null for a table without IDs.
/// - Returns: the model type.
fn TableModel(comptime T: type, comptime cellFn: fn (*const T, usize, usize) mod.View, comptime idFn: ?fn (*const T, usize) u64) type {
    return struct {
        const Self = @This();

        /// The app's context.
        context: *const T,
        /// The columns.
        columns: []const mod.TableColumn,
        /// How many rows.
        count: usize,
        /// The table's state: the app's, or one in the build arena for a
        /// table that keeps nothing (`kept` false).
        state: *mod.TableState,
        /// Whether `state` is the app's, so the table selects, sorts and
        /// resizes; false for a table given no state.
        kept: bool,
        /// The options.
        options: mod.TableOptions(T),
        /// Each row's height: the options', else a `Table` row's.
        row_height: f32,
        /// The header's height: the options', else a `Table` header's.
        header_height: f32,

        /// Hands the state what its handlers need this frame, and keeps the
        /// header level with the rows.
        ///
        /// - `self`: the model.
        fn record(self: *const Self) void {
            const state = self.state;
            state.drawn_in = mod.BuildScope.shared().stamp();
            state.syncSideways();
            state.count = self.count;
            state.mode = self.options.selection_mode;
            state.multiple = self.options.multiple_selection;
            state.row_height = self.row_height;
            state.on_activate = self.options.on_activate;
            state.on_sort = self.options.on_sort;
            state.on_selection = self.options.on_selection;
            state.id_source = if (idFn != null) .{ .context = self.context, .function = Self.rowId } else null;
            if (state.cursor) |cursor| {
                if (cursor.row >= self.count) state.cursor = null;
            }
            state.settleIds();
        }

        /// Whether some column shares the pane's width, so the layout needs the pane's size.
        ///
        /// - `self`: the model.
        /// - Returns: true when a column has no width and was never dragged.
        fn shares(self: *const Self) bool {
            for (self.columns, 0..) |column, index| {
                if (column.width == null and self.state.columnWidth(index) == null) return true;
            }
            return false;
        }

        /// The table at a size `GeometryReader` gives it.
        ///
        /// - `self`: the model.
        /// - `size`: the room the table has.
        /// - Returns: the table.
        fn sized(self: *const Self, size: renderer.Size) mod.View {
            return self.build(size.width).frame(size.width, size.height);
        }

        /// The table: the header, a divider, and the rows (or the empty view).
        ///
        /// - `self`: the model.
        /// - `room`: the pane's width, or null when no column shares it.
        /// - Returns: the table.
        fn build(self: *const Self, room: ?f32) mod.View {
            self.state.layOut(self.columns, room) catch @panic("oom");
            if (self.options.layout == .fitted) return self.fitted();
            const rows = if (self.count == 0)
                (self.options.empty orelse mod.Empty()).frameMaxWidth().frameMaxHeight()
            else
                mod.VirtualListBoth(Self, self, self.count, self.row_height, &self.state.scroll, Self.row, 0);
            if (!self.options.column_headers.shows()) return rows.frameMaxWidth().frameMaxHeight();
            // A wheel up or down over the header scrolls the rows: the header
            // itself has nothing to scroll that way.
            var titles = mod.ScrollViewStateBoth(&self.state.header_scroll, self.header());
            titles.kind.scrollState.vertical_target = &self.state.scroll;
            return mod.VStack(.{
                // No scroll bar of its own: the rows' scrolls sideways and the
                // header follows, and a bar along its foot would take the
                // presses meant for the titles and their edges.
                titles.scrollIndicators(.hidden).frameHeight(self.header_height).frameMaxWidth(),
                mod.Divider(),
                rows,
            }).spacing(0).frameMaxWidth().frameMaxHeight();
        }

        /// The table laid out whole (`.fitted`): the header, a divider and
        /// every row, as tall as they are, nothing scrolled, at the pane's
        /// leading edge. `empty` shows nothing here.
        ///
        /// - `self`: the model.
        /// - Returns: the table.
        fn fitted(self: *const Self) mod.View {
            const rows = mod.BuildScope.shared().allocator().alloc(mod.View, self.count) catch @panic("oom");
            for (rows, 0..) |*shown, index| shown.* = self.row(index).frameHeight(self.row_height);
            const body = mod.StackBuilder.fromSlice(.vertical, 0, .leading, rows).frameMaxWidth();
            if (!self.options.column_headers.shows()) return body;
            return mod.VStack(.{
                self.header().frameHeight(self.header_height).frameMaxWidth().frameAlign(.leading),
                mod.Divider(),
                body,
            }).spacing(0).frameMaxWidth();
        }

        /// How tall a fitted table is: its header and divider, when shown,
        /// and every row.
        ///
        /// - `self`: the model.
        /// - Returns: the height, in points.
        fn fittedHeight(self: *const Self) f32 {
            const rows = @as(f32, @floatFromInt(self.count)) * self.row_height;
            if (!self.options.column_headers.shows()) return rows;
            return self.header_height + mod.BuildScope.shared().theme().metrics.hairline + rows;
        }

        /// The header row: each column's title (and accessory), the columns
        /// abutting as the rows' do, the text 5 points from the top.
        ///
        /// - `self`: the model.
        /// - Returns: the header.
        fn header(self: *const Self) mod.View {
            const cells = mod.BuildScope.shared().allocator().alloc(mod.View, self.columns.len) catch @panic("oom");
            for (cells, 0..) |*header_cell, index| header_cell.* = self.headerCell(index);
            return mod.StackBuilder.fromSlice(.horizontal, 0, .center, cells)
                .paddingInsets(.{ .top = TableLook.vertical_padding, .leading = mod.TableState.side_inset, .bottom = TableLook.vertical_padding, .trailing = mod.TableState.side_inset });
        }

        /// A column's header: its title in the label color (the accent, and
        /// the order's chevron, while sorted by it), a rounded hover fill and
        /// a tap that sorts on a sortable column, the edge a press drags with
        /// its hairline between columns, and the accessory under them.
        ///
        /// - `self`: the model.
        /// - `index`: the column.
        /// - Returns: the cell, as wide as the column.
        fn headerCell(self: *const Self, index: usize) mod.View {
            const tokens = mod.BuildScope.shared().tokens();
            const column = self.columns[index];
            const width = self.state.laid_out.items[index];
            const edges = TableLook.insets(index, self.columns.len, self.options.resizable);
            // A table given no state sorts nothing: there is no `sort` to keep.
            const sortable = column.sortable and self.kept;
            const active = sortable and self.state.sort.index == @as(i64, @intCast(index));
            const label = mod.Text(column.title).font(.subheadline).truncated().foregroundStyle(if (active) tokens.accent else tokens.label);
            // `StackBuilder.fromSlice` keeps the slice, so it lives in the build arena.
            const parts = mod.BuildScope.shared().allocator().alloc(mod.View, if (active) 2 else 1) catch @panic("oom");
            parts[0] = label;
            if (active) parts[1] = mod.Icon(if (self.state.sort.order == .forward) mod.IconName.chevronUp else mod.IconName.chevronDown, 10, tokens.accent);
            var title = TableLook.framed(mod.StackBuilder.fromSlice(.horizontal, 4, .center, parts), width, column.trailing, edges);
            if (sortable) {
                const tag = index * 2 + @intFromBool(column.first_order == .reverse);
                title = title.cornerRadius(5).hoverFill(tokens.hover).onTapGesture(mod.Callback.tagged(mod.TableState, self.state, mod.TableState.tapHeader, tag));
            }
            if (column.help) |hint| title = title.help(hint);
            // The edge a press drags lies over the title's trailing side, its
            // hairline on the column's edge, none after the last column (as a
            // `Table` draws it); drawn after the title, it takes the presses it covers.
            const last = index + 1 == self.columns.len;
            const titled = if (self.options.resizable) mod.ZStack(.{
                title,
                mod.HStack(.{
                    mod.Spacer(),
                    if (last) mod.Empty() else mod.Rectangle(tokens.tertiary_label).frame(1, TableLook.edge_height),
                }).spacing(0)
                    .frame(TableLook.edge_grab, TableLook.edge_height)
                    .onTapGesture(mod.Callback.tagged(mod.TableState, self.state, mod.TableState.pressEdge, index))
                    .pointerStyle(.columnResize),
            }).alignment(.trailing).frameWidth(width) else title;
            const accessory = self.options.header_accessory orelse return titled;
            // Under the title, inset as the column's text is.
            return mod.VStack(.{ titled, TableLook.framed(accessory(self.context, index), width, false, edges) }).spacing(4).frameWidth(width);
        }

        /// One row, for the virtual list: its cells framed to the abutting
        /// columns, striped, and as a `Table` draws a selected row, filled in
        /// the selection color with its text on the accent; a row the app
        /// highlights (a find's match) takes the selection color lightly.
        ///
        /// - `self`: the model.
        /// - `index`: the row's position.
        /// - Returns: the row.
        fn row(self: *const Self, index: usize) mod.View {
            const tokens = mod.BuildScope.shared().tokens();
            const cells = mod.BuildScope.shared().allocator().alloc(mod.View, self.columns.len) catch @panic("oom");
            for (cells, 0..) |*row_cell, column| row_cell.* = self.cell(index, column);
            var view = mod.StackBuilder.fromSlice(.horizontal, 0, .center, cells)
                .paddingInsets(.{ .top = 0, .leading = mod.TableState.side_inset, .bottom = 0, .trailing = mod.TableState.side_inset })
                .frameMaxWidth()
                .frameMaxHeight();
            const highlighted = if (self.options.highlighted) |marks| marks(self.context, index) else false;
            if (self.state.isRowSelected(index)) {
                view = view.background(tokens.selection).foregroundStyle(tokens.on_accent);
            } else if (highlighted) {
                view = view.background(tokens.selection.withAlpha(0.22));
            } else if (index % 2 == 1) {
                view = view.background(tokens.row_stripe);
            }
            // A table narrower than the pane keeps to the leading edge, under its header.
            return view.frameAlign(.leading);
        }

        /// One cell: the app's view framed to its column and as tall as the
        /// row, filled and outlined while it is the focused cursor, and tappable.
        ///
        /// - `self`: the model.
        /// - `index`: the row's position.
        /// - `column`: the column.
        /// - Returns: the cell.
        fn cell(self: *const Self, index: usize, column: usize) mod.View {
            const tokens = mod.BuildScope.shared().tokens();
            const content = cellFn(self.context, index, column);
            const edges = TableLook.insets(column, self.columns.len, self.options.resizable);
            // As tall as the row, so a press anywhere on the row lands on a cell.
            var framed = TableLook.framed(content, self.state.laid_out.items[column], self.columns[column].trailing, edges).frameMaxHeight();
            // The cursor fills its whole cell, as a spreadsheet's does.
            if (self.state.focused and self.state.isCursor(index, column)) framed = framed.background(tokens.accent_soft).border(tokens.focus_ring, 1);
            // A table given no state takes no taps: there is nothing to select into.
            if (!self.kept) return framed;
            return framed.onTapGesture(mod.Callback.tagged(mod.TableState, self.state, mod.TableState.tapCell, index * self.columns.len + column));
        }

        /// A row's ID, for the state's handlers.
        ///
        /// - `context`: the app's context.
        /// - `index`: the row's position.
        /// - Returns: the row's ID.
        fn rowId(context: *const anyopaque, index: usize) u64 {
            return idFn.?(@ptrCast(@alignCast(context)), index);
        }
    };
}

/// A table (SwiftUI's `Table`, which is lazy). Scrolling (`.scrolling`, the
/// default), a fixed header over rows built only while in view
/// (`VirtualListBoth`), scrolling both ways with the header kept level, as
/// big as it is given; fitted (`.fitted`), every row built and the table as
/// tall as they are, nothing scrolled, for a short table inside a larger pane.
/// `column_headers = .hidden` leaves the rows alone. A sortable header sorts
/// on a tap (`state.sort`, then `on_sort`; the app re-sorts its rows); a
/// header's trailing edge drags the column wider or narrower, the table
/// growing with it. Rows are selected by ID (`idFn`) with taps, ⌘/⇧ taps and
/// the keys (`state.handleKey`); a double click or Enter activates a row.
///
/// A fitted table never resizes its columns: it scrolls nothing, so a column
/// dragged past its pane could not be reached. Given no `state`, the table
/// keeps nothing between frames: it is fitted, selects and sorts nothing, and
/// lays its columns out in the build arena. Rows of text read through a
/// `TableRows`.
///
/// The app keeps its rows: `cellFn` is asked only for the cells built. Columns
/// without a width share the pane's width, so such a table lays out at paint
/// time (`GeometryReader`, framed to a fitted table's height).
///
/// - `T`: the app's context type.
/// - `context`: the app's context, handed to `cellFn` and `idFn`.
/// - `columns`: the columns.
/// - `count`: how many rows.
/// - `cellFn`: makes the cell at a row's position and a column's index.
/// - `idFn`: gives a row's ID, or null for a table without (one row selects, by position).
/// - `state`: the table's state, app-owned at a stable address; null for a
///   table that keeps nothing.
/// - `options`: how it lays out, selects, sorts and draws its header.
/// - Returns: the table: as big as it is given, or as tall as its rows when fitted.
pub fn Table(
    comptime T: type,
    context: *const T,
    columns: []const mod.TableColumn,
    count: usize,
    comptime cellFn: fn (*const T, usize, usize) mod.View,
    comptime idFn: ?fn (*const T, usize) u64,
    state: ?*mod.TableState,
    options: mod.TableOptions(T),
) mod.View {
    const Model = TableModel(T, cellFn, idFn);
    const arena = mod.BuildScope.shared().allocator();
    const model = arena.create(Model) catch @panic("oom");
    const theme = mod.BuildScope.shared().theme();
    // Given no state, the table keeps one for this frame in the build arena:
    // fitted, selecting and resizing nothing (sorting nothing either, `kept`).
    var shown = options;
    const kept = state orelse blk: {
        shown.layout = .fitted;
        shown.selection_mode = .none;
        shown.resizable = false;
        const frame_state = arena.create(mod.TableState) catch @panic("oom");
        frame_state.* = .{ .allocator = arena };
        break :blk frame_state;
    };
    // A fitted table scrolls nothing, so a column dragged past its pane
    // could never be reached: it does not resize.
    if (shown.layout == .fitted) shown.resizable = false;
    model.* = .{
        .context = context,
        .columns = columns,
        .count = count,
        .state = kept,
        .kept = state != null,
        .options = shown,
        .row_height = shown.row_height orelse TableLook.rowHeight(theme),
        .header_height = shown.header_height orelse TableLook.headerHeight(theme, shown.header_accessory != null),
    };
    model.record();
    if (!model.shares()) return model.build(null);
    const reader = mod.GeometryReader(Model, model, Model.sized);
    // A fitted table's height is known (its rows'), so only its width is read.
    return if (shown.layout == .fitted) reader.frameHeight(model.fittedHeight()).frameMaxWidth() else reader;
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

/// Rows for the tests: each cell says nothing much, and the cells of the
/// first column count themselves.
const TestRows = struct {
    const Self = @This();

    /// How many first-column cells were built.
    built: *usize,

    /// A cell.
    ///
    /// - `self`: the rows.
    /// - `row`: the row's position.
    /// - `column`: the column.
    /// - Returns: the cell.
    fn cell(self: *const Self, row: usize, column: usize) mod.View {
        _ = row;
        if (column == 0) self.built.* += 1;
        return mod.Text("cell");
    }

    /// A row's ID: its position plus 1.
    ///
    /// - `self`: the rows.
    /// - `row`: the row's position.
    /// - Returns: the ID.
    fn id(self: *const Self, row: usize) u64 {
        _ = self;
        return row + 1;
    }

    /// An accessory: a button that counts its taps in `built`.
    ///
    /// - `self`: the rows.
    /// - `column`: the column.
    /// - Returns: the accessory.
    fn accessory(self: *const Self, column: usize) mod.View {
        _ = column;
        return mod.Button("Filter", mod.Callback.init(usize, self.built, Self.bump));
    }

    /// Counts a tap.
    ///
    /// - `count`: the counter.
    fn bump(count: *usize) void {
        count.* += 1000;
    }
};

/// Counts what the table told the app, for the tests.
const TestProbe = struct {
    const Self = @This();

    /// The last row activated.
    activated: ?usize = null,
    /// How many sorts were asked for.
    sorts: usize = 0,

    /// Records an activation.
    ///
    /// - `self`: the probe.
    /// - `row`: the row.
    fn activate(self: *Self, row: usize) void {
        self.activated = row;
    }

    /// Records a sort.
    ///
    /// - `self`: the probe.
    fn sort(self: *Self) void {
        self.sorts += 1;
    }
};

/// The tests' columns: two sortable (the second first sorting in reverse), all fixed.
const test_columns = [_]mod.TableColumn{
    .{ .title = "Name", .width = 120, .sortable = true },
    .{ .title = "Size", .width = 80, .sortable = true, .trailing = true, .first_order = .reverse },
    .{ .title = "Kind", .width = 100 },
};

test "a table builds only the rows in view, and taps select by ID with Command and Shift" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    defer mod.PointerInput.shared().setClickModifiers(false, false);
    defer mod.PointerInput.shared().setTapCount(1);
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();
    var probe: TestProbe = .{};

    window.begin(renderer.MacosTheme.light);
    const view = Table(TestRows, &rows, &test_columns, 100_000, TestRows.cell, TestRows.id, &state, .{ .on_activate = mod.IndexCallback.init(TestProbe, &probe, TestProbe.activate) });
    window.end();
    var first = try window.render(view, 400, 300);
    first.deinit();
    // Once the viewport is known, a 300-point table builds about a dozen of its 100,000 rows.
    built = 0;
    window.begin(renderer.MacosTheme.light);
    const again = Table(TestRows, &rows, &test_columns, 100_000, TestRows.cell, TestRows.id, &state, .{ .on_activate = mod.IndexCallback.init(TestProbe, &probe, TestProbe.activate) });
    window.end();
    var frame = try window.render(again, 400, 300);
    defer frame.deinit();
    try std.testing.expect(built > 5 and built < 25);
    try std.testing.expectEqual(@as(f32, 120), state.laid_out.items[0]);

    // Rows start under the header and its divider, a `Table` row's height apart.
    const pitch = TableLook.rowHeight(renderer.MacosTheme.light);
    const row_two = TableLook.headerHeight(renderer.MacosTheme.light, false) + renderer.MacosTheme.light.metrics.hairline + 2 * pitch + pitch / 2;
    try std.testing.expect(window.tap(.{ .x = 40, .y = row_two }));
    try std.testing.expect(state.isSelectedId(3));
    mod.PointerInput.shared().setClickModifiers(true, false);
    try std.testing.expect(window.tap(.{ .x = 40, .y = row_two + 2 * pitch }));
    try std.testing.expect(state.isRowSelected(2) and state.isRowSelected(3) and state.isRowSelected(4));
    mod.PointerInput.shared().setClickModifiers(false, true);
    try std.testing.expect(window.tap(.{ .x = 40, .y = row_two + pitch }));
    try std.testing.expect(!state.isRowSelected(3) and state.isRowSelected(4));
    try std.testing.expect(state.focused);

    // A double click (a second press on the same row) activates it.
    mod.PointerInput.shared().setClickModifiers(false, false);
    try std.testing.expect(window.tap(.{ .x = 40, .y = row_two }));
    try std.testing.expectEqual(@as(?usize, null), probe.activated);
    mod.PointerInput.shared().setTapCount(2);
    try std.testing.expect(window.tap(.{ .x = 40, .y = row_two }));
    try std.testing.expectEqual(@as(?usize, 2), probe.activated);
}

test "a table sorts on a header tap in the column's first order, and tells the app" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();
    var probe: TestProbe = .{};
    const options: mod.TableOptions(TestRows) = .{ .on_sort = mod.Callback.init(TestProbe, &probe, TestProbe.sort) };

    window.begin(renderer.MacosTheme.light);
    var view = Table(TestRows, &rows, &test_columns, 10, TestRows.cell, TestRows.id, &state, options);
    window.end();
    var frame = try window.render(view, 400, 300);
    frame.deinit();
    // "Size" starts at 8 + 120, the columns abutting: its first tap sorts in reverse.
    try std.testing.expect(window.tap(.{ .x = 150, .y = 15 }));
    try std.testing.expectEqual(mod.SortColumn{ .index = 1, .order = .reverse }, state.sort);
    try std.testing.expectEqual(@as(usize, 1), probe.sorts);

    window.begin(renderer.MacosTheme.light);
    view = Table(TestRows, &rows, &test_columns, 10, TestRows.cell, TestRows.id, &state, options);
    window.end();
    frame = try window.render(view, 400, 300);
    frame.deinit();
    try std.testing.expect(window.tap(.{ .x = 150, .y = 15 }));
    try std.testing.expectEqual(mod.SortOrder.forward, state.sort.order);
    // "Kind" does not sort: a tap on its title leaves the sort on "Size".
    _ = window.tap(.{ .x = 270, .y = 15 });
    try std.testing.expectEqual(mod.SortColumn{ .index = 1, .order = .forward }, state.sort);
    try std.testing.expectEqual(@as(usize, 2), probe.sorts);
}

test "a table's header edge drags its column wider, and the table with it" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    // A failed expect must not leave a drag armed on this stack's state.
    defer mod.PointerInput.shared().endDrag();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();

    window.begin(renderer.MacosTheme.light);
    var view = Table(TestRows, &rows, &test_columns, 10, TestRows.cell, TestRows.id, &state, .{});
    window.end();
    var frame = try window.render(view, 300, 300);
    frame.deinit();
    // The first column ends at 8 + 120; its edge spans the 8 points before, and a press on it arms the drag,
    // low in the header of a table wider than its pane, where a header scroll bar once took it.
    try std.testing.expect(window.tap(.{ .x = 124, .y = 12 }));
    mod.PointerInput.shared().drag(window.hits.items, .{ .x = 184, .y = 12 });
    try std.testing.expectEqual(@as(?f32, 180), state.columnWidth(0));
    mod.PointerInput.shared().endDrag();

    window.begin(renderer.MacosTheme.light);
    view = Table(TestRows, &rows, &test_columns, 10, TestRows.cell, TestRows.id, &state, .{});
    window.end();
    frame = try window.render(view, 300, 300);
    frame.deinit();
    try std.testing.expectEqual(@as(f32, 180), state.laid_out.items[0]);
    // The rows grew with it, past the 300-point pane: 8 + 180 + 80 + 100 + 8 = 376 across.
    try std.testing.expectEqual(@as(f32, 376), state.scroll.content_width);
}

test "a table's accessories sit under the titles, and columns without a width share the pane" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();
    const columns = [_]mod.TableColumn{ .{ .title = "Name" }, .{ .title = "Size", .width = 80 } };

    window.begin(renderer.MacosTheme.light);
    const view = Table(TestRows, &rows, &columns, 0, TestRows.cell, null, &state, .{ .header_accessory = TestRows.accessory, .selection_mode = .cell });
    window.end();
    var frame = try window.render(view, 400, 300);
    defer frame.deinit();
    // 400 less the 8 at each end and the fixed 80.
    try std.testing.expectEqual(@as(f32, 304), state.laid_out.items[0]);
    // The accessory sits under the title (5 points down, a 14-point row, a 4-point gap), inside the taller header.
    try std.testing.expect(window.tap(.{ .x = 30, .y = 5 + 14 + 4 + renderer.MacosTheme.light.metrics.control_height / 2 }));
    try std.testing.expectEqual(@as(usize, 1000), built);
}

test "a table that does not resize keeps a trailing column's title at its trailing edge" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();
    const columns = [_]mod.TableColumn{ .{ .title = "Name", .width = 120 }, .{ .title = "Size", .width = 80, .trailing = true } };

    window.begin(renderer.MacosTheme.light);
    const view = Table(TestRows, &rows, &columns, 3, TestRows.cell, TestRows.id, &state, .{ .resizable = false });
    window.end();
    var frame = try window.render(view, 400, 200);
    defer frame.deinit();
    // "Size" spans 8 + 120 = 128 to 208; trailing, its ink starts past the middle, 168.
    var leftmost: u32 = 400;
    for (2..22) |y| for (128..208) |x| {
        if (frame.at(@intCast(x), @intCast(y)).r < 0.75) leftmost = @min(leftmost, @as(u32, @intCast(x)));
    };
    try std.testing.expect(leftmost > 168 and leftmost < 208);
}

test "a table's header grows its accessory row to the theme's control height" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();

    window.begin(renderer.MuiTheme.light);
    const view = Table(TestRows, &rows, &test_columns, 10, TestRows.cell, TestRows.id, &state, .{ .header_accessory = TestRows.accessory });
    window.end();
    var frame = try window.render(view, 400, 300);
    defer frame.deinit();
    // Material's controls are 36 tall: the header is its titles' height + 8 + 36, then the divider.
    try std.testing.expect(window.tap(.{ .x = 40, .y = TableLook.headerHeight(renderer.MuiTheme.light, true) + renderer.MuiTheme.light.metrics.hairline + TableLook.rowHeight(renderer.MuiTheme.light) / 2 }));
    try std.testing.expect(state.isSelectedId(1));
}

test "a table's sortable titles start where their column's cells do" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();

    window.begin(renderer.MacosTheme.light);
    const view = Table(TestRows, &rows, &test_columns, 3, TestRows.cell, TestRows.id, &state, .{});
    window.end();
    var frame = try window.render(view, 400, 200);
    defer frame.deinit();
    // The leftmost ink of "Name" in the header and of "cell" in row 0, across the first column.
    var title_left: u32 = 400;
    var cell_left: u32 = 400;
    // The header's text above its divider, then row 0's.
    for (0..128) |x| {
        for (2..22) |y| if (frame.at(@intCast(x), @intCast(y)).r < 0.75) {
            title_left = @min(title_left, @as(u32, @intCast(x)));
        };
        for (28..48) |y| if (frame.at(@intCast(x), @intCast(y)).r < 0.75) {
            cell_left = @min(cell_left, @as(u32, @intCast(x)));
        };
    }
    // Their first glyphs' side bearings differ by a point at most; the old inset was 4.
    const apart = if (title_left > cell_left) title_left - cell_left else cell_left - title_left;
    try std.testing.expect(cell_left < 20 and apart <= 1);
}

test "a table's line ratio is the bundled face's, so its rows are as tall as a Table's" {
    const fonts = try renderer.FontSet.create(std.testing.allocator);
    defer fonts.destroy();
    const shaper = renderer.TextShaper.init(fonts.cache(.{}).face);
    for ([_]f32{ 11, 12, 13, 14 }) |size| {
        try std.testing.expectApproxEqAbs(size * TableLook.line_ratio, shaper.lineHeight(size), 0.001);
    }
    // macOS: a 13-point body line and 5 points above and below it.
    try std.testing.expectApproxEqAbs(@as(f32, 13 * 1.2099609375 + 10), TableLook.rowHeight(renderer.MacosTheme.light), 0.001);
}

test "a table draws a selected row as a Table does: the selection fill, its text on the accent" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();
    state.select(1);

    window.begin(renderer.MacosTheme.light);
    const tokens = mod.BuildScope.shared().tokens();
    const view = Table(TestRows, &rows, &test_columns, 3, TestRows.cell, TestRows.id, &state, .{});
    window.end();
    var frame = try window.render(view, 400, 200);
    defer frame.deinit();
    const pitch = TableLook.rowHeight(renderer.MacosTheme.light);
    const top = TableLook.headerHeight(renderer.MacosTheme.light, false) + renderer.MacosTheme.light.metrics.hairline;
    // Row 1's ground, right of its text, is the selection color.
    const ground = frame.at(380, @intFromFloat(top + pitch + pitch / 2));
    try std.testing.expectApproxEqAbs(tokens.selection.r, ground.r, 0.02);
    try std.testing.expectApproxEqAbs(tokens.selection.b, ground.b, 0.02);
}

/// What the tests read off a drawn frame.
const TestFrame = struct {
    const Self = @This();

    /// The lowest edge of a frame's tap regions: where a fitted table's
    /// last row ends.
    ///
    /// - `window`: the window drawn.
    /// - Returns: the lowest edge, in points; 0 with no regions.
    fn lowestTap(window: *const mod.TestWindow) f32 {
        var lowest: f32 = 0;
        for (window.hits.items) |hit| lowest = @max(lowest, hit.rect.y + hit.rect.height);
        return lowest;
    }
};

test "a fitted table builds every row and is as tall as its header and rows" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();

    window.begin(renderer.MacosTheme.light);
    const view = mod.VStack(.{ Table(TestRows, &rows, &test_columns, 40, TestRows.cell, TestRows.id, &state, .{ .layout = .fitted }), mod.Spacer() }).spacing(0);
    window.end();
    var frame = try window.render(view, 400, 300);
    defer frame.deinit();
    // Every one of its 40 rows, though only a dozen fit the window.
    try std.testing.expectEqual(@as(usize, 40), built);
    const top = TableLook.headerHeight(renderer.MacosTheme.light, false) + renderer.MacosTheme.light.metrics.hairline;
    const pitch = TableLook.rowHeight(renderer.MacosTheme.light);
    // No resize edge: a press where the first column's would be drags nothing.
    try std.testing.expect(window.tap(.{ .x = 124, .y = 12 }));
    mod.PointerInput.shared().drag(window.hits.items, .{ .x = 184, .y = 12 });
    mod.PointerInput.shared().endDrag();
    try std.testing.expectEqual(@as(?f32, null), state.columnWidth(0));
    // Its rows tap and select as a scrolling table's do, a press above a row's text too.
    try std.testing.expect(window.tap(.{ .x = 40, .y = top + pitch + pitch / 2 }));
    try std.testing.expect(state.isSelectedId(2));
    try std.testing.expect(window.tap(.{ .x = 40, .y = top + 2 * pitch + 2 }));
    try std.testing.expect(state.isSelectedId(3));
}

test "a fitted table with columns sharing the pane is as tall as its rows, and hidden headers leave the rows alone" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();
    const columns = [_]mod.TableColumn{ .{ .title = "Name" }, .{ .title = "Size", .width = 80 } };

    window.begin(renderer.MacosTheme.light);
    const view = mod.VStack(.{ Table(TestRows, &rows, &columns, 3, TestRows.cell, TestRows.id, &state, .{ .layout = .fitted, .column_headers = .hidden }), mod.Spacer() }).spacing(0);
    window.end();
    var frame = try window.render(view, 400, 300);
    defer frame.deinit();
    const pitch = TableLook.rowHeight(renderer.MacosTheme.light);
    // No header: three rows from the top, their cells as tall as they are (a press
    // anywhere on a row lands), the first column sharing what the second leaves.
    try std.testing.expectApproxEqAbs(3 * pitch, TestFrame.lowestTap(window), 0.01);
    try std.testing.expectEqual(@as(f32, 400 - 16 - 80), state.laid_out.items[0]);
    try std.testing.expect(window.tap(.{ .x = 40, .y = pitch / 2 }));
    try std.testing.expect(state.isSelectedId(1));
}

test "a table given no state is fitted and takes no taps, and its sortable header sorts nothing" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };

    window.begin(renderer.MacosTheme.light);
    // Asked to scroll, but with nothing to keep a scroll position in it is fitted.
    const view = mod.VStack(.{ Table(TestRows, &rows, &test_columns, 30, TestRows.cell, TestRows.id, null, .{}), mod.Spacer() }).spacing(0);
    window.end();
    var frame = try window.render(view, 400, 300);
    defer frame.deinit();
    try std.testing.expectEqual(@as(usize, 30), built);
    try std.testing.expectEqual(@as(usize, 0), window.hits.items.len);
    try std.testing.expect(!window.tap(.{ .x = 40, .y = 12 }));
}

test "a table over text rows shows each row's texts, nothing past a short row's end" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const texts = [_][]const []const u8{ &.{ "Ada", "36" }, &.{"Alan"} };
    const columns = [_]mod.TableColumn{ .{ .title = "Name", .width = 120 }, .{ .title = "Age", .width = 60, .trailing = true } };

    window.begin(renderer.MacosTheme.light);
    const context = mod.TableRows.of(&texts);
    try std.testing.expectEqualStrings("36", context.cell(0, 1).kind.text.string);
    try std.testing.expectEqualStrings("", context.cell(1, 1).kind.text.string);
    // A row past the last, from a count larger than the rows, is empty too.
    try std.testing.expectEqualStrings("", context.cell(5, 0).kind.text.string);
    const view = mod.TableRows.table(&texts, &columns, null, .{});
    window.end();
    var frame = try window.render(view, 300, 120);
    defer frame.deinit();
    // "36", trailing, ends at its column's end, 8 + 120 + 60 = 188.
    const top = TableLook.headerHeight(renderer.MacosTheme.light, false) + renderer.MacosTheme.light.metrics.hairline;
    var rightmost: u32 = 0;
    for (@intFromFloat(top)..@intFromFloat(top + TableLook.rowHeight(renderer.MacosTheme.light))) |y| for (128..200) |x| {
        if (frame.at(@intCast(x), @intCast(y)).r < 0.6) rightmost = @max(rightmost, @as(u32, @intCast(x)));
    };
    try std.testing.expect(rightmost > 180 and rightmost <= 188);
}

test "a wheel over a table's header scrolls its rows" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var built: usize = 0;
    const rows = TestRows{ .built = &built };
    var state = mod.TableState.init(std.testing.allocator);
    defer state.deinit();

    window.begin(renderer.MacosTheme.light);
    const view = Table(TestRows, &rows, &test_columns, 1000, TestRows.cell, TestRows.id, &state, .{});
    window.end();
    var frame = try window.render(view, 400, 300);
    defer frame.deinit();
    try std.testing.expect(window.scroll(.{ .x = 40, .y = 12 }, 0, -1));
    try std.testing.expect(state.scroll.offset > 0);
    try std.testing.expectEqual(@as(f32, 0), state.header_scroll.offset);
}
