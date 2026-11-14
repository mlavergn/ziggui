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

test "view: frameTime reads back what setFrameTime set" {
    const clock = FrameClock.shared();
    const saved = clock.time();
    defer clock.setTime(saved);
    clock.setTime(1234);
    try std.testing.expectEqual(@as(u64, 1234), clock.time());
}
