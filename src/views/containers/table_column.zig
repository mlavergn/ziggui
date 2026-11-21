//! One column of a `Table`.

const std = @import("std");
const log = std.log.scoped(.ziggui_table_column);
const mod = @import("module.zig");

/// One column of a `Table`: its title, width and how it sorts. A column
/// with a width keeps it until the user drags its edge; one without shares
/// what is left of the pane while the table fits, and keeps the width it is
/// dragged to.
pub const TableColumn = struct {
    const Self = @This();

    /// The header's title.
    title: []const u8,

    /// The column's width, in points, or null to share the leftover.
    width: ?f32 = null,

    /// The narrowest the column lays out or is dragged to.
    min_width: f32 = 40,

    /// Whether a tap on the header sorts by the column.
    sortable: bool = false,

    /// Pins the header and cells to the trailing edge (numeric columns).
    trailing: bool = false,

    /// The order a first tap on the header sorts in; a second flips it.
    first_order: mod.SortOrder = .forward,

    /// The header's hover hint (a column's type, say), or null for none.
    help: ?[]const u8 = null,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
