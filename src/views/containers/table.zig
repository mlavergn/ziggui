//! A multi-column table of text rows (SwiftUI's `Table`).

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_table);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The padding before the first column and after the last.
const inset: f32 = 8;

/// How far in from a column's trailing edge a press grabs it.
const grab: f32 = 8;

/// A resizable table's room between a column's text and an edge.
const edge_gap: f32 = 6;

/// A table's columns, rows and state: built at once by `Table`, or held in the
/// build arena until a `TableResizable`'s `GeometryReader` lays it out.
const TableModel = struct {
    const Self = @This();

    /// The columns.
    columns: []const mod.TableColumn,

    /// Each row's cell texts.
    rows: []const []const []const u8,

    /// The selected row's index, or null for no selection.
    selection: ?mod.Binding(i64),

    /// The widths the user dragged, or null for a table that does not resize.
    customization: ?*mod.TableColumnCustomization,

    /// The resizable table's content for a frame of `size`: the columns laid
    /// out across its width, then the header and rows at those widths.
    ///
    /// - `self`: the model.
    /// - `size`: the size the table is laid out at.
    /// - Returns: the table's content.
    fn body(self: *const Self, size: renderer.Size) mod.View {
        const widths = mod.BuildScope.shared().allocator().alloc(f32, self.columns.len) catch @panic("oom");
        self.customization.?.resolve(self.columns, @max(0, size.width - 2 * inset), widths);
        return self.build(widths).frame(size.width, size.height);
    }

    /// The header, a divider, and the rows in a scroll view.
    ///
    /// - `self`: the model.
    /// - `widths`: each column's laid-out width, or null to use the columns' own.
    /// - Returns: the table.
    fn build(self: *const Self, widths: ?[]const f32) mod.View {
        const tokens = mod.BuildScope.shared().tokens();
        const allocator = mod.BuildScope.shared().allocator();
        const header_cells = allocator.alloc(mod.View, self.columns.len) catch @panic("oom");
        for (self.columns, header_cells, 0..) |column, *header_cell, column_index| {
            const width = if (widths) |laid_out| laid_out[column_index] else column.width;
            header_cell.* = self.headerCell(column, column_index, width);
        }
        const header = mod.StackBuilder.fromSlice(.horizontal, 0, .center, header_cells)
            .paddingInsets(.{ .top = 5, .leading = inset, .bottom = 5, .trailing = inset })
            .frameMaxWidth();

        const row_views = allocator.alloc(mod.View, self.rows.len) catch @panic("oom");
        for (self.rows, 0..) |row, row_index| {
            const cells = allocator.alloc(mod.View, self.columns.len) catch @panic("oom");
            const is_selected = if (self.selection) |binding| binding.get() == @as(i64, @intCast(row_index)) else false;
            const foreground: ?renderer.Color = if (is_selected) tokens.on_accent else null;
            for (self.columns, 0..) |column, column_index| {
                const cell_text = if (column_index < row.len) row[column_index] else "";
                var text = mod.Text(cell_text).truncated();
                if (foreground) |color| text = text.foreground(color);
                cells[column_index] = Self.cell(text, if (widths) |laid_out| laid_out[column_index] else column.width, self.cellInsets(column_index));
            }
            var row_view = mod.StackBuilder.fromSlice(.horizontal, 0, .center, cells)
                .paddingInsets(.{ .top = 5, .leading = inset, .bottom = 5, .trailing = inset })
                .frameMaxWidth();
            if (self.selection) |binding| {
                row_view = row_view.onTap(mod.Callback.select(binding, @intCast(row_index)));
                if (is_selected) {
                    row_view = row_view.background(tokens.selection);
                } else if (row_index % 2 == 1) {
                    // Subtle zebra striping like a macOS table.
                    row_view = row_view.background(tokens.row_stripe);
                }
            } else if (row_index % 2 == 1) {
                row_view = row_view.background(tokens.row_stripe);
            }
            row_views[row_index] = row_view;
        }
        const body_rows = mod.StackBuilder.fromSlice(.vertical, 0, .leading, row_views).frameMaxWidth();

        return mod.VStack(.{
            header,
            mod.Divider(),
            mod.ScrollView(body_rows).frameMaxWidth().frameMaxHeight(),
        }).spacing(0).frameMaxWidth();
    }

    /// A column's header: its title, and in a resizable table (but for the
    /// last column) the edge a press drags, a hairline at its trailing side.
    ///
    /// - `self`: the model.
    /// - `column`: the column.
    /// - `column_index`: its index.
    /// - `width`: its width, or null to fill.
    /// - Returns: the header cell.
    fn headerCell(self: *const Self, column: mod.TableColumn, column_index: usize, width: ?f32) mod.View {
        const title = mod.Text(column.title).font(.subheadline).truncated();
        const insets = self.cellInsets(column_index);
        const customization = self.customization orelse return Self.cell(title, width, insets);
        const last = column_index + 1 >= @min(self.columns.len, mod.TableColumnCustomization.max_columns);
        if (last) return Self.cell(title, width, insets);
        const edge = mod.HStack(.{
            mod.Spacer(),
            mod.Rectangle(mod.BuildScope.shared().tokens().tertiary_label).frame(1, 14),
        }).spacing(0)
            .frame(grab, 14)
            .onTap(mod.Callback.tagged(mod.TableColumnCustomization, customization, mod.TableColumnCustomization.pressEdge, column_index));
        // The edge holds the gap before the next column.
        const content = mod.HStack(.{ title, mod.Spacer(), edge }).spacing(0).paddingInsets(.{ .leading = insets.leading });
        if (width) |fixed| return content.frameWidth(fixed);
        return content.frameMaxWidth();
    }

    /// The room inside a column's cells: none in a `Table`; in a resizable
    /// one, a gap on each side of every edge a press drags.
    ///
    /// - `self`: the model.
    /// - `column_index`: the column's index.
    /// - Returns: the cell's insets.
    fn cellInsets(self: *const Self, column_index: usize) renderer.EdgeInsets {
        if (self.customization == null) return .{};
        const edges = @min(self.columns.len, mod.TableColumnCustomization.max_columns);
        return .{
            .leading = if (column_index > 0 and column_index < edges) edge_gap else 0,
            .trailing = if (column_index + 1 < edges) edge_gap else 0,
        };
    }

    /// A cell sized to its column, its content left-aligned (macOS tables are
    /// leading-aligned).
    ///
    /// - `content`: the cell's view.
    /// - `width`: the column's width, or null to fill.
    /// - `insets`: the room around the content inside the column.
    /// - Returns: the cell.
    fn cell(content: mod.View, width: ?f32, insets: renderer.EdgeInsets) mod.View {
        // The frame default centers, so a trailing Spacer pushes content to the
        // leading edge.
        var row = mod.HStack(.{ content, mod.Spacer() });
        if (insets.leading > 0 or insets.trailing > 0) row = row.paddingInsets(insets);
        if (width) |fixed| return row.frameWidth(fixed);
        return row.frameMaxWidth();
    }
};

/// A multi-column data table (SwiftUI `Table`): a header row over scrollable data
/// rows, with an optional single-selection binding that highlights the selected
/// row. `rows[r][c]` is the text for row `r`, column `c`; a text too long for
/// its column is cut with an ellipsis. Pure composition over stacks; selectable
/// rows reuse `Callback.select`. Wrap it in a fixed `.frameHeight` to get the
/// scrollable, bordered look. `TableResizable` lets the user drag the columns.
///
/// - `columns`: the columns.
/// - `rows`: each row's cell texts.
/// - `selection`: the selected row's index, or null for no selection.
/// - Returns: the table.
pub fn Table(columns: []const mod.TableColumn, rows: []const []const []const u8, selection: ?mod.Binding(i64)) mod.View {
    const model = TableModel{ .columns = columns, .rows = rows, .selection = selection, .customization = null };
    return model.build(null);
}

/// A `Table` whose columns the user resizes by dragging a column's trailing
/// edge in the header: the column grows by what the next one gives, so the
/// table keeps its width. The widths live in the app's `customization`, so
/// they survive across frames (`reset` forgets them). Laid out through a
/// `GeometryReader`, so it fills the space it is offered.
///
/// - `columns`: the columns; each stays at least its `min_width`.
/// - `rows`: each row's cell texts.
/// - `selection`: the selected row's index, or null for no selection.
/// - `customization`: the dragged widths; app-owned.
/// - Returns: the table.
pub fn TableResizable(columns: []const mod.TableColumn, rows: []const []const []const u8, selection: ?mod.Binding(i64), customization: *mod.TableColumnCustomization) mod.View {
    const model = mod.BuildScope.shared().allocator().create(TableModel) catch @panic("oom");
    model.* = .{ .columns = columns, .rows = rows, .selection = selection, .customization = customization };
    return mod.GeometryReader(TableModel, model, TableModel.body);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a resizable table's header edge drags width from one column to the next" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    // A failed expect must not leave a drag armed on this stack's state.
    defer mod.PointerInput.shared().endDrag();
    var customization: mod.TableColumnCustomization = .{};
    const columns = [_]mod.TableColumn{ .{ .title = "Name" }, .{ .title = "Role" }, .{ .title = "Age", .width = 60 } };
    const rows = [_][]const []const u8{&.{ "Ada", "Mathematician", "36" }};
    window.begin(renderer.MacosTheme.light);
    const view = TableResizable(&columns, &rows, null, &customization);
    window.end();
    var frame = try window.render(view, 316, 120);
    defer frame.deinit();
    // 300 points of columns inside the insets: two shares of 120 and the fixed 60.
    try std.testing.expectEqual(@as(f32, 120), customization.laid_out[0]);
    try std.testing.expectEqual(@as(f32, 60), customization.laid_out[2]);
    // The first column's edge ends at 8 + 120; a press just inside it arms the drag.
    try std.testing.expect(window.tap(.{ .x = 125, .y = 12 }));
    mod.PointerInput.shared().drag(window.hits.items, .{ .x = 165, .y = 12 });
    try std.testing.expectEqual(@as(f32, 160), customization.widths[0]);
    try std.testing.expectEqual(@as(f32, 80), customization.widths[1]);
    // Never past the next column's minimum.
    mod.PointerInput.shared().drag(window.hits.items, .{ .x = 400, .y = 12 });
    try std.testing.expectEqual(@as(f32, 200), customization.widths[0]);
    try std.testing.expectEqual(@as(f32, 40), customization.widths[1]);
}
