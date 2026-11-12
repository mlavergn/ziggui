//! One column of a `Table`.

const std = @import("std");
const log = std.log.scoped(.ziggui_table_column);

/// One column of a `Table`: a header title and the width the column occupies. A
/// `null` width makes the column flexible (it shares the leftover space evenly
/// with the other flexible columns).
pub const TableColumn = struct {
    const Self = @This();

    /// The header's title.
    title: []const u8,

    /// The column's width, or null to share the leftover.
    width: ?f32 = null,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
