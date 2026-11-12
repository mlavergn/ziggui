//! One column of a `DataTable` (and of `TableHeader`/`TableRow`).

const std = @import("std");
const log = std.log.scoped(.ziggui_data_column);

/// One column of a `DataTable`. `width` of `null` makes the column flexible (it
/// shares the leftover width evenly with the other flexible columns). `sortable`
/// makes the header clickable — it toggles the table's `sort` binding and shows a
/// direction chevron when active. `trailing` right-aligns the header and cells
/// (use it for numeric columns).
pub const DataColumn = struct {
    const Self = @This();

    /// The header's title.
    title: []const u8,

    /// The column's width, or null to share the leftover.
    width: ?f32 = null,

    /// Whether a click on the header sorts by the column.
    sortable: bool = false,

    /// Right-aligns the header and cells.
    trailing: bool = false,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
