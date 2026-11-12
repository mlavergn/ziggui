const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_platform);
const ziggui = @import("ziggui");

/// What the gallery asks of the window it runs in: the window buttons, the
/// quit, and the animator. `main.zig` fills the hooks with `ziggui.App`'s
/// calls; headless (the tests, `--screenshot`) they stay null, and each call
/// does what a window that is not there would.
pub const Platform = struct {
    const Self = @This();

    /// Minimizes the window.
    minimize_fn: ?*const fn () void = null,

    /// Maximizes the window, or restores it when it is maximized.
    toggle_maximized_fn: ?*const fn () void = null,

    /// Whether the window is maximized.
    is_maximized_fn: ?*const fn () bool = null,

    /// Asks to close the window, as its own close button does (the quit handler may refuse).
    request_close_fn: ?*const fn () void = null,

    /// Ends the loop without asking.
    quit_fn: ?*const fn () void = null,

    /// The running loop's animator, while there is one.
    animator_fn: ?*const fn () ?*ziggui.Animator = null,

    /// Minimizes the window, if there is one.
    ///
    /// - `self`: the platform.
    pub fn minimize(self: *const Self) void {
        if (self.minimize_fn) |hook| hook();
    }

    /// Maximizes or restores the window, if there is one.
    ///
    /// - `self`: the platform.
    pub fn toggleMaximized(self: *const Self) void {
        if (self.toggle_maximized_fn) |hook| hook();
    }

    /// Reports whether the window is maximized.
    ///
    /// - `self`: the platform.
    /// - Returns: true when it is; false with no window.
    pub fn isMaximized(self: *const Self) bool {
        const hook = self.is_maximized_fn orelse return false;
        return hook();
    }

    /// Asks to close the window, if there is one.
    ///
    /// - `self`: the platform.
    pub fn requestClose(self: *const Self) void {
        if (self.request_close_fn) |hook| hook();
    }

    /// Ends the loop, if one runs.
    ///
    /// - `self`: the platform.
    pub fn quit(self: *const Self) void {
        if (self.quit_fn) |hook| hook();
    }

    /// The animator, while a loop runs to drive it.
    ///
    /// - `self`: the platform.
    /// - Returns: the animator, or null headless.
    pub fn animator(self: *const Self) ?*ziggui.Animator {
        const hook = self.animator_fn orelse return null;
        return hook();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Platform);
    // Nothing here does I/O to trace.
    _ = log;
}

test "an empty platform does what a missing window would" {
    const platform: Platform = .{};
    platform.minimize();
    platform.toggleMaximized();
    platform.requestClose();
    platform.quit();
    try std.testing.expect(!platform.isMaximized());
    try std.testing.expectEqual(@as(?*ziggui.Animator, null), platform.animator());
}

test "a filled platform calls its hooks" {
    const Probe = struct {
        const Self = @This();

        var calls: u32 = 0;

        fn count() void {
            Self.calls += 1;
        }

        fn yes() bool {
            return true;
        }
    };
    const platform: Platform = .{
        .minimize_fn = Probe.count,
        .toggle_maximized_fn = Probe.count,
        .request_close_fn = Probe.count,
        .quit_fn = Probe.count,
        .is_maximized_fn = Probe.yes,
    };
    platform.minimize();
    platform.toggleMaximized();
    platform.requestClose();
    platform.quit();
    try std.testing.expectEqual(@as(u32, 4), Probe.calls);
    try std.testing.expect(platform.isMaximized());
}
