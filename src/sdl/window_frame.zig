//! Where the main window is and how big, in points.

const std = @import("std");
const log = std.log.scoped(.ziggui_window_frame);

/// The main window's position (desktop coordinates, its top-left corner) and size, in points.
pub const WindowFrame = struct {
    const Self = @This();

    /// The left edge.
    x: i32,
    /// The top edge.
    y: i32,
    /// The width.
    width: u32,
    /// The height.
    height: u32,

    /// Whether at least `min_visible` points of the frame, across and down, fall inside `bounds`.
    ///
    /// - `self`: the frame.
    /// - `bounds`: a display's usable area.
    /// - `min_visible`: how much must show, both ways.
    /// - Returns: true when enough of it shows.
    pub fn overlaps(self: *const Self, bounds: Self, min_visible: i32) bool {
        // In i64: a remembered frame read from a file may sit anywhere.
        const left = @max(@as(i64, self.x), bounds.x);
        const top = @max(@as(i64, self.y), bounds.y);
        const right = @min(@as(i64, self.x) + self.width, @as(i64, bounds.x) + bounds.width);
        const bottom = @min(@as(i64, self.y) + self.height, @as(i64, bounds.y) + bounds.height);
        return right - left >= min_visible and bottom - top >= min_visible;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Geometry only: nothing here does I/O to trace.
    _ = log;
}

test "window frame: a frame shows on a display only when enough of it falls inside" {
    const display: WindowFrame = .{ .x = 0, .y = 25, .width = 1440, .height = 875 };
    try std.testing.expect((WindowFrame{ .x = 100, .y = 100, .width = 1200, .height = 780 }).overlaps(display, 100));
    // A display that was unplugged: the frame sits beyond the right edge.
    try std.testing.expect(!(WindowFrame{ .x = 2000, .y = 100, .width = 1200, .height = 780 }).overlaps(display, 100));
    // Far out of range, as a corrupt file might hold: no overflow, just not shown.
    try std.testing.expect(!(WindowFrame{ .x = std.math.maxInt(i32), .y = std.math.minInt(i32), .width = std.math.maxInt(u32), .height = std.math.maxInt(u32) }).overlaps(display, 100));
    // Only a sliver shows.
    try std.testing.expect(!(WindowFrame{ .x = 1400, .y = 100, .width = 1200, .height = 780 }).overlaps(display, 100));
}
