//! How a `Sidebar` highlights its selection.

const std = @import("std");
const log = std.log.scoped(.ziggui_sidebar_style);

/// How a `Sidebar` highlights its selection: `neutral` is the grey wash of
/// macOS settings-style source lists; `prominent` is the vivid accent row of
/// content lists (Mail, Notes, chat apps).
pub const SidebarStyle = enum {
    const Self = @This();

    /// A grey wash.
    neutral,

    /// The accent color.
    prominent,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
