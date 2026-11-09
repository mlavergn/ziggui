const std = @import("std");
const log = std.log.scoped(.ziggui_menu_bar_state);
const mod = @import("module.zig");

/// A key an open `MenuBar` reads.
pub const MenuBarKey = enum {
    const Self = @This();

    /// The menu before, wrapping.
    left,

    /// The menu after, wrapping.
    right,

    /// The entry above, wrapping.
    up,

    /// The entry below, wrapping.
    down,

    /// Chooses the highlighted entry.
    enter,

    /// Closes the menu.
    escape,

    /// The menu key an SDL key event is (`SdlKey`), with no modifier held.
    ///
    /// - `keycode`: the event's `SDL_Keycode`.
    /// - `mods`: its `SDL_Keymod` mask.
    /// - Returns: the key, or null for any other key or with a modifier.
    pub fn fromKeycode(keycode: u32, mods: u16) ?Self {
        if (mods & mod.SdlKey.modifier_mask != 0) return null;
        return switch (keycode) {
            mod.SdlKey.left_arrow => .left,
            mod.SdlKey.right_arrow => .right,
            mod.SdlKey.up_arrow => .up,
            mod.SdlKey.down_arrow => .down,
            mod.SdlKey.enter, mod.SdlKey.keypad_enter => .enter,
            mod.SdlKey.escape => .escape,
            else => null,
        };
    }

    /// The SDL keycode that reads as this key (`fromKeycode`'s inverse): an
    /// app or a test can replay a key event with it.
    ///
    /// - `self`: the key.
    /// - Returns: its `SDL_Keycode` (Return, for `enter`).
    pub fn toKeycode(self: *const Self) u32 {
        return switch (self.*) {
            .left => mod.SdlKey.left_arrow,
            .right => mod.SdlKey.right_arrow,
            .up => mod.SdlKey.up_arrow,
            .down => mod.SdlKey.down_arrow,
            .enter => mod.SdlKey.enter,
            .escape => mod.SdlKey.escape,
        };
    }
};

/// A `MenuBar`'s state, owned by the app (like `SplitState`): which menu is
/// open, which of its entries is highlighted, and whether an Alt tap is under
/// way.
///
/// An Alt tap (Alt pressed, then released with no other key or click between)
/// opens the first menu, or closes the open one, as on Windows, so Alt+Tab
/// and Alt+F4 open nothing. The app forwards zigui's raw events: key-downs
/// to `keyDown`, key-ups to `keyUp`, mouse presses to `pointerDown`, and
/// takes the menus to draw and to pass them from `shown`, which folds them
/// in a narrow window.
pub const MenuBarState = struct {
    const Self = @This();

    /// The open menu's index, or null when the bar is closed.
    menu: ?usize = null,

    /// The highlighted entry of the open menu, or null for none.
    item: ?usize = null,

    /// Alt is down and nothing else has been pressed since.
    alt_armed: bool = false,

    /// Alt is down, so its key repeats are not new presses: a click while
    /// it is held ends the tap, and a repeat must not start another.
    alt_held: bool = false,

    /// Whether the last `shown` gave the folded menus; null before the first.
    folded: ?bool = null,

    /// The menus to draw and to pass the other methods at `width`: the
    /// folded `☰` below `menus.fold_below`, else every menu. A fold or an
    /// unfold closes an open menu, whose index would point at another menu.
    ///
    /// - `self`: the state.
    /// - `menus`: the bar's menus, both forms.
    /// - `width`: the window's width now (`zigui.viewport().width`).
    /// - Returns: the menus, in `menus`.
    pub fn shown(self: *Self, menus: *const mod.MenuBarMenus, width: f32) []const mod.MenuBarMenu {
        const folded = menus.foldsAt(width);
        if (self.folded) |was| if (was != folded) self.close();
        self.folded = folded;
        return if (folded) menus.folded else menus.all;
    }

    /// A key went down (zigui's key handler): Alt may start a tap and is
    /// left to the app; any other key ends a tap. With a menu open, its keys
    /// (`MenuBarKey.fromKeycode`) move and choose, and are used; a modifier
    /// on its own (Shift, Ctrl, ⌘) leaves it open; any other key closes it
    /// and goes on to the app.
    ///
    /// - `self`: the state.
    /// - `menus`: the menus `shown` gave.
    /// - `keycode`: the event's `SDL_Keycode`.
    /// - `mods`: its `SDL_Keymod` mask.
    /// - Returns: true when the menu used the key.
    pub fn keyDown(self: *Self, menus: []const mod.MenuBarMenu, keycode: u32, mods: u16) bool {
        if (mod.SdlKey.isAlt(keycode)) {
            self.altDown();
            return false;
        }
        self.otherKey();
        if (!self.isOpen()) return false;
        if (MenuBarKey.fromKeycode(keycode, mods)) |pressed| return self.key(menus, pressed);
        if (!mod.SdlKey.isModifier(keycode)) self.close();
        return false;
    }

    /// A key came up (zigui's key-up handler): Alt ends a tap, which opens
    /// the first menu or closes the open one.
    ///
    /// - `self`: the state.
    /// - `menus`: the menus `shown` gave.
    /// - `keycode`: the event's `SDL_Keycode`.
    /// - Returns: true when it was an Alt tap.
    pub fn keyUp(self: *Self, menus: []const mod.MenuBarMenu, keycode: u32) bool {
        if (!mod.SdlKey.isAlt(keycode)) return false;
        return self.altUp(menus);
    }

    /// A mouse button went down (zigui's mouse handler): an Alt held
    /// meanwhile is not a tap.
    ///
    /// - `self`: the state.
    pub fn pointerDown(self: *Self) void {
        self.otherKey();
    }

    /// Reports whether a menu is open.
    ///
    /// - `self`: the state.
    /// - Returns: true while a menu is open.
    pub fn isOpen(self: *const Self) bool {
        return self.menu != null;
    }

    /// Opens menu `index` with nothing highlighted, as a click does.
    ///
    /// - `self`: the state.
    /// - `index`: the menu.
    pub fn open(self: *Self, index: usize) void {
        self.menu = index;
        self.item = null;
    }

    /// Closes the open menu.
    ///
    /// - `self`: the state.
    pub fn close(self: *Self) void {
        self.menu = null;
        self.item = null;
    }

    /// A click on title `index`: opens its menu, or closes it when it is the open one.
    ///
    /// - `self`: the state.
    /// - `index`: the menu.
    pub fn toggle(self: *Self, index: usize) void {
        if (self.menu == index) self.close() else self.open(index);
    }

    /// The pointer entered title `index`: while another menu is open, its
    /// menu opens instead; with none open, nothing happens.
    ///
    /// - `self`: the state.
    /// - `index`: the menu.
    pub fn hover(self: *Self, index: usize) void {
        const current = self.menu orelse return;
        if (current != index) self.open(index);
    }

    /// Reads a key while a menu is open: `←→` switch menus (with more than one), `↑↓` move the
    /// highlight, `enter` chooses it, `esc` closes the menu.
    ///
    /// - `self`: the state.
    /// - `menus`: the bar's menus.
    /// - `pressed`: the key.
    /// - Returns: true when the key was used; false with no menu open.
    pub fn key(self: *Self, menus: []const mod.MenuBarMenu, pressed: MenuBarKey) bool {
        const current = self.menu orelse return false;
        if (current >= menus.len) {
            self.close();
            return false;
        }
        switch (pressed) {
            .escape => self.close(),
            // One menu (a folded bar): there is no other to move to.
            .left => if (menus.len > 1) self.openByKey(menus, (current + menus.len - 1) % menus.len),
            .right => if (menus.len > 1) self.openByKey(menus, (current + 1) % menus.len),
            .down => {
                const from = if (self.item) |at| at + 1 else 0;
                self.item = menus[current].nextSelectable(from, 1);
            },
            .up => {
                const count = menus[current].items.len;
                const from = if (self.item) |at| at + count - 1 else count -| 1;
                self.item = menus[current].nextSelectable(from, -1);
            },
            .enter => if (self.item) |at| self.choose(menus, current, at),
        }
        return true;
    }

    /// Closes the menu, then runs entry `item` of menu `menu`, if it can be chosen.
    ///
    /// - `self`: the state.
    /// - `menus`: the bar's menus.
    /// - `menu`: the menu.
    /// - `item`: the entry.
    pub fn choose(self: *Self, menus: []const mod.MenuBarMenu, menu: usize, item: usize) void {
        self.close();
        if (menu >= menus.len or item >= menus[menu].items.len) return;
        const entry = menus[menu].items[item];
        if (!entry.selectable()) return;
        if (entry.action) |action| action.call();
    }

    /// Alt went down: an Alt tap may be starting. A key repeat of an Alt
    /// already held starts none, so a click while it is held still ends the tap.
    ///
    /// - `self`: the state.
    pub fn altDown(self: *Self) void {
        if (!self.alt_held) self.alt_armed = true;
        self.alt_held = true;
    }

    /// Any other key, or a click, came while Alt was down: it is not a tap.
    ///
    /// - `self`: the state.
    pub fn otherKey(self: *Self) void {
        self.alt_armed = false;
    }

    /// Alt came up: after a tap, the first menu opens (its first entry
    /// highlighted), or the open one closes.
    ///
    /// - `self`: the state.
    /// - `menus`: the bar's menus.
    /// - Returns: true when it was a tap.
    pub fn altUp(self: *Self, menus: []const mod.MenuBarMenu) bool {
        self.alt_held = false;
        if (!self.alt_armed) return false;
        self.alt_armed = false;
        if (self.menu != null) {
            self.close();
        } else if (menus.len > 0) {
            self.openByKey(menus, 0);
        }
        return true;
    }

    /// Opens menu `index` with its first choosable entry highlighted, as the keys do.
    ///
    /// - `self`: the state.
    /// - `menus`: the bar's menus.
    /// - `index`: the menu.
    fn openByKey(self: *Self, menus: []const mod.MenuBarMenu, index: usize) void {
        self.menu = index;
        self.item = menus[index].nextSelectable(0, 1);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "raw key events: an Alt tap opens the first menu, the menu's keys move and choose, any other key closes it" {
    mod.TestMenus.chosen = 0;
    var bar: MenuBarState = .{};
    const down = MenuBarKey.down.toKeycode();
    // Alt with a key between (Alt+Tab), or a click between, opens nothing.
    try std.testing.expect(!bar.keyDown(&mod.TestMenus.menus, mod.SdlKey.left_alt, 0));
    try std.testing.expect(!bar.keyDown(&mod.TestMenus.menus, mod.SdlKey.tab, mod.SdlKey.alt_mask));
    try std.testing.expect(!bar.keyUp(&mod.TestMenus.menus, mod.SdlKey.left_alt));
    _ = bar.keyDown(&mod.TestMenus.menus, mod.SdlKey.right_alt, 0);
    bar.pointerDown();
    try std.testing.expect(!bar.keyUp(&mod.TestMenus.menus, mod.SdlKey.right_alt));
    try std.testing.expect(!bar.isOpen());
    // A tap opens File on Open; down moves past the separator and the disabled Save to Quit; enter chooses it.
    _ = bar.keyDown(&mod.TestMenus.menus, mod.SdlKey.left_alt, 0);
    try std.testing.expect(bar.keyUp(&mod.TestMenus.menus, mod.SdlKey.left_alt));
    try std.testing.expectEqual(@as(?usize, 0), bar.item);
    try std.testing.expect(bar.keyDown(&mod.TestMenus.menus, down, 0));
    try std.testing.expectEqual(@as(?usize, 3), bar.item);
    try std.testing.expect(bar.keyDown(&mod.TestMenus.menus, MenuBarKey.enter.toKeycode(), 0));
    try std.testing.expectEqual(@as(u32, 1), mod.TestMenus.chosen);
    try std.testing.expect(!bar.isOpen());
    // A modifier on its own leaves it open; a menu key with one held, or
    // any other key, closes it and the key goes on.
    bar.open(0);
    try std.testing.expect(!bar.keyDown(&mod.TestMenus.menus, mod.SdlKey.left_ctrl, 0));
    try std.testing.expect(!bar.keyDown(&mod.TestMenus.menus, mod.SdlKey.right_gui, 0));
    try std.testing.expect(bar.isOpen());
    try std.testing.expect(!bar.keyDown(&mod.TestMenus.menus, down, mod.SdlKey.shift_mask));
    try std.testing.expect(!bar.isOpen());
    bar.open(0);
    try std.testing.expect(!bar.keyDown(&mod.TestMenus.menus, 's', 0));
    try std.testing.expect(!bar.isOpen());
    // Closed, no key is the menu's.
    try std.testing.expect(!bar.keyDown(&mod.TestMenus.menus, down, 0));
}

test "shown folds the menus below the width, and a change of fold closes the open menu" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const menus = try mod.MenuBarMenus.init(arena.allocator(), &mod.TestMenus.menus, 640);
    var bar: MenuBarState = .{};
    try std.testing.expectEqual(2, bar.shown(&menus, 640).len);
    bar.open(1);
    try std.testing.expectEqual(1, bar.shown(&menus, 639).len);
    try std.testing.expect(!bar.isOpen());
    bar.open(0);
    try std.testing.expectEqual(1, bar.shown(&menus, 500).len);
    try std.testing.expect(bar.isOpen());
    try std.testing.expectEqual(2, bar.shown(&menus, 900).len);
    try std.testing.expect(!bar.isOpen());
}

test "a click toggles a menu, and pointing at another title switches only while one is open" {
    var bar: MenuBarState = .{};
    bar.hover(1);
    try std.testing.expect(!bar.isOpen());
    bar.toggle(0);
    try std.testing.expectEqual(@as(?usize, 0), bar.menu);
    bar.hover(1);
    try std.testing.expectEqual(@as(?usize, 1), bar.menu);
    bar.toggle(0);
    try std.testing.expectEqual(@as(?usize, 0), bar.menu);
    bar.toggle(0);
    try std.testing.expect(!bar.isOpen());
}

test "the keys move between menus and entries, skipping what cannot be chosen, and choose" {
    mod.TestMenus.chosen = 0;
    var bar: MenuBarState = .{};
    // Closed, the bar reads no keys.
    try std.testing.expect(!bar.key(&mod.TestMenus.menus, .down));
    bar.open(0);
    try std.testing.expect(bar.key(&mod.TestMenus.menus, .down));
    try std.testing.expectEqual(@as(?usize, 0), bar.item);
    // Down skips the separator and the disabled Save.
    try std.testing.expect(bar.key(&mod.TestMenus.menus, .down));
    try std.testing.expectEqual(@as(?usize, 3), bar.item);
    try std.testing.expect(bar.key(&mod.TestMenus.menus, .down));
    try std.testing.expectEqual(@as(?usize, 0), bar.item);
    try std.testing.expect(bar.key(&mod.TestMenus.menus, .up));
    try std.testing.expectEqual(@as(?usize, 3), bar.item);
    // Right opens Edit on its first enabled entry, past the disabled Undo.
    try std.testing.expect(bar.key(&mod.TestMenus.menus, .right));
    try std.testing.expectEqual(@as(?usize, 1), bar.menu);
    try std.testing.expectEqual(@as(?usize, 1), bar.item);
    try std.testing.expect(bar.key(&mod.TestMenus.menus, .right));
    try std.testing.expectEqual(@as(?usize, 0), bar.menu);
    try std.testing.expect(bar.key(&mod.TestMenus.menus, .left));
    try std.testing.expectEqual(@as(?usize, 1), bar.menu);
    try std.testing.expect(bar.key(&mod.TestMenus.menus, .enter));
    try std.testing.expect(!bar.isOpen());
    try std.testing.expectEqual(@as(u32, 1), mod.TestMenus.chosen);
    bar.open(1);
    try std.testing.expect(bar.key(&mod.TestMenus.menus, .escape));
    try std.testing.expect(!bar.isOpen());
}

test "a disabled entry or a separator does nothing when chosen" {
    mod.TestMenus.chosen = 0;
    var bar: MenuBarState = .{};
    bar.open(1);
    bar.choose(&mod.TestMenus.menus, 1, 0);
    bar.choose(&mod.TestMenus.menus, 0, 1);
    try std.testing.expectEqual(@as(u32, 0), mod.TestMenus.chosen);
    try std.testing.expect(!bar.isOpen());
}

test "a held Alt's key repeats start no new tap, so a click while it is held still ends it" {
    var bar: MenuBarState = .{};
    _ = bar.keyDown(&mod.TestMenus.menus, mod.SdlKey.left_alt, mod.SdlKey.alt_mask);
    bar.pointerDown();
    // The repeats that follow the click, as Windows sends for a held key.
    _ = bar.keyDown(&mod.TestMenus.menus, mod.SdlKey.left_alt, mod.SdlKey.alt_mask);
    _ = bar.keyDown(&mod.TestMenus.menus, mod.SdlKey.left_alt, mod.SdlKey.alt_mask);
    try std.testing.expect(!bar.keyUp(&mod.TestMenus.menus, mod.SdlKey.left_alt));
    try std.testing.expect(!bar.isOpen());
    // Released, the next press is a new tap.
    _ = bar.keyDown(&mod.TestMenus.menus, mod.SdlKey.left_alt, mod.SdlKey.alt_mask);
    try std.testing.expect(bar.keyUp(&mod.TestMenus.menus, mod.SdlKey.left_alt));
    try std.testing.expect(bar.isOpen());
}

test "the menu keys' keycodes read back as the same keys" {
    for (std.enums.values(MenuBarKey)) |pressed| {
        try std.testing.expectEqual(@as(?MenuBarKey, pressed), MenuBarKey.fromKeycode(pressed.toKeycode(), 0));
    }
    try std.testing.expectEqual(@as(?MenuBarKey, .enter), MenuBarKey.fromKeycode(mod.SdlKey.keypad_enter, 0));
}

test "an Alt tap opens the first menu or closes the open one; Alt with another key does not" {
    var bar: MenuBarState = .{};
    try std.testing.expect(!bar.altUp(&mod.TestMenus.menus));
    bar.altDown();
    bar.otherKey();
    try std.testing.expect(!bar.altUp(&mod.TestMenus.menus));
    try std.testing.expect(!bar.isOpen());
    bar.altDown();
    try std.testing.expect(bar.altUp(&mod.TestMenus.menus));
    try std.testing.expectEqual(@as(?usize, 0), bar.menu);
    try std.testing.expectEqual(@as(?usize, 0), bar.item);
    bar.altDown();
    try std.testing.expect(bar.altUp(&mod.TestMenus.menus));
    try std.testing.expect(!bar.isOpen());
}
