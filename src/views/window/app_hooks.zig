//! The app hooks whose decisions need no SDL: key-ups and the quit question.
//! The SDL runtime's `App` keeps one `AppHooks` and forwards SDL's events to it, so what a
//! key-up or a quit does is tested headless.

const std = @import("std");
const log = std.log.scoped(.ziggui_app_hooks);

/// The key-up and quit handlers an app may install (`App.setKeyUpHandler`,
/// `App.setQuitHandler`). Unset, a key-up does nothing and a quit ends the loop.
pub const AppHooks = struct {
    const Self = @This();

    /// Called on every key-up with the SDL keycode (`SDLK_*`) and modifier
    /// mask (`SDL_KMOD_*`), beside the key-down handler. An app tells an Alt
    /// tap from the Alt of Alt+Tab with it.
    key_up: ?*const fn (key: u32, modifiers: u16) void = null,

    /// Asked when a quit is requested (`SDL_EVENT_QUIT`: ⌘Q, the app menu's
    /// Quit, a logout; or the main window's close button): true lets it end
    /// the loop, false keeps it running. `App.quit()` never asks.
    quit: ?*const fn () bool = null,

    /// Forwards a key-up to the handler, if one is set.
    ///
    /// - `self`: the hooks.
    /// - `key`: the SDL keycode.
    /// - `modifiers`: the SDL modifier mask.
    pub fn keyUp(self: *const Self, key: u32, modifiers: u16) void {
        if (self.key_up) |handler| handler(key, modifiers);
    }

    /// A quit was requested: clears `running` unless the quit handler refuses.
    ///
    /// - `self`: the hooks.
    /// - `running`: the event loop's run flag.
    pub fn requestQuit(self: *const Self, running: *bool) void {
        if (self.quit) |handler| if (!handler()) return;
        running.* = false;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "app hooks: a key-up reaches the handler with its keycode and modifiers" {
    const Probe = struct {
        const Self = @This();
        var key: u32 = 0;
        var modifiers: u16 = 0;
        var calls: u32 = 0;
        fn up(pressed_key: u32, pressed_modifiers: u16) void {
            key = pressed_key;
            modifiers = pressed_modifiers;
            calls += 1;
        }
    };
    // None set: nothing is called.
    (AppHooks{}).keyUp(0x400000e2, 0x0100);
    try std.testing.expectEqual(@as(u32, 0), Probe.calls);
    (AppHooks{ .key_up = Probe.up }).keyUp(0x400000e2, 0x0100);
    try std.testing.expectEqual(@as(u32, 1), Probe.calls);
    try std.testing.expectEqual(@as(u32, 0x400000e2), Probe.key);
    try std.testing.expectEqual(@as(u16, 0x0100), Probe.modifiers);
}

test "app hooks: a refusing quit handler keeps the loop running" {
    const Probe = struct {
        const Self = @This();
        var asked: u32 = 0;
        fn refuse() bool {
            asked += 1;
            return false;
        }
        fn accept() bool {
            asked += 1;
            return true;
        }
    };
    var running = true;
    (AppHooks{ .quit = Probe.refuse }).requestQuit(&running);
    try std.testing.expect(running);
    try std.testing.expectEqual(@as(u32, 1), Probe.asked);
    (AppHooks{ .quit = Probe.accept }).requestQuit(&running);
    try std.testing.expect(!running);
    try std.testing.expectEqual(@as(u32, 2), Probe.asked);
    // None set: a quit ends the loop.
    running = true;
    (AppHooks{}).requestQuit(&running);
    try std.testing.expect(!running);
}
