//! Whether a part of a view shows, as SwiftUI's `Visibility`.

const std = @import("std");
const log = std.log.scoped(.ziggui_visibility);

/// Whether a part of a view shows (SwiftUI's `Visibility`): a table's column
/// headers (`TableOptions.column_headers`), say.
pub const Visibility = enum {
    const Self = @This();

    /// As the view decides: shown, for every view that takes one today.
    automatic,
    /// Shown.
    visible,
    /// Not shown.
    hidden,

    /// Whether the part shows: `.automatic` and `.visible` show it.
    ///
    /// - `self`: the visibility.
    /// - Returns: true unless `.hidden`.
    pub fn shows(self: *const Self) bool {
        return self.* != .hidden;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Visibility);
    // Nothing here does I/O to trace.
    _ = log;
}

test "a visibility shows its part unless hidden" {
    for ([_]Visibility{ .automatic, .visible }) |visibility| try std.testing.expect(visibility.shows());
    const hidden: Visibility = .hidden;
    try std.testing.expect(!hidden.shows());
}
