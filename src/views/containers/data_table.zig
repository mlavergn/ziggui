//! A sortable table whose cells are arbitrary views.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_data_table);
const mod = @import("module.zig");

/// What a sortable header's tap sets: a (binding, column) pair stored in the
/// build arena, which outlives the frame until the next rebuild.
const SortAction = struct {
    const Self = @This();

    /// The table's sort.
    binding: mod.Binding(mod.SortColumn),

    /// The header's column.
    column: i64,

    /// A `Callback` that, when a sortable header is tapped, sets `binding` to
    /// sort by `column` (toggling the order if it was already the sorted
    /// column).
    ///
    /// - `binding`: the table's sort.
    /// - `column`: the header's column.
    /// - Returns: the callback, its context in the build arena.
    fn callback(binding: mod.Binding(mod.SortColumn), column: i64) mod.Callback {
        const action = mod.BuildScope.shared().allocator().create(Self) catch @panic("oom");
        action.* = .{ .binding = binding, .column = column };
        return .{ .context = action, .function = Self.apply };
    }

    /// Sorts by the column, or flips the order when it is already sorted by.
    ///
    /// - `context`: the `SortAction`.
    fn apply(context: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        const current = self.binding.get();
        if (current.index == self.column) {
            self.binding.set(.{ .index = self.column, .order = if (current.order == .reverse) .forward else .reverse });
        } else {
            self.binding.set(.{ .index = self.column, .order = .reverse });
        }
    }
};

/// Builds a `DataTable`'s cells.
const DataCell = struct {
    const Self = @This();

    /// Sizes a cell to its column (fixed width, or flexible) and pins its
    /// content to the leading edge (or trailing, for numeric columns) via the
    /// frame's alignment — NOT a Spacer, so a `.truncated()` child can shrink
    /// to fill the column rather than being squeezed to half-width by a
    /// competing Spacer.
    ///
    /// - `content`: the cell's view.
    /// - `column`: its column.
    /// - Returns: the cell.
    fn view(content: mod.View, column: mod.DataColumn) mod.View {
        const framed = if (column.width) |width| content.frameWidth(width) else content.frameMaxWidth();
        return if (column.trailing) framed.frameAlign(.trailing) else framed.frameAlign(.leading);
    }

    /// A header cell: the title, and the order chevron when the table is
    /// sorted by it; tappable when the column is sortable.
    ///
    /// - `column`: the column.
    /// - `index`: its position.
    /// - `sort`: the table's sort, or null when unsortable.
    /// - Returns: the cell.
    fn header(column: mod.DataColumn, index: usize, sort: ?mod.Binding(mod.SortColumn)) mod.View {
        const tokens = mod.BuildScope.shared().tokens();
        const sortable = column.sortable and sort != null;
        const active = sortable and sort.?.get().index == @as(i64, @intCast(index));
        const order: mod.SortOrder = if (sort) |binding| binding.get().order else .reverse;

        const label = mod.Text(column.title).font(.subheadline)
            .foreground(if (active) tokens.accent else tokens.secondary_label);
        const arrow = mod.Icon(if (order == .forward) mod.IconName.chevronUp else mod.IconName.chevronDown, 10, tokens.accent);

        // Title (+ active sort arrow). `StackBuilder.fromSlice` keeps the slice, so
        // it must live in the build arena, not on the stack. `view` pins it to
        // the column edge — no Spacer needed.
        var buffer: [2]mod.View = undefined;
        var count: usize = 0;
        buffer[count] = label;
        count += 1;
        if (active) {
            buffer[count] = arrow;
            count += 1;
        }
        const children = mod.BuildScope.shared().allocator().alloc(mod.View, count) catch @panic("oom");
        @memcpy(children, buffer[0..count]);

        var cell = Self.view(mod.StackBuilder.fromSlice(.horizontal, 4, .center, children), column);
        if (sortable) {
            cell = cell.paddingInsets(.{ .top = 2, .leading = 4, .bottom = 2, .trailing = 4 })
                .cornerRadius(5)
                .hoverFill(tokens.hover)
                .onTap(SortAction.callback(sort.?, @intCast(index)));
        }
        return cell;
    }
};

/// A multi-column table whose cells are arbitrary views (badges, buttons, icons —
/// not just text), with clickable, sortable headers. `rows[r][c]` is the view for
/// row `r`, column `c`; rows shorter than `columns` pad with blanks. Pass a `sort`
/// binding to enable sorting: clicking a `sortable` header updates the binding and
/// shows an order chevron, and the app re-sorts its data to match (the table
/// renders rows in the order given — it does not reorder them itself). Pass a
/// `scroll` state to make the body wheel-scrollable (the offset persists across
/// frames); pass null for a static viewport. The fixed header sits over
/// zebra-striped body rows; wrap the result in a fixed `.frameHeight`/
/// `.frameMaxHeight` for the bordered, scrollable look.
///
/// - `columns`: the columns.
/// - `rows`: each row's cell views.
/// - `sort`: the table's sort, or null when unsortable.
/// - `scroll`: the body's scroll position, or null for a static viewport.
/// - Returns: the table.
pub fn DataTable(columns: []const mod.DataColumn, rows: []const []const mod.View, sort: ?mod.Binding(mod.SortColumn), scroll: ?*mod.ScrollState) mod.View {
    const tokens = mod.BuildScope.shared().tokens();

    const header_cells = mod.BuildScope.shared().allocator().alloc(mod.View, columns.len) catch @panic("oom");
    for (columns, 0..) |column, column_index| header_cells[column_index] = DataCell.header(column, column_index, sort);
    const header = mod.StackBuilder.fromSlice(.horizontal, 8, .center, header_cells)
        .paddingInsets(.{ .top = 6, .leading = 8, .bottom = 6, .trailing = 8 })
        .frameMaxWidth();

    const row_views = mod.BuildScope.shared().allocator().alloc(mod.View, rows.len) catch @panic("oom");
    for (rows, 0..) |row, row_index| {
        const cells = mod.BuildScope.shared().allocator().alloc(mod.View, columns.len) catch @panic("oom");
        for (columns, 0..) |column, column_index| {
            const content = if (column_index < row.len) row[column_index] else mod.Spacer();
            cells[column_index] = DataCell.view(content, column);
        }
        var row_view = mod.StackBuilder.fromSlice(.horizontal, 8, .center, cells)
            .paddingInsets(.{ .top = 6, .leading = 8, .bottom = 6, .trailing = 8 })
            .frameMaxWidth();
        // Subtle zebra striping like a macOS table.
        if (row_index % 2 == 1) row_view = row_view.background(tokens.row_stripe);
        row_views[row_index] = row_view;
    }
    const body = mod.StackBuilder.fromSlice(.vertical, 0, .leading, row_views).frameMaxWidth();
    const viewport = if (scroll) |scroll_state| mod.ScrollViewState(scroll_state, body) else mod.ScrollView(body);

    return mod.VStack(.{
        header,
        mod.Divider(),
        viewport.frameMaxWidth().frameMaxHeight(),
    }).spacing(0).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
