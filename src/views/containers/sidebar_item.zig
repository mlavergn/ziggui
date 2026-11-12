//! One row of a `Sidebar`.

const std = @import("std");
const log = std.log.scoped(.ziggui_sidebar_item);
const mod = @import("module.zig");

/// One row of a `Sidebar`: a title, an optional leading icon, and an optional
/// second `detail` line (a chat-list style subtitle). Mirrors SwiftUI's
/// `Label(item, systemImage:)` rows in a `.sidebar`-styled `List`.
pub const SidebarItem = struct {
    const Self = @This();

    /// The row's title.
    label: []const u8,

    /// A leading icon, if any.
    icon: ?mod.IconName = null,

    /// A second line under the title, if any.
    detail: ?[]const u8 = null,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
