//! Where a window was and how big: the value an app saves to reopen it there.

const std = @import("std");
const log = std.log.scoped(.ziggui_window_place);

/// Where a window was and how big, in points (desktop coordinates): the
/// value an app keeps in its settings, read by `App.windowPlace` and given
/// back at launch through `AppConfig.restoring`.
pub const WindowPlace = struct {
    const Self = @This();

    /// The left edge.
    x: i32,
    /// The top edge.
    y: i32,
    /// The width; while maximized, the width a restore returns to.
    width: u32,
    /// The height; while maximized, the height a restore returns to.
    height: u32,
    /// The window is maximized.
    maximized: bool = false,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // A value only: nothing here does I/O to trace.
    _ = log;
}
