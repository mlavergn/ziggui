//! One laid-out line of a rich paragraph.

const std = @import("std");
const log = std.log.scoped(.ziggui_rich_line);
const mod = @import("module.zig");

/// A line of a rich paragraph: its runs, where it sits, and its baseline.
pub const RichLine = struct {
    const Self = @This();

    /// The runs on the line, left to right.
    runs: []mod.RichRun,

    /// The line's top, from the paragraph's.
    y: f32,

    /// The line's height.
    height: f32,

    /// Baseline offset from the line's top.
    baseline: f32,

    /// The line's width (its last run's right edge).
    width: f32,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
