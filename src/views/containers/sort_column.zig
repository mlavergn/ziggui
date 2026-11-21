//! Which column a `Table` is sorted by, and in which order.

const std = @import("std");
const log = std.log.scoped(.ziggui_sort_column);
const mod = @import("module.zig");

/// Which column a `Table` is sorted by, and in which order. `index` is the
/// column's position in the `columns` slice (-1 = unsorted). A `TableState`
/// keeps one (`sort`): a tap on a sortable header sets it, in the column's
/// first order, or flips the order when already sorted by it, and the app
/// re-sorts its rows to match (`TableOptions.on_sort`).
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
