//! A laid-out piece of one span on one line of a rich paragraph.

const std = @import("std");
const log = std.log.scoped(.ziggui_rich_run);

/// A byte range of one span placed on a line: where it starts and how wide
/// it is.
pub const RichRun = struct {
    const Self = @This();

    /// The span's index in the paragraph.
    span: u32,

    /// The first byte, in the span's text.
    start: u32,

    /// One past the last byte, in the span's text.
    end: u32,

    /// The run's left edge, from the line's.
    x: f32,

    /// The run's width.
    width: f32,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
