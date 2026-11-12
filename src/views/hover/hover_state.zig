//! Which row of a list the pointer rests on, and since when: a `HoverPopover`'s delay.

const std = @import("std");
const log = std.log.scoped(.ziggui_hover_state);

/// Which of a list's rows the pointer rests on, and since when, owned by the
/// app (like `SplitState`) so a `HoverPopover` can wait out its delay across
/// frames. One state serves every row of a list, each by its own `id`.
///
/// Times are ziggui's frame clock (`FrameClock.time`), in milliseconds. The
/// delay starts at the first frame built after the pointer enters a row
/// (`stamp`), not at the enter itself: a motion event that ends an idle wait
/// arrives while the clock still reads the last frame's time, long past.
pub const HoverState = struct {
    const Self = @This();

    /// How long the pointer rests on a row before its popover opens.
    pub const delay_ms: u64 = 500;

    /// The row the pointer is over, if any.
    over: ?usize = null,

    /// When the pointer reached it: the first frame built after, once `stamped`.
    since_ms: u64 = 0,

    /// Whether `since_ms` is set for `over`; until a frame stamps it, the
    /// delay has not started.
    stamped: bool = false,

    /// The popover was dismissed (a tap) while the pointer stayed: it stays
    /// closed until the pointer moves to another row.
    dismissed: bool = false,

    /// The pointer entered row `id`; its delay starts at the next `stamp`.
    ///
    /// - `self`: the state.
    /// - `id`: the row.
    /// - `now_ms`: the frame clock, kept until the next frame stamps its own
    ///   (an event's clock is the last frame's, possibly long past).
    pub fn enter(self: *Self, id: usize, now_ms: u64) void {
        if (self.over == id) return;
        self.over = id;
        self.since_ms = now_ms;
        self.stamped = false;
        self.dismissed = false;
    }

    /// Starts the delay of a row entered since the last frame, at this
    /// frame's time; `HoverPopover` calls it as each frame builds.
    ///
    /// - `self`: the state.
    /// - `now_ms`: the frame clock, as the frame builds.
    pub fn stamp(self: *Self, now_ms: u64) void {
        if (self.over == null or self.stamped) return;
        self.since_ms = now_ms;
        self.stamped = true;
    }

    /// The pointer left row `id`; a later row's enter already took over.
    ///
    /// - `self`: the state.
    /// - `id`: the row.
    pub fn leave(self: *Self, id: usize) void {
        if (self.over == id) self.over = null;
    }

    /// Closes the open popover until the pointer moves to another row.
    ///
    /// - `self`: the state.
    pub fn dismiss(self: *Self) void {
        self.dismissed = true;
    }

    /// Reports whether row `id`'s popover is open.
    ///
    /// - `self`: the state.
    /// - `id`: the row.
    /// - `now_ms`: the frame clock.
    /// - Returns: true once the pointer has rested on it for `delay_ms`,
    ///   counted from the frame that stamped it.
    pub fn shows(self: *const Self, id: usize, now_ms: u64) bool {
        return self.over == id and self.stamped and !self.dismissed and now_ms >= self.since_ms + delay_ms;
    }

    /// Reports whether a popover is about to open, so the app keeps its loop
    /// awake (an idle loop draws no frame to open it on).
    ///
    /// - `self`: the state.
    /// - `now_ms`: the frame clock.
    /// - Returns: true while the pointer rests on a row short of the delay,
    ///   or not yet stamped by a frame.
    pub fn waiting(self: *const Self, now_ms: u64) bool {
        return self.over != null and !self.dismissed and (!self.stamped or now_ms < self.since_ms + delay_ms);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a hover opens after the delay, closes on leaving, and a dismissal holds until another row" {
    var state: HoverState = .{};
    state.enter(2, 1000);
    state.stamp(1000);
    try std.testing.expect(!state.shows(2, 1200));
    try std.testing.expect(state.waiting(1200));
    try std.testing.expect(state.shows(2, 1500));
    try std.testing.expect(!state.waiting(1500));
    try std.testing.expect(!state.shows(1, 1500));

    // Entering the same row again keeps its time; a dismissal holds.
    state.enter(2, 1400);
    state.stamp(1400);
    try std.testing.expect(state.shows(2, 1500));
    state.dismiss();
    try std.testing.expect(!state.shows(2, 2000));
    try std.testing.expect(!state.waiting(2000));

    // Another row starts afresh; leaving a row no longer over does nothing.
    state.enter(3, 2000);
    state.stamp(2000);
    state.leave(2);
    try std.testing.expectEqual(@as(?usize, 3), state.over);
    try std.testing.expect(state.shows(3, 2600));
    state.leave(3);
    try std.testing.expect(!state.shows(3, 3000));
}

test "a hover's delay starts at the first frame after the enter, not at a stale clock" {
    var state: HoverState = .{};
    // After an idle wait, the motion event arrives with the clock still at
    // the last frame, drawn long ago.
    state.enter(7, 1000);
    try std.testing.expect(!state.shows(7, 9000));
    try std.testing.expect(state.waiting(9000));

    // The frame the event wakes builds at 9000: the delay starts there.
    state.stamp(9000);
    try std.testing.expect(!state.shows(7, 9000));
    try std.testing.expect(state.waiting(9000 + HoverState.delay_ms - 1));
    try std.testing.expect(state.shows(7, 9000 + HoverState.delay_ms));

    // Later frames do not restart it; no row, nothing to stamp.
    state.stamp(9400);
    try std.testing.expect(state.shows(7, 9000 + HoverState.delay_ms));
    state.leave(7);
    state.stamp(9600);
    try std.testing.expectEqual(@as(?usize, null), state.over);
    try std.testing.expect(!state.waiting(9600));
}
