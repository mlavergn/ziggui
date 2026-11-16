//! Keeps the loop drawing for a moment after the window's content resizes,
//! so platform views placed over or under the surface land where the views
//! end up once a transition (full screen) has finished moving them.

const std = @import("std");
const log = std.log.scoped(.ziggui_resize_settle);
const mod = @import("module.zig");
const views = @import("views");

/// Notices the window's content resizing and asks for frames until
/// `settle_ms` after the last change: a full-screen transition moves the
/// window's views as it animates and sends no event at its end, so the
/// pictures and views placed over the surface are placed again after it.
/// It asks again every frame until then, because the frame clock keeps only
/// the earliest request, which an earlier one (a hover hint) would win.
pub const ResizeSettle = struct {
    const Self = @This();

    /// How long after the last resize to keep drawing, in milliseconds.
    pub const settle_ms: u64 = 600;

    /// The content's width at the last `note`.
    width: f64 = 0,

    /// The content's height at the last `note`.
    height: f64 = 0,

    /// When the settling ends, on the frame clock (0 when it has).
    until_ms: u64 = 0,

    /// Whether a size was noted yet: the first is where the window starts,
    /// not a resize.
    noted: bool = false,

    /// Notes the content's size this frame, and while settling asks the
    /// frame clock for a frame at its end.
    ///
    /// - `self`: the settle.
    /// - `width`: the content's width.
    /// - `height`: the content's height.
    /// - `now_ms`: the frame clock's time.
    /// - Returns: true on a resize and until it settles: frames the
    ///   placement should check everything again.
    pub fn note(self: *Self, width: f64, height: f64, now_ms: u64) bool {
        if (!self.noted) {
            self.noted = true;
            self.width = width;
            self.height = height;
        } else if (width != self.width or height != self.height) {
            self.width = width;
            self.height = height;
            self.until_ms = now_ms + settle_ms;
        }
        if (self.until_ms == 0) return false;
        if (now_ms >= self.until_ms) {
            self.until_ms = 0;
            // The frame the request made: placed once more, then done.
            return true;
        }
        views.FrameClock.shared().requestFrameAt(self.until_ms);
        return true;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = mod;
}

test "a resize settles over settle_ms, asking for its last frame each frame until then" {
    var settle: ResizeSettle = .{};
    // The window's first size is not a resize.
    try std.testing.expect(!settle.note(700, 500, 900));
    try std.testing.expect(settle.note(800, 600, 1000));
    try std.testing.expect(settle.note(800, 600, 1300));
    // Another change restarts it.
    try std.testing.expect(settle.note(900, 600, 1400));
    try std.testing.expectEqual(@as(u64, 2000), settle.until_ms);
    // Its end: one last frame, then nothing.
    try std.testing.expect(settle.note(900, 600, 2000));
    try std.testing.expect(!settle.note(900, 600, 2100));
}
