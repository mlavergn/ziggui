const std = @import("std");
const log = std.log.scoped(.ziggui_row_range);
const zigui = @import("zigui");

/// Rows built past the viewport's edge, so a small scroll never shows a gap
/// before the next frame rebuilds.
const overscan: usize = 4;

/// The rows `[start, end)` a `VirtualList` builds.
pub const RowRange = struct {
    const Self = @This();

    /// The first row built.
    start: usize,

    /// One past the last row built.
    end: usize,

    /// Which rows of a list are in view at `scroll`'s offset, plus overscan.
    ///
    /// - `count`: how many rows.
    /// - `row_h`: each row's height, in points.
    /// - `scroll`: the list's scroll position.
    /// - Returns: the rows to build.
    pub fn visible(count: usize, row_h: f32, scroll: *const zigui.ScrollState) Self {
        if (count == 0 or row_h <= 0) return .{ .start = 0, .end = 0 };
        const viewport = if (scroll.viewport_h > 0) scroll.viewport_h else 1200;
        const max_offset = @max(0, @as(f32, @floatFromInt(count)) * row_h - viewport);
        const offset = std.math.clamp(scroll.offset, 0, max_offset);
        const first: usize = @intFromFloat(@floor(offset / row_h));
        const last: usize = @intFromFloat(@ceil((offset + viewport) / row_h));
        const self = Self{ .start = @min(count, first -| overscan), .end = @min(count, last + overscan) };
        return self;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "RowRange.visible builds the rows in view plus overscan" {
    var scroll: zigui.ScrollState = .{ .offset = 200, .viewport_h = 100 };
    const r = RowRange.visible(1000, 20, &scroll);
    try std.testing.expectEqual(@as(usize, 10 - overscan), r.start);
    try std.testing.expectEqual(@as(usize, 15 + overscan), r.end);
    // Past the end clamps; an empty list builds nothing.
    scroll.offset = 1_000_000;
    try std.testing.expectEqual(@as(usize, 1000), RowRange.visible(1000, 20, &scroll).end);
    try std.testing.expectEqual(@as(usize, 0), RowRange.visible(0, 20, &scroll).end);
}
