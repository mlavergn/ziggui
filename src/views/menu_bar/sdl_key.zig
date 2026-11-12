//! The SDL3 keycodes and modifier bits ziggui's key handlers pass, mirrored so key handling stays headless.

const std = @import("std");
const log = std.log.scoped(.ziggui_sdl_key);

/// The SDL3 keycodes and modifier bits ziggui's key handlers pass
/// (`setKeyHandler`, `setKeyUpHandler`): `SDLK_*` and `SDL_KMOD_*`, which are
/// stable ABI. Mirrored here so the code that reads key events (the menu
/// bar, an app's key map) stays headless, with no SDL import.
pub const SdlKey = struct {
    const Self = @This();

    // Keys with a character: their keycode is the character.

    /// Tab (`SDLK_TAB`).
    pub const tab: u32 = '\t';

    /// Return (`SDLK_RETURN`).
    pub const enter: u32 = '\r';

    /// Escape (`SDLK_ESCAPE`).
    pub const escape: u32 = 0x1b;

    /// The space bar (`SDLK_SPACE`).
    pub const space: u32 = ' ';

    /// Backspace, `⌫` (`SDLK_BACKSPACE`).
    pub const backspace: u32 = 0x08;

    /// Forward delete, `⌦` (`SDLK_DELETE`).
    pub const delete: u32 = 0x7f;

    // Keys with none: their keycode is their scancode with `scancode_mask`.

    /// The bit a key with no character has over its scancode (`SDLK_SCANCODE_MASK`).
    pub const scancode_mask: u32 = 1 << 30;

    /// F1 (`SDLK_F1`).
    pub const f1: u32 = Self.scancode_mask | 58;

    /// Home (`SDLK_HOME`).
    pub const home: u32 = Self.scancode_mask | 74;

    /// Page Up (`SDLK_PAGEUP`).
    pub const page_up: u32 = Self.scancode_mask | 75;

    /// End (`SDLK_END`).
    pub const end: u32 = Self.scancode_mask | 77;

    /// Page Down (`SDLK_PAGEDOWN`).
    pub const page_down: u32 = Self.scancode_mask | 78;

    /// The right arrow (`SDLK_RIGHT`).
    pub const right_arrow: u32 = Self.scancode_mask | 79;

    /// The left arrow (`SDLK_LEFT`).
    pub const left_arrow: u32 = Self.scancode_mask | 80;

    /// The down arrow (`SDLK_DOWN`).
    pub const down_arrow: u32 = Self.scancode_mask | 81;

    /// The up arrow (`SDLK_UP`).
    pub const up_arrow: u32 = Self.scancode_mask | 82;

    /// The keypad's Enter (`SDLK_KP_ENTER`).
    pub const keypad_enter: u32 = Self.scancode_mask | 88;

    /// The left Ctrl key (`SDLK_LCTRL`), the first of the eight modifier keys.
    pub const left_ctrl: u32 = Self.scancode_mask | 224;

    /// The left Shift key (`SDLK_LSHIFT`).
    pub const left_shift: u32 = Self.scancode_mask | 225;

    /// The left Alt key, Option on macOS (`SDLK_LALT`).
    pub const left_alt: u32 = Self.scancode_mask | 226;

    /// The left GUI key, ⌘ or the Windows key (`SDLK_LGUI`).
    pub const left_gui: u32 = Self.scancode_mask | 227;

    /// The right Ctrl key (`SDLK_RCTRL`).
    pub const right_ctrl: u32 = Self.scancode_mask | 228;

    /// The right Shift key (`SDLK_RSHIFT`).
    pub const right_shift: u32 = Self.scancode_mask | 229;

    /// The right Alt key (`SDLK_RALT`).
    pub const right_alt: u32 = Self.scancode_mask | 230;

    /// The right GUI key (`SDLK_RGUI`), the last of the eight modifier keys.
    pub const right_gui: u32 = Self.scancode_mask | 231;

    // Modifier bits: what the event's `SDL_Keymod` mask has held.

    /// The left Shift key held (`SDL_KMOD_LSHIFT`).
    pub const left_shift_mask: u16 = 0x0001;

    /// The right Shift key held (`SDL_KMOD_RSHIFT`).
    pub const right_shift_mask: u16 = 0x0002;

    /// The left Ctrl key held (`SDL_KMOD_LCTRL`).
    pub const left_ctrl_mask: u16 = 0x0040;

    /// The right Ctrl key held (`SDL_KMOD_RCTRL`).
    pub const right_ctrl_mask: u16 = 0x0080;

    /// The left Alt key held (`SDL_KMOD_LALT`).
    pub const left_alt_mask: u16 = 0x0100;

    /// The right Alt key held (`SDL_KMOD_RALT`).
    pub const right_alt_mask: u16 = 0x0200;

    /// The left GUI key held (`SDL_KMOD_LGUI`).
    pub const left_gui_mask: u16 = 0x0400;

    /// The right GUI key held (`SDL_KMOD_RGUI`).
    pub const right_gui_mask: u16 = 0x0800;

    /// Either Shift held (`SDL_KMOD_SHIFT`).
    pub const shift_mask: u16 = Self.left_shift_mask | Self.right_shift_mask;

    /// Either Ctrl held (`SDL_KMOD_CTRL`).
    pub const ctrl_mask: u16 = Self.left_ctrl_mask | Self.right_ctrl_mask;

    /// Either Alt held (`SDL_KMOD_ALT`).
    pub const alt_mask: u16 = Self.left_alt_mask | Self.right_alt_mask;

    /// Either GUI held (`SDL_KMOD_GUI`).
    pub const gui_mask: u16 = Self.left_gui_mask | Self.right_gui_mask;

    /// Any of Shift, Ctrl, Alt or GUI held.
    pub const modifier_mask: u16 = Self.shift_mask | Self.ctrl_mask | Self.alt_mask | Self.gui_mask;

    /// Reports whether a keycode is a modifier key pressed on its own.
    ///
    /// - `keycode`: an `SDL_Keycode`.
    /// - Returns: true for Ctrl, Shift, Alt or GUI, left or right.
    pub fn isModifier(keycode: u32) bool {
        return keycode >= Self.left_ctrl and keycode <= Self.right_gui;
    }

    /// Reports whether a keycode is either Alt key (Option on macOS).
    ///
    /// - `keycode`: an `SDL_Keycode`.
    /// - Returns: true for left or right Alt.
    pub fn isAlt(keycode: u32) bool {
        return keycode == Self.left_alt or keycode == Self.right_alt;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "the eight modifier keys, and only they, are modifiers; Alt is either Alt" {
    for ([_]u32{ SdlKey.left_ctrl, SdlKey.left_shift, SdlKey.left_alt, SdlKey.left_gui, SdlKey.right_ctrl, SdlKey.right_shift, SdlKey.right_alt, SdlKey.right_gui }) |key| {
        try std.testing.expect(SdlKey.isModifier(key));
    }
    try std.testing.expect(!SdlKey.isModifier(SdlKey.keypad_enter));
    try std.testing.expect(!SdlKey.isModifier('a'));
    try std.testing.expect(SdlKey.isAlt(SdlKey.left_alt) and SdlKey.isAlt(SdlKey.right_alt));
    try std.testing.expect(!SdlKey.isAlt(SdlKey.left_ctrl));
}
