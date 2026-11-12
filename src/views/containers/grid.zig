//! Lazy grids: `LazyVGrid`/`LazyHGrid` lay items into even tracks by
//! composition (a stack of stacks), so they need no new layout primitive. Short
//! final rows/columns are padded with invisible cells to keep tracks aligned.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_grid);
const mod = @import("module.zig");

/// A grid that grows vertically: `items` are mapped to cells via `map` and
/// laid out left-to-right, top-to-bottom into `columns` even columns. Built by
/// composition — a `VStack` of `HStack` rows. Each cell is `.frameMaxWidth()` so
/// columns share width evenly; the trailing slots of a short final row are
/// filled with invisible cells so every column stays aligned.
///
/// - `columns`: how many columns (0 counts as 1).
/// - `spacing`: the gap between both rows and columns.
/// - `items`: the slice.
/// - `map`: makes an item's cell.
/// - Returns: the grid.
pub fn LazyVGrid(columns: usize, spacing: f32, items: anytype, comptime map: anytype) mod.View {
    const column_count = if (columns == 0) 1 else columns;
    const count = items.len;
    const row_count = if (count == 0) 0 else (count + column_count - 1) / column_count; // ceil(count/column_count)
    const row_views = mod.BuildScope.shared().allocator().alloc(mod.View, row_count) catch @panic("oom");
    var row: usize = 0;
    while (row < row_count) : (row += 1) {
        const cells = mod.BuildScope.shared().allocator().alloc(mod.View, column_count) catch @panic("oom");
        var column: usize = 0;
        while (column < column_count) : (column += 1) {
            const index = row * column_count + column;
            cells[column] = if (index < count) map(items[index]).frameMaxWidth() else mod.Empty().frameMaxWidth();
        }
        row_views[row] = mod.StackBuilder.fromSlice(.horizontal, spacing, .center, cells);
    }
    return mod.StackBuilder.fromSlice(.vertical, spacing, .center, row_views);
}

/// A grid that grows horizontally: the transpose of `LazyVGrid`. `items` fill
/// `rows` even rows top-to-bottom, then wrap to the next column. Built as an
/// `HStack` of `VStack` columns; each cell is `.frameMaxHeight()`.
///
/// - `rows`: how many rows (0 counts as 1).
/// - `spacing`: the gap between both rows and columns.
/// - `items`: the slice.
/// - `map`: makes an item's cell.
/// - Returns: the grid.
pub fn LazyHGrid(rows: usize, spacing: f32, items: anytype, comptime map: anytype) mod.View {
    const row_count = if (rows == 0) 1 else rows;
    const count = items.len;
    const column_count = if (count == 0) 0 else (count + row_count - 1) / row_count; // ceil(count/row_count)
    const column_views = mod.BuildScope.shared().allocator().alloc(mod.View, column_count) catch @panic("oom");
    var column: usize = 0;
    while (column < column_count) : (column += 1) {
        const cells = mod.BuildScope.shared().allocator().alloc(mod.View, row_count) catch @panic("oom");
        var row: usize = 0;
        while (row < row_count) : (row += 1) {
            const index = column * row_count + row;
            cells[row] = if (index < count) map(items[index]).frameMaxHeight() else mod.Empty().frameMaxHeight();
        }
        column_views[column] = mod.StackBuilder.fromSlice(.vertical, spacing, .center, cells);
    }
    return mod.StackBuilder.fromSlice(.horizontal, spacing, .center, column_views);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
