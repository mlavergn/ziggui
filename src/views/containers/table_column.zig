//! One column of a `Table`.

const std = @import("std");
const log = std.log.scoped(.ziggui_table_column);

/// One column of a `Table`: a header title and the width the column occupies. A
/// `null` width makes the column flexible (it shares the leftover space evenly
/// with the other flexible columns). In a `TableResizable` the user can drag it
/// wider or narrower, down to `min_width`.
pub const TableColumn = struct {
    const Self = @This();

    /// The header's title.
    title: []const u8,

    /// The column's width, or null to share the leftover.
    width: ?f32 = null,

    /// The narrowest the column lays out, or a drag in a `TableResizable`
    /// makes it (SwiftUI's `.width(min:)`).
    min_width: f32 = 40,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
