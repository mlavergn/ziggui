//! A multi-column table of text rows (SwiftUI's `Table`).

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_table);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Builds a `Table`'s cells.
const TableCell = struct {
    const Self = @This();

    /// A cell sized to its column, its content left-aligned (macOS tables are
    /// leading-aligned).
    ///
    /// - `content`: the cell's view.
    /// - `width`: the column's width, or null to fill.
    /// - Returns: the cell.
    fn view(content: mod.View, width: ?f32) mod.View {
        // The frame default centers, so a trailing Spacer pushes content to the
        // leading edge.
        const row = mod.HStack(.{ content, mod.Spacer() });
        if (width) |fixed| return row.frameWidth(fixed);
        return row.frameMaxWidth();
    }
};

/// A multi-column data table (SwiftUI `Table`): a header row over scrollable data
/// rows, with an optional single-selection binding that highlights the selected
/// row. `rows[r][c]` is the text for row `r`, column `c`. Pure composition over
/// stacks; selectable rows reuse `Callback.select`. Wrap it in a fixed
/// `.frameHeight` to get the scrollable, bordered look.
///
/// - `columns`: the columns.
/// - `rows`: each row's cell texts.
/// - `selection`: the selected row's index, or null for no selection.
/// - Returns: the table.
pub fn Table(columns: []const mod.TableColumn, rows: []const []const []const u8, selection: ?mod.Binding(i64)) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    // Header
    const header_cells = mod.BuildScope.shared().allocator().alloc(mod.View, columns.len) catch @panic("oom");
    for (columns, 0..) |column, column_index| header_cells[column_index] = TableCell.view(mod.Text(column.title).font(.subheadline), column.width);
    const header = mod.StackBuilder.fromSlice(.horizontal, 0, .center, header_cells)
        .paddingInsets(.{ .top = 5, .leading = 8, .bottom = 5, .trailing = 8 })
        .frameMaxWidth();

    // Body rows
    const row_views = mod.BuildScope.shared().allocator().alloc(mod.View, rows.len) catch @panic("oom");
    for (rows, 0..) |row, row_index| {
        const cells = mod.BuildScope.shared().allocator().alloc(mod.View, columns.len) catch @panic("oom");
        const is_selected = if (selection) |binding| binding.get() == @as(i64, @intCast(row_index)) else false;
        const foreground: ?renderer.Color = if (is_selected) tokens.on_accent else null;
        for (columns, 0..) |column, column_index| {
            const cell_text = if (column_index < row.len) row[column_index] else "";
            var cell = mod.Text(cell_text);
            if (foreground) |color| cell = cell.foreground(color);
            cells[column_index] = TableCell.view(cell, column.width);
        }
        var row_view = mod.StackBuilder.fromSlice(.horizontal, 0, .center, cells)
            .paddingInsets(.{ .top = 5, .leading = 8, .bottom = 5, .trailing = 8 })
            .frameMaxWidth();
        if (selection) |binding| {
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
    const body = mod.StackBuilder.fromSlice(.vertical, 0, .leading, row_views).frameMaxWidth();

    return mod.VStack(.{
        header,
        mod.Divider(),
        mod.ScrollView(body).frameMaxWidth().frameMaxHeight(),
    }).spacing(0).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
