//! How a presented overlay is drawn.

const std = @import("std");
const log = std.log.scoped(.ziggui_overlay_style);

/// How a presented overlay is positioned and styled when drawn on top of
/// everything (see the overlay drain pass in `ViewRenderer.render`).
pub const OverlayStyle = enum {
    const Self = @This();

    /// A centered window-modal panel.
    sheet,
    /// A centered dialog box.
    alert,
    /// A small panel near its anchor view (also used for menus).
    popover,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
