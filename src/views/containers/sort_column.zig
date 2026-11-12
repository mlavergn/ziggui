//! Which column a `DataTable` is sorted by, and in which order.

const std = @import("std");
const log = std.log.scoped(.ziggui_sort_column);
const mod = @import("module.zig");

/// Which column a `DataTable` is sorted by, and in which order. `index` is
/// the column's position in the `columns` slice (-1 = unsorted). Keep this in app
/// `State` and pass `.binding()` to `DataTable`: the table flips it when a
/// sortable header is clicked, and the app re-sorts its rows to match. A fresh
/// column defaults to `.reverse` (largest / most / newest first); clicking the
/// active column again toggles the order.
pub const SortColumn = struct {
    const Self = @This();

    /// The sorted column's index, or -1 when unsorted.
    index: i64 = -1,

    /// The sort's order.
    order: mod.SortOrder = .reverse,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
