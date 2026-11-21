//! A main-window mouse event in points, as `App.setMouseHandler`'s handler
//! sees it.

const std = @import("std");
const log = std.log.scoped(.ziggui_mouse_event);
const mod = @import("module.zig");
const renderer = @import("renderer");
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
    /// A trackpad pinch changed its scale (`scale`), at the pointer.
    pinch,
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

    /// The pinch's scale change since its last update: above 1 zooms in,
    /// below 1 out (pinch only).
    scale: f32 = 1,

    /// `SDL_KMOD_*` mask.
    modifiers: u16 = 0,

    /// The mouse event an SDL event is, in the points of the window it came from.
    ///
    /// - `event`: the SDL event.
    /// - `scale`: that window's event scale (`App.event_scale`, `PopoverWindow.event_scale`).
    /// - `hover`: the pointer over that window, where a pinch acts; null when elsewhere.
    /// - Returns: the mouse event, or null when it is not one.
    pub fn fromSdl(event: *const sdl_c.SDL_Event, scale: f32, hover: ?renderer.Point) ?Self {
        const modifiers: u16 = @intCast(sdl_c.SDL_GetModState());
        return switch (event.type) {
            sdl_c.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl_c.SDL_EVENT_MOUSE_BUTTON_UP => blk: {
                const point: renderer.Point = .{ .x = event.button.x * scale, .y = event.button.y * scale };
                break :blk .{ .kind = if (event.type == sdl_c.SDL_EVENT_MOUSE_BUTTON_DOWN) .down else .up, .x = point.x, .y = point.y, .button = event.button.button, .clicks = event.button.clicks, .modifiers = modifiers };
            },
            sdl_c.SDL_EVENT_MOUSE_MOTION => blk: {
                const point: renderer.Point = .{ .x = event.motion.x * scale, .y = event.motion.y * scale };
                break :blk .{ .kind = .motion, .x = point.x, .y = point.y, .held = (event.motion.state & sdl_c.SDL_BUTTON_LMASK) != 0, .modifiers = modifiers };
            },
            sdl_c.SDL_EVENT_MOUSE_WHEEL => blk: {
                const point: renderer.Point = .{ .x = event.wheel.mouse_x * scale, .y = event.wheel.mouse_y * scale };
                break :blk .{ .kind = .wheel, .x = point.x, .y = point.y, .delta_y = event.wheel.y, .delta_x = event.wheel.x, .modifiers = modifiers };
            },
            // A pinch has no position of its own: it acts where the pointer rests.
            sdl_c.SDL_EVENT_PINCH_UPDATE => blk: {
                const point = hover orelse break :blk null;
                break :blk .{ .kind = .pinch, .x = point.x, .y = point.y, .scale = event.pinch.scale, .modifiers = modifiers };
            },
            else => null,
        };
    }

    /// Whether ⌘ or Ctrl was held: what makes a wheel turn zoom rather than
    /// scroll (`ZoomState.wheel`'s `zooming`).
    ///
    /// - `self`: the event.
    /// - Returns: true when either was held.
    pub fn commandOrControl(self: *const Self) bool {
        return (self.modifiers & (sdl_c.SDL_KMOD_GUI | sdl_c.SDL_KMOD_CTRL)) != 0;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a mouse event is in the points of the window it came from, at that window's scale" {
    var event = std.mem.zeroes(sdl_c.SDL_Event);
    event.type = sdl_c.SDL_EVENT_MOUSE_WHEEL;
    event.wheel.mouse_x = 30;
    event.wheel.mouse_y = 40;
    event.wheel.y = 1;
    // A window drawn at twice SDL's coordinates (a display of another scale).
    const wheel = MouseEvent.fromSdl(&event, 2, null).?;
    try std.testing.expectEqual(MouseEventKind.wheel, wheel.kind);
    try std.testing.expectEqual(@as(f32, 60), wheel.x);
    try std.testing.expectEqual(@as(f32, 80), wheel.y);

    // A pinch acts where the pointer rests over its window, and is nothing with no pointer there.
    event = std.mem.zeroes(sdl_c.SDL_Event);
    event.type = sdl_c.SDL_EVENT_PINCH_UPDATE;
    event.pinch.scale = 1.5;
    const pinch = MouseEvent.fromSdl(&event, 2, .{ .x = 12, .y = 34 }).?;
    try std.testing.expectEqual(@as(f32, 12), pinch.x);
    try std.testing.expectEqual(@as(f32, 1.5), pinch.scale);
    try std.testing.expectEqual(null, MouseEvent.fromSdl(&event, 2, null));
}

test "the popover window converts its events with its own scale" {
    var popover_window: mod.PopoverWindow = .{ .event_scale = 0.5 };
    const point = popover_window.eventPoint(100, 60);
    try std.testing.expectEqual(@as(f32, 50), point.x);
    try std.testing.expectEqual(@as(f32, 30), point.y);
}
