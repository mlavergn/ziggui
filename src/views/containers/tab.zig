//! One page of a `TabView`.

const std = @import("std");
const log = std.log.scoped(.ziggui_tab);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One page of a `TabView` or `Settings`: a title for its tab, the content
/// shown when it is selected, and in `Settings` a symbol over the title.
pub const Tab = struct {
    const Self = @This();

    /// The tab-bar segment's title.
    label: []const u8,

    /// What the tab shows.
    content: mod.View,

    /// The symbol over the title in a `Settings` toolbar (SwiftUI's
    /// `tabItem { Label(_, systemImage:) }`); a `TabView` shows none.
    icon: ?renderer.Icon = null,
    /// The hover hint on its tab in a `Settings` toolbar (`View.help`),
    /// saying what the page holds; empty for none. A `TabView` shows none.
    help: []const u8 = "",
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
