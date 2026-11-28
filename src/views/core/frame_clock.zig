//! The app's millisecond clock, for views that time something (scrollbar
//! fades, hover delays).

const std = @import("std");
const log = std.log.scoped(.ziggui_frame_clock);

/// The millisecond clock the app sets once per frame, and how long the overlay
/// scrollbars stay up after a scroll: they appear on scroll, hold for
/// `scrollbar_hold_ms`, then fade over `scrollbar_fade_ms` and disappear.
pub const FrameClock = struct {
    const Self = @This();

    /// How long a scrollbar holds before fading.
    pub const scrollbar_hold_ms: u64 = 1600;

    /// How long it takes to fade.
    pub const scrollbar_fade_ms: u64 = 400;

    /// The whole time a scrollbar shows after a scroll.
    pub const scrollbar_visible_ms: u64 = scrollbar_hold_ms + scrollbar_fade_ms;

    /// Wall-clock time (ms) of the current frame, set by the app via `setTime`.
    /// 0 in headless/tests, which keeps scrollbars hidden there.
    time_ms: u64 = 0,

    /// Time (ms) until which at least one scrollbar is still visible or fading.
    scrollbar_until_ms: u64 = 0,

    /// The earliest time (ms) a view asked for a frame at (a hover hint's delay), or 0 for none.
    frame_at_ms: u64 = 0,

    /// The display's refresh interval (ms): what a view animating every
    /// frame asks to wait (`frameInterval`). The SDL runtime sets it from the
    /// window's display (8 at 120 Hz); 16 headless and in tests.
    frame_interval_ms: u64 = 16,

    /// The most frames a second the app asks for (`setFrameRateLimit`), 0 for
    /// as many as the display shows.
    frame_rate_limit: u32 = 0,

    /// The process's clock.
    var shared_clock: Self = .{};

    /// Wakes the app's event loop from any thread: installed by the SDL
    /// runtime while its loop runs (`App.wake`), null headless and in tests.
    var wake_handler: ?*const fn () void = null;

    /// The process's frame clock.
    ///
    /// - Returns: the shared clock.
    pub fn shared() *Self {
        return &shared_clock;
    }

    /// Sets the clock; the app calls this once per frame with its millisecond
    /// clock so scrollbars can time their auto-hide.
    ///
    /// - `self`: the clock.
    /// - `milliseconds`: the frame's time.
    pub fn setTime(self: *Self, milliseconds: u64) void {
        self.time_ms = milliseconds;
    }

    /// Starts a frame at `milliseconds`: sets the clock, and clears a frame
    /// request this frame satisfies, one due by then or within half a
    /// display refresh (a wait wakes a millisecond early; a press or a move
    /// may bring the frame sooner). Its views ask again as they're built;
    /// left standing, a request already met would bring a second frame at
    /// once, doubling an animating view's pace.
    ///
    /// - `self`: the clock.
    /// - `milliseconds`: the frame's time.
    pub fn beginFrame(self: *Self, milliseconds: u64) void {
        self.time_ms = milliseconds;
        if (self.frame_at_ms != 0 and self.frame_at_ms <= milliseconds + self.frame_interval_ms / 2) self.frame_at_ms = 0;
    }

    /// Sets the display's refresh interval, for views animating every frame.
    ///
    /// - `self`: the clock.
    /// - `milliseconds`: the interval, at least 1.
    pub fn setFrameInterval(self: *Self, milliseconds: u64) void {
        self.frame_interval_ms = @max(milliseconds, 1);
    }

    /// The display's refresh interval: how long a view animating every frame
    /// (an animating `SceneView`) waits for its next.
    ///
    /// - `self`: the clock.
    /// - Returns: the interval, in milliseconds.
    pub fn frameInterval(self: *const Self) u64 {
        if (self.frame_rate_limit == 0) return self.frame_interval_ms;
        return @max(self.frame_interval_ms, 1000 / @as(u64, self.frame_rate_limit));
    }

    /// The soonest the next frame may start under the frame-rate cap
    /// (`setFrameRateLimit`): a frame an event brings (a move, a key) waits
    /// for it too, the event handled at once.
    ///
    /// - `self`: the clock.
    /// - Returns: the time, on the clock `beginFrame` sets, or null with no cap.
    pub fn earliestFrame(self: *const Self) ?u64 {
        if (self.frame_rate_limit == 0) return null;
        return self.time_ms + 1000 / @as(u64, self.frame_rate_limit);
    }

    /// Caps how many frames a second a view animating every frame asks for,
    /// below the display's refresh (to save power and heat), and how soon an
    /// event's frame follows the last (`earliestFrame`).
    ///
    /// - `self`: the clock.
    /// - `frames_per_second`: the most a second; 0 for as many as the display shows.
    pub fn setFrameRateLimit(self: *Self, frames_per_second: u32) void {
        self.frame_rate_limit = frames_per_second;
    }

    /// Installs what `wake` calls; the SDL runtime sets it as its loop starts
    /// and clears it as the loop ends.
    ///
    /// - `self`: the clock.
    /// - `handler`: wakes the event loop from any thread; null for none.
    pub fn setWakeHandler(self: *Self, handler: ?*const fn () void) void {
        _ = self;
        wake_handler = handler;
    }

    /// Asks for a frame, from any thread: a worker finished something the
    /// window should show (a folder listing), and an idle loop draws nothing
    /// until an event comes. A no-op headless.
    ///
    /// - `self`: the clock.
    pub fn wake(self: *const Self) void {
        _ = self;
        if (wake_handler) |handler| handler();
    }

    /// The millisecond clock the app last set with `setTime`, for views
    /// that time something themselves (a hover delay), as the scrollbars time
    /// their fade.
    ///
    /// - `self`: the clock.
    /// - Returns: the clock; 0 headless and in tests until one sets it.
    pub fn time(self: *const Self) u64 {
        return self.time_ms;
    }

    /// Asks the loop for a frame at `milliseconds`, though no event comes: a
    /// hover hint shows once the pointer has rested, and a resting pointer
    /// sends nothing. The earliest request wins; `frameDueIn` reads it.
    ///
    /// - `self`: the clock.
    /// - `milliseconds`: when, on the clock `setTime` sets.
    pub fn requestFrameAt(self: *Self, milliseconds: u64) void {
        if (self.frame_at_ms == 0 or milliseconds < self.frame_at_ms) self.frame_at_ms = milliseconds;
    }

    /// How long the loop may wait before the frame a view asked for, clearing a request that is due.
    ///
    /// - `self`: the clock.
    /// - `now_ms`: the app's clock now.
    /// - Returns: the wait in ms (0 when it is due now), or null when none was asked for.
    pub fn frameDueIn(self: *Self, now_ms: u64) ?u64 {
        if (self.frame_at_ms == 0) return null;
        if (now_ms >= self.frame_at_ms) {
            self.frame_at_ms = 0;
            return 0;
        }
        return self.frame_at_ms - now_ms;
    }

    /// Keeps the loop awake until a just-scrolled scrollbar has faded.
    ///
    /// - `self`: the clock.
    pub fn keepScrollbarsVisible(self: *Self) void {
        self.scrollbar_until_ms = self.time_ms + scrollbar_visible_ms;
    }

    /// True while a recently-scrolled viewport's overlay scrollbar is still on
    /// screen (or fading). The app's loop wakes at ~60fps while this holds so the
    /// bar fades out instead of freezing on screen.
    ///
    /// - `self`: the clock.
    /// - `now_ms`: the app's clock now.
    /// - Returns: whether a scrollbar still shows.
    pub fn scrollbarsAnimating(self: *const Self, now_ms: u64) bool {
        return now_ms < self.scrollbar_until_ms;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "frame clock: a requested frame is due at its time, the earliest first, then cleared" {
    var clock: FrameClock = .{};
    try std.testing.expect(clock.frameDueIn(100) == null);
    clock.requestFrameAt(700);
    clock.requestFrameAt(900);
    try std.testing.expectEqual(@as(?u64, 600), clock.frameDueIn(100));
    try std.testing.expectEqual(@as(?u64, 0), clock.frameDueIn(700));
    try std.testing.expect(clock.frameDueIn(800) == null);
}

test "view: frameTime reads back what setFrameTime set" {
    const clock = FrameClock.shared();
    const saved = clock.time();
    defer clock.setTime(saved);
    clock.setTime(1234);
    try std.testing.expectEqual(@as(u64, 1234), clock.time());
}

test "view: frame clock's interval follows what the display sets, never below a millisecond" {
    var clock = FrameClock{};
    try std.testing.expectEqual(@as(u64, 16), clock.frameInterval());
    clock.setFrameInterval(8);
    try std.testing.expectEqual(@as(u64, 8), clock.frameInterval());
    clock.setFrameInterval(0);
    try std.testing.expectEqual(@as(u64, 1), clock.frameInterval());
    // A cap only ever lengthens the wait.
    clock.setFrameInterval(8);
    clock.setFrameRateLimit(30);
    try std.testing.expectEqual(@as(u64, 33), clock.frameInterval());
    clock.setFrameRateLimit(240);
    try std.testing.expectEqual(@as(u64, 8), clock.frameInterval());
}

test "view: a frame clears the request it satisfies, so an animating view keeps its pace" {
    var clock = FrameClock{};
    clock.setFrameInterval(8);
    clock.setFrameRateLimit(30);
    clock.beginFrame(1000);
    clock.requestFrameAt(clock.time() + clock.frameInterval());
    try std.testing.expectEqual(@as(?u64, 1033), clock.earliestFrame());
    // The wait woke a millisecond early: this frame meets the request, and no second frame follows at once.
    clock.beginFrame(1032);
    try std.testing.expectEqual(@as(?u64, null), clock.frameDueIn(1033));
    // A request further off than half a refresh stands.
    clock.requestFrameAt(1500);
    clock.beginFrame(1100);
    try std.testing.expectEqual(@as(?u64, 400), clock.frameDueIn(1100));
    clock.setFrameRateLimit(0);
    try std.testing.expectEqual(@as(?u64, null), clock.earliestFrame());
}
