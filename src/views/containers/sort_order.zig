//! The order a `DataTable` column is sorted in, as SwiftUI's `SortOrder`.

const std = @import("std");
const log = std.log.scoped(.ziggui_sort_order);

/// The order a `DataTable` column is sorted in, as SwiftUI's `SortOrder`.
pub const SortOrder = enum {
    const Self = @This();

    /// Smallest first (ascending).
    forward,

    /// Largest (most, newest) first (descending).
    reverse,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
