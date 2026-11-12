//! A scroll view's app-owned offsets and extents.

const std = @import("std");
const log = std.log.scoped(.ziggui_scroll_state);

/// Scroll position for a `ScrollViewState`, owned by the app (like
/// `TextFieldState`) so it survives across frames and can be driven by the event
/// loop (mouse wheel) and by code (auto-follow). `content_height`/`viewport_height`
/// are written back by the painter each frame so `maxOffset`/`atBottom` are
/// accurate; `offset` is what the view is scrolled by (vertical, in points).
/// A `ScrollViewStateBoth` also scrolls sideways: `offset_x`, with
/// `content_width`/`viewport_width` written back the same way (all 0 otherwise).
pub const ScrollState = struct {
    const Self = @This();

    /// How far the content is scrolled down, in points.
    offset: f32 = 0,
    /// The content's height, recorded at paint.
    content_height: f32 = 0,
    /// The viewport's height, recorded at paint.
    viewport_height: f32 = 0,
    /// How far the content is scrolled sideways, in points (`ScrollViewStateBoth`).
    offset_x: f32 = 0,
    /// The content's width, recorded at paint (`ScrollViewStateBoth`).
    content_width: f32 = 0,
    /// The viewport's width, recorded at paint (`ScrollViewStateBoth`).
    viewport_width: f32 = 0,
    /// The viewport's left edge, recorded at paint (where the horizontal bar's track starts).
    viewport_x: f32 = 0,
    /// Wall-clock time (ms, in the app's `FrameClock`) of the most recent
    /// scroll. The overlay scrollbar shows only briefly after this, then fades
    /// out (see `Scrollbar.paint`). 0 means "never scrolled" → no bar.
    last_active_ms: u64 = 0,
    /// The viewport's top edge, recorded at paint (where the scrollbar's track starts).
    viewport_y: f32 = 0,

    /// The furthest the content can be scrolled (0 when it fits the viewport).
    ///
    /// - `self`: the scroll position.
    /// - Returns: the largest `offset`.
    pub fn maxOffset(self: *const Self) f32 {
        return @max(0, self.content_height - self.viewport_height);
    }

    /// Scrolls by `delta` points, clamped to `[0, maxOffset]`.
    ///
    /// - `self`: the scroll position.
    /// - `delta`: how far; positive moves the content up.
    pub fn scrollBy(self: *Self, delta: f32) void {
        self.offset = std.math.clamp(self.offset + delta, 0, self.maxOffset());
    }

    /// The furthest the content can be scrolled sideways.
    ///
    /// - `self`: the scroll position.
    /// - Returns: the largest `offset_x`, 0 when the content fits.
    pub fn maxOffsetX(self: *const Self) f32 {
        return @max(0, self.content_width - self.viewport_width);
    }

    /// Scrolls sideways, clamped to `[0, maxOffsetX]`.
    ///
    /// - `self`: the scroll position.
    /// - `delta`: how far, in points; positive moves the content left.
    pub fn scrollByX(self: *Self, delta: f32) void {
        self.offset_x = std.math.clamp(self.offset_x + delta, 0, self.maxOffsetX());
    }

    /// Scrolls to the bottom.
    ///
    /// - `self`: the scroll position.
    pub fn scrollToBottom(self: *Self) void {
        self.offset = self.maxOffset();
    }

    /// Scrolls just enough that row `index` of a list of `row_height`-tall rows
    /// is in view (keyboard selection follows the cursor). Before the first
    /// paint (no viewport yet) it only brings a row above the top back into view.
    ///
    /// - `self`: the scroll position.
    /// - `index`: the row.
    /// - `row_height`: every row's height.
    pub fn reveal(self: *Self, index: usize, row_height: f32) void {
        const top = @as(f32, @floatFromInt(index)) * row_height;
        if (top < self.offset) {
            self.offset = top;
        } else if (self.viewport_height > 0 and top + row_height > self.offset + self.viewport_height) {
            self.offset = top + row_height - self.viewport_height;
        }
    }

    /// True when scrolled to (or past) the bottom — used to decide whether to
    /// keep a streaming transcript pinned.
    ///
    /// - `self`: the scroll position.
    /// - Returns: whether it is at the bottom.
    pub fn atBottom(self: *const Self) bool {
        return self.offset >= self.maxOffset() - 0.5;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "view: ScrollState scrollBy clamps and scrollToBottom reaches the bottom" {
    var state = ScrollState{ .content_height = 250, .viewport_height = 100 };
    try std.testing.expectEqual(@as(f32, 150), state.maxOffset());
    state.scrollBy(1000); // clamps to maxOffset
    try std.testing.expectEqual(@as(f32, 150), state.offset);
    state.scrollBy(-1000); // clamps to 0
    try std.testing.expectEqual(@as(f32, 0), state.offset);
    state.scrollToBottom();
    try std.testing.expectEqual(@as(f32, 150), state.offset);
    try std.testing.expect(state.atBottom());
    // content fits the viewport -> no scrolling possible
    var fits = ScrollState{ .content_height = 50, .viewport_height = 100 };
    try std.testing.expectEqual(@as(f32, 0), fits.maxOffset());
    try std.testing.expect(fits.atBottom());
}

test "view: ScrollState.reveal follows a cursor row" {
    var scroll: ScrollState = .{ .offset = 0, .viewport_height = 100, .content_height = 2000 };
    scroll.reveal(9, 20);
    try std.testing.expectEqual(@as(f32, 100), scroll.offset);
    scroll.reveal(2, 20);
    try std.testing.expectEqual(@as(f32, 40), scroll.offset);
}
