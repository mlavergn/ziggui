//! A `Table`'s context over rows of text.

const std = @import("std");
const log = std.log.scoped(.ziggui_table_rows);
const mod = @import("module.zig");

/// A `Table`'s context over rows of text, `rows[row][column]`, with the
/// cell function that reads them; `table` makes the whole table:
/// `TableRows.table(rows, columns, state, options)`.
pub const TableRows = struct {
    const Self = @This();

    /// Each row's cell texts, by column; a row short of a column shows
    /// nothing there.
    rows: []const []const []const u8,

    /// A context over `rows` for this frame, in the build arena: a `Table`
    /// reads its context until the frame is drawn, after the build that
    /// made it returns.
    ///
    /// - `rows`: each row's cell texts; they must outlive the frame.
    /// - Returns: the context.
    pub fn of(rows: []const []const []const u8) *const Self {
        const context = mod.BuildScope.shared().allocator().create(Self) catch @panic("oom");
        context.* = .{ .rows = rows };
        return context;
    }

    /// A `Table` over rows of text, as
    /// `Table(TableRows, TableRows.of(rows), columns, rows.len, TableRows.cell, null, state, options)`.
    ///
    /// - `rows`: each row's cell texts; they must outlive the frame.
    /// - `columns`: the columns.
    /// - `state`: the table's state, app-owned at a stable address; null for a
    ///   table that keeps nothing (fitted, selecting and sorting nothing).
    /// - `options`: how it lays out, selects, sorts and draws its header.
    /// - Returns: the table.
    pub fn table(rows: []const []const []const u8, columns: []const mod.TableColumn, state: ?*mod.TableState, options: mod.TableOptions(Self)) mod.View {
        return mod.Table(Self, Self.of(rows), columns, rows.len, Self.cell, null, state, options);
    }

    /// A cell: the row's text in the column, truncated to fit; empty past
    /// the row's end, and for a row past the last (a table given a count
    /// larger than `rows`).
    ///
    /// - `self`: the rows.
    /// - `row`: the row's position.
    /// - `column`: the column.
    /// - Returns: the cell.
    pub fn cell(self: *const Self, row: usize, column: usize) mod.View {
        const cells: []const []const u8 = if (row < self.rows.len) self.rows[row] else &.{};
        return mod.Text(if (column < cells.len) cells[column] else "").truncated();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
