//! One page of a `TabView`.

const std = @import("std");
const log = std.log.scoped(.ziggui_tab);
const mod = @import("module.zig");

/// One page of a `TabView`: a title for its tab-bar segment plus the content
/// shown when that tab is selected.
pub const Tab = struct {
    const Self = @This();

    /// The tab-bar segment's title.
    label: []const u8,

    /// What the tab shows.
    content: mod.View,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
