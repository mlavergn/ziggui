//! A main-window mouse event in points, as `App.setMouseHandler`'s handler
//! sees it.

const std = @import("std");
const log = std.log.scoped(.ziggui_mouse_event);
const mod = @import("module.zig");
const sdl_c = @import("sdl_c");

/// What a `MouseEvent` reports.
pub const MouseEventKind = enum {
    const Self = @This();

    /// A button went down.
    down,
    /// A button came up.
    up,
    /// The pointer moved.
    motion,
    /// The wheel turned.
    wheel,
};

/// A mouse event in the main window, in logical points (see
/// `App.setMouseHandler`).
pub const MouseEvent = struct {
    const Self = @This();

    /// What happened.
    kind: MouseEventKind,

    /// Where, across.
    x: f32,

    /// Where, down.
    y: f32,

    /// 1 left, 2 middle, 3 right (down/up only).
    button: u8 = 0,

    /// 2 for a double click, 3 for a triple (down only).
    clicks: u8 = 1,

    /// The left button is held (motion only).
    held: bool = false,

    /// Wheel lines, positive = away from the user (wheel only).
    delta_y: f32 = 0,

    /// Sideways wheel lines, positive = to the right (wheel only).
    delta_x: f32 = 0,

    /// `SDL_KMOD_*` mask.
    modifiers: u16 = 0,

    /// The mouse event an SDL event is, in region points.
    ///
    /// - `event`: the SDL event.
    /// - Returns: the mouse event, or null when it is not one.
    pub fn fromSdl(event: *const sdl_c.SDL_Event) ?Self {
        const app = mod.App.shared();
        const modifiers: u16 = @intCast(sdl_c.SDL_GetModState());
        return switch (event.type) {
            sdl_c.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl_c.SDL_EVENT_MOUSE_BUTTON_UP => blk: {
                const point = app.eventPoint(event.button.x, event.button.y);
                break :blk .{ .kind = if (event.type == sdl_c.SDL_EVENT_MOUSE_BUTTON_DOWN) .down else .up, .x = point.x, .y = point.y, .button = event.button.button, .clicks = event.button.clicks, .modifiers = modifiers };
            },
            sdl_c.SDL_EVENT_MOUSE_MOTION => blk: {
                const point = app.eventPoint(event.motion.x, event.motion.y);
                break :blk .{ .kind = .motion, .x = point.x, .y = point.y, .held = (event.motion.state & sdl_c.SDL_BUTTON_LMASK) != 0, .modifiers = modifiers };
            },
            sdl_c.SDL_EVENT_MOUSE_WHEEL => blk: {
                const point = app.eventPoint(event.wheel.mouse_x, event.wheel.mouse_y);
                break :blk .{ .kind = .wheel, .x = point.x, .y = point.y, .delta_y = event.wheel.y, .delta_x = event.wheel.x, .modifiers = modifiers };
            },
            else => null,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
