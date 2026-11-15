//! A key press as an app's handlers read it: a character or a named key, and
//! the modifiers, with ⌘ on macOS and Ctrl elsewhere as one `command`.

const std = @import("std");
const log = std.log.scoped(.ziggui_key);
const mod = @import("module.zig");

/// A key that is not a character.
pub const KeyName = enum {
    const Self = @This();

    /// `↑`.
    up,
    /// `↓`.
    down,
    /// `←`.
    left,
    /// `→`.
    right,
    /// `PgUp`.
    pageUp,
    /// `PgDn`.
    pageDown,
    /// `Home`.
    home,
    /// `End`.
    end,
    /// `Tab`.
    tab,
    /// `Return` or keypad `Enter`.
    enter,
    /// `Esc`.
    escape,
    /// The space bar.
    space,
    /// `⌫`.
    backspace,
    /// `⌦`.
    delete,
};

/// An SDL key-down as ziggui's key handler passes it.
pub const SdlKeyEvent = struct {
    const Self = @This();

    /// The `SDL_Keycode`.
    keycode: u32,
    /// The `SDL_Keymod` mask.
    mods: u16 = 0,
};

/// One key press as an app's screens read it, off an SDL key event.
///
/// A letter with shift is its capital (`A` amends), so a screen compares
/// `char` alone; `command` is ⌘ on macOS and Ctrl elsewhere, the modifier the
/// menu shortcuts use.
pub const Key = struct {
    const Self = @This();

    /// The character typed, for a printable key; null for a named one.
    char: ?u21 = null,
    /// The key, when it is not a character.
    name: ?KeyName = null,
    /// Shift was held (`shift+tab`).
    shift: bool = false,
    /// ⌘ on macOS, Ctrl elsewhere.
    command: bool = false,
    /// Option or Alt.
    alt: bool = false,

    /// Reads an SDL key-down event.
    ///
    /// - `keycode`: the event's `SDL_Keycode` (`ev.key.key`).
    /// - `mods`: its `SDL_Keymod` mask.
    /// - `mac`: whether ⌘ (rather than Ctrl) is the command modifier.
    /// - Returns: the key, or null for one no screen reads (a lone modifier, F-keys).
    pub fn fromSdl(keycode: u32, mods: u16, mac: bool) ?Self {
        var key: Self = .{
            .shift = mods & mod.SdlKey.shift_mask != 0,
            .command = mods & (if (mac) mod.SdlKey.gui_mask else mod.SdlKey.ctrl_mask) != 0,
            .alt = mods & mod.SdlKey.alt_mask != 0,
        };
        key.name = switch (keycode) {
            mod.SdlKey.up_arrow => .up,
            mod.SdlKey.down_arrow => .down,
            mod.SdlKey.left_arrow => .left,
            mod.SdlKey.right_arrow => .right,
            mod.SdlKey.page_up => .pageUp,
            mod.SdlKey.page_down => .pageDown,
            mod.SdlKey.home => .home,
            mod.SdlKey.end => .end,
            mod.SdlKey.tab => .tab,
            mod.SdlKey.enter, mod.SdlKey.keypad_enter => .enter,
            mod.SdlKey.escape => .escape,
            mod.SdlKey.space => .space,
            mod.SdlKey.backspace => .backspace,
            mod.SdlKey.delete => .delete,
            else => null,
        };
        if (key.name != null) return key;
        if (keycode < 0x21 or keycode > 0x7e) return null;
        var char: u21 = @intCast(keycode);
        if (key.shift and char >= 'a' and char <= 'z') char -= 'a' - 'A';
        key.char = char;
        return key;
    }

    /// The SDL key event that reads as this key (`fromSdl`'s inverse), for
    /// a headless `--keys` run, which feeds the window's own key path.
    ///
    /// - `self`: the key.
    /// - `mac`: whether ⌘ (rather than Ctrl) is the command modifier.
    /// - Returns: the event.
    pub fn toSdl(self: *const Self, mac: bool) SdlKeyEvent {
        var event: SdlKeyEvent = .{ .keycode = 0 };
        if (self.shift) event.mods |= mod.SdlKey.left_shift_mask;
        if (self.command) event.mods |= if (mac) mod.SdlKey.left_gui_mask else mod.SdlKey.left_ctrl_mask;
        if (self.alt) event.mods |= mod.SdlKey.left_alt_mask;
        if (self.name) |name| {
            event.keycode = switch (name) {
                .up => mod.SdlKey.up_arrow,
                .down => mod.SdlKey.down_arrow,
                .left => mod.SdlKey.left_arrow,
                .right => mod.SdlKey.right_arrow,
                .pageUp => mod.SdlKey.page_up,
                .pageDown => mod.SdlKey.page_down,
                .home => mod.SdlKey.home,
                .end => mod.SdlKey.end,
                .tab => mod.SdlKey.tab,
                .enter => mod.SdlKey.enter,
                .escape => mod.SdlKey.escape,
                .space => mod.SdlKey.space,
                .backspace => mod.SdlKey.backspace,
                .delete => mod.SdlKey.delete,
            };
            return event;
        }
        const char = self.char orelse return event;
        if (char >= 'A' and char <= 'Z') {
            event.keycode = char + ('a' - 'A');
            event.mods |= mod.SdlKey.left_shift_mask;
        } else event.keycode = char;
        return event;
    }

    /// Reports whether this is `char` with no command modifier.
    ///
    /// - `self`: the key.
    /// - `char`: the character.
    /// - Returns: true for that plain character.
    pub fn is(self: *const Self, char: u21) bool {
        return !self.command and !self.alt and self.char == char;
    }

    /// Reports whether this is the named key with no command modifier.
    ///
    /// - `self`: the key.
    /// - `name`: the key's name.
    /// - Returns: true for that key (shift allowed; see `shift`).
    pub fn isNamed(self: *const Self, name: KeyName) bool {
        return !self.command and !self.alt and self.name == name;
    }

    /// The view or screen a digit selects: `1` is the first.
    ///
    /// - `self`: the key.
    /// - Returns: the screen's index, or null for any other key.
    pub fn digit(self: *const Self) ?usize {
        const char = self.char orelse return null;
        if (self.alt or char < '1' or char > '9') return null;
        return char - '1';
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "keys read SDL events as an app reads them" {
    try std.testing.expectEqual(@as(?u21, 'A'), Key.fromSdl('a', mod.SdlKey.left_shift_mask, true).?.char);
    try std.testing.expect(Key.fromSdl('s', 0, true).?.is('s'));
    try std.testing.expect(!Key.fromSdl('s', mod.SdlKey.left_gui_mask, true).?.is('s'));
    try std.testing.expect(Key.fromSdl('s', mod.SdlKey.left_gui_mask, true).?.command);
    // Ctrl is the command key off macOS, not on it.
    try std.testing.expect(Key.fromSdl('o', mod.SdlKey.left_ctrl_mask, false).?.command);
    try std.testing.expect(!Key.fromSdl('o', mod.SdlKey.left_ctrl_mask, true).?.command);
    const tab = Key.fromSdl(mod.SdlKey.tab, mod.SdlKey.left_shift_mask, true).?;
    try std.testing.expectEqual(KeyName.tab, tab.name.?);
    try std.testing.expect(tab.shift);
    try std.testing.expectEqual(KeyName.down, Key.fromSdl(mod.SdlKey.down_arrow, 0, true).?.name.?);
    try std.testing.expectEqual(@as(?usize, 2), Key.fromSdl('3', 0, true).?.digit());
    try std.testing.expectEqual(null, Key.fromSdl(mod.SdlKey.f1, 0, true));
}

test "a key becomes the SDL event that reads back as it" {
    const keys = [_]Key{
        .{ .char = 'A', .shift = true },
        .{ .char = 's' },
        .{ .char = 'a', .command = true },
        .{ .name = .tab, .shift = true },
        .{ .name = .down },
        .{ .name = .enter },
        .{ .char = ',' },
    };
    for ([_]bool{ true, false }) |mac| for (keys) |key| {
        const event = key.toSdl(mac);
        try std.testing.expectEqual(key, Key.fromSdl(event.keycode, event.mods, mac).?);
    };
}
