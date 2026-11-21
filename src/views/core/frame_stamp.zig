//! Which window's frame drew a view, so its state can tell whether that
//! window's last frame still shows it.

const std = @import("std");
const log = std.log.scoped(.ziggui_frame_stamp);

/// The frame a view was drawn in, in the window that drew it: the main
/// window's `BuildScope.frame_number`, or the popover window's
/// `BuildScope.popover_window_frame_number`. `BuildScope.stamp` makes one as a
/// view builds; `BuildScope.isLatest` says whether that window has drawn
/// since without it.
pub const FrameStamp = struct {
    const Self = @This();

    /// Whether a second window (the popover window) drew it.
    popover_window: bool,

    /// That window's frame number.
    number: u64,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
