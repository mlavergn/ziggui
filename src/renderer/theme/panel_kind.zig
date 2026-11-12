//! What a floating panel is for.

const std = @import("std");
const log = std.log.scoped(.ziggui_panel_kind);

/// What a floating panel is for: native macOS draws modals (sheets/alerts) as
/// opaque elevated panels but popovers/menus as frosted material.
pub const PanelKind = enum {
    const Self = @This();

    /// A sheet or alert.
    modal,
    /// A popover or menu.
    popover,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
