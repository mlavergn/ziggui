//! The SDL hit-test callback: the drag band and, with a custom title bar, the
//! resize edges. What a press does is decided headless by
//! `views.WindowHitArea`; this maps it to SDL.

const std = @import("std");
const log = std.log.scoped(.ziggui_window_hit_test);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// The main window's drag band, resize edge, and the hit regions they yield
/// to. One per process (`shared`).
pub const WindowHitTest = struct {
    const Self = @This();

    /// How far in from a custom-title-bar window's edges a press resizes it, in points.
    pub const custom_resize_edge: f32 = 6;

    /// The top band, in points, whose empty space drags the window.
    drag_band: f32 = 0,

    /// The current frame's hit regions (SDL calls the hit test from inside the
    /// event pump, where the loop's lists are out of reach).
    hits: []const views.HitRegion = &.{},

    /// The resize edge in effect: `custom_resize_edge` with a custom title bar, else 0.
    resize_edge: f32 = 0,

    /// The process's hit test.
    var shared_hit_test: Self = .{};

    /// The process's hit test.
    ///
    /// - Returns: the shared hit test.
    pub fn shared() *Self {
        return &shared_hit_test;
    }

    /// Sets the band and edge, and hands SDL the hit test for `window`.
    ///
    /// - `self`: the hit test.
    /// - `window`: the main window.
    /// - `drag_band`: the drag band's height, in points.
    /// - `custom_titlebar`: whether the window draws its own title bar (and so
    ///   resizes from its edges).
    pub fn install(self: *Self, window: *sdl_c.SDL_Window, drag_band: f32, custom_titlebar: bool) void {
        self.drag_band = drag_band;
        self.resize_edge = if (custom_titlebar) Self.custom_resize_edge else 0;
        _ = sdl_c.SDL_SetWindowHitTest(window, Self.hitTest, null);
    }

    /// Empty space in the top band drags the window; anything tappable there
    /// (a toolbar button, a title menu) keeps its clicks, an overlay's dismiss
    /// region excepted. With a custom title bar the edges resize the window
    /// unless it is maximized. Fullscreen, the whole window is content. See
    /// `views.WindowHitArea`.
    fn hitTest(window: ?*sdl_c.SDL_Window, area: [*c]const sdl_c.SDL_Point, _: ?*anyopaque) callconv(.c) sdl_c.SDL_HitTestResult {
        const self = Self.shared();
        const app = mod.App.shared();
        const point = app.eventPoint(@floatFromInt(area.*.x), @floatFromInt(area.*.y));
        var width: c_int = 0;
        var height: c_int = 0;
        if (window) |pressed| _ = sdl_c.SDL_GetWindowSize(pressed, &width, &height);
        const flags: sdl_c.SDL_WindowFlags = if (window) |pressed| sdl_c.SDL_GetWindowFlags(pressed) else 0;
        const maximized = (flags & sdl_c.SDL_WINDOW_MAXIMIZED) != 0;
        const size = app.eventPoint(@floatFromInt(width), @floatFromInt(height));
        const hit_area: views.WindowHitArea = .{
            .size = .{ .width = size.x, .height = size.y },
            .drag_band = self.drag_band,
            .resize_edge = if (maximized) 0 else self.resize_edge,
            .hits = self.hits,
            .menu_open = views.TextContextMenu.shared().isOpen(),
            .fullscreen = (flags & sdl_c.SDL_WINDOW_FULLSCREEN) != 0,
        };
        return switch (hit_area.at(point)) {
            .normal => sdl_c.SDL_HITTEST_NORMAL,
            .draggable => sdl_c.SDL_HITTEST_DRAGGABLE,
            .resizeTopLeft => sdl_c.SDL_HITTEST_RESIZE_TOPLEFT,
            .resizeTop => sdl_c.SDL_HITTEST_RESIZE_TOP,
            .resizeTopRight => sdl_c.SDL_HITTEST_RESIZE_TOPRIGHT,
            .resizeRight => sdl_c.SDL_HITTEST_RESIZE_RIGHT,
            .resizeBottomRight => sdl_c.SDL_HITTEST_RESIZE_BOTTOMRIGHT,
            .resizeBottom => sdl_c.SDL_HITTEST_RESIZE_BOTTOM,
            .resizeBottomLeft => sdl_c.SDL_HITTEST_RESIZE_BOTTOMLEFT,
            .resizeLeft => sdl_c.SDL_HITTEST_RESIZE_LEFT,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(WindowHitTest);
    // Nothing here does I/O to trace.
    _ = log;
}
