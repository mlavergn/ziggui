//! One segment of an `IconSegmentedControl`, and the width such a control
//! takes, for a caller laying out around it.

const std = @import("std");
const log = std.log.scoped(.ziggui_icon_segment);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One segment of an `IconSegmentedControl`: its Lucide icon, and the title
/// that names it (its accessibility label and hover hint).
pub const IconSegment = struct {
    const Self = @This();

    /// The glyph drawn in the segment.
    icon: renderer.Icon,
    /// What the segment is, read out and shown on hover.
    title: []const u8,

    /// The ideal width of an `IconSegmentedControl` of `count` segments:
    /// what a caller lays out around it (`WindowChrome.topBarLeading`).
    ///
    /// - `count`: how many segments.
    /// - Returns: the width, in points.
    pub fn controlWidth(count: usize) f32 {
        const segments: f32 = @floatFromInt(count);
        // Each segment, the gaps between them, and the track's inset on both sides.
        return segments * mod.ControlMetrics.icon_segment_width + (segments + 1) * mod.ControlMetrics.segment_track_inset;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "an icon segmented control's width is its segments, gaps and inset" {
    try std.testing.expectEqual(@as(f32, 2 * mod.ControlMetrics.icon_segment_width + 3 * mod.ControlMetrics.segment_track_inset), IconSegment.controlWidth(2));
}
