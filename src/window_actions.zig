const std = @import("std");
const log = std.log.scoped(.ziggui_window_actions);
const zigui = @import("zigui");

/// What `WindowButtons` do: minimize, maximize or restore, and close (the
/// app's runtime calls: `minimizeWindow`, `toggleMaximized`, `requestClose`).
pub const WindowActions = struct {
    const Self = @This();

    /// Minimizes the window.
    minimize: zigui.Callback,

    /// Maximizes the window, or restores it when maximized.
    maximize: zigui.Callback,

    /// Asks to close the window (the quit handler may refuse).
    close: zigui.Callback,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
