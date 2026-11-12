//! The popover panel window (see `PanelSpecification`): created hidden at startup and
//! toggled by a status-item click. Its hit regions live in their own lists so
//! clicks on the panel never resolve against the main window's tree.

const std = @import("std");
const log = std.log.scoped(.ziggui_panel);
const mod = @import("module.zig");
const renderer = @import("renderer");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// The popover panel's window and what its last frame registered. One per
/// process (`shared`); the event loop creates the window when `App.run` is
/// given a `PanelSpecification`.
pub const Panel = struct {
    const Self = @This();

    /// The panel window, while the loop runs with one.
    window: ?*sdl_c.SDL_Window = null,

    /// The panel window's SDL id (0 with none).
    id: sdl_c.SDL_WindowID = 0,

    /// Whether the panel is showing.
    shown: bool = false,

    /// The panel's hit regions from its last frame.
    hits: []const views.HitRegion = &.{},

    /// The panel's scroll regions from its last frame.
    scrolls: []const views.ScrollRegion = &.{},

    /// The pointer over the panel, in points, or null when it is elsewhere.
    hover: ?renderer.Point = null,

    /// When the panel last hid (SDL ticks). A tray click on an open panel first
    /// takes its focus, hiding it, so the click that follows must not reopen it.
    hidden_ms: u64 = 0,

    /// Size key of the frame already written by ZIGGUI_PANEL_DUMP (see the event
    /// loop's frame drawing).
    dump_written: u64 = 0,

    /// Where the status-item click being handled happened (screen coordinates);
    /// `show` anchors there instead of the pointer unless it is (0, 0), what
    /// a host that sends no position reports.
    click_at: ?[2]i32 = null,

    /// The process's panel.
    var shared_panel: Self = .{};

    /// The process's panel.
    ///
    /// - Returns: the shared panel.
    pub fn shared() *Self {
        return &shared_panel;
    }

    /// Reports whether the panel is showing.
    ///
    /// - `self`: the panel.
    /// - Returns: true while it shows.
    pub fn visible(self: *const Self) bool {
        return self.shown;
    }

    /// Positions the panel under the pointer (a tray click leaves the cursor on
    /// the icon), clamped to the screen's usable area, then shows and focuses
    /// it. A Linux status-item click anchors at the position its host reported
    /// instead (KDE and Xfce send one); a host that reports none (COSMIC sends
    /// 0, 0) gets the primary display's top-right corner, where its tray sits.
    ///
    /// - `self`: the panel.
    pub fn show(self: *Self) void {
        const window = self.window orelse return;
        var logical_width: c_int = 0;
        var logical_height: c_int = 0;
        _ = sdl_c.SDL_GetWindowSize(window, &logical_width, &logical_height);
        var mouse_x: f32 = 0;
        var mouse_y: f32 = 0;
        _ = sdl_c.SDL_GetGlobalMouseState(&mouse_x, &mouse_y);
        const corner = if (self.click_at) |at| at[0] == 0 and at[1] == 0 else false;
        if (self.click_at) |at| if (!corner) {
            mouse_x = @floatFromInt(at[0]);
            mouse_y = @floatFromInt(at[1]);
        };
        var x: c_int = @intFromFloat(@as(f32, mouse_x) - @as(f32, @floatFromInt(logical_width)) / 2);
        var y: c_int = @intFromFloat(mouse_y + 10);
        var point = sdl_c.SDL_Point{ .x = @intFromFloat(mouse_x), .y = @intFromFloat(mouse_y) };
        const display = if (corner) sdl_c.SDL_GetPrimaryDisplay() else sdl_c.SDL_GetDisplayForPoint(&point);
        var bounds: sdl_c.SDL_Rect = undefined;
        if (corner and sdl_c.SDL_GetDisplayUsableBounds(display, &bounds)) {
            // XWayland reports no work area, so the usable bounds still cover the
            // top bar: step below it.
            var full: sdl_c.SDL_Rect = undefined;
            const bar: c_int = if (sdl_c.SDL_GetDisplayBounds(display, &full) and full.y == bounds.y and full.h == bounds.h) 40 else 0;
            x = bounds.x + bounds.w - logical_width - 48;
            y = bounds.y + bar + 8;
        }
        if (sdl_c.SDL_GetDisplayUsableBounds(display, &bounds)) {
            const max_x = bounds.x + bounds.w - logical_width;
            const max_y = bounds.y + bounds.h - logical_height;
            if (max_y < bounds.y) y = bounds.y else if (y > max_y) y = max_y;
            if (x < bounds.x) x = bounds.x else if (x > max_x) x = max_x;
        }
        _ = sdl_c.SDL_SetWindowPosition(window, x, y);
        _ = sdl_c.SDL_ShowWindow(window);
        _ = sdl_c.SDL_RaiseWindow(window);
        if (mod.os_tag == .linux) Self.x11Focus(window);
        _ = sdl_c.SDL_StartTextInput(window);
        self.shown = true;
        mod.App.shared().wake();
    }

    /// Spotlight-style placement for a quick launcher: centered horizontally on
    /// the primary display, top edge 25% down, wherever the pointer is. `height`
    /// is the content's fixed size; the auto-height frame can grow it when a
    /// conversation starts without moving the top edge.
    ///
    /// - `self`: the panel.
    /// - `width`: the panel's width, in points.
    /// - `height`: the panel's height, in points.
    pub fn showCentered(self: *Self, width: u32, height: u32) void {
        const window = self.window orelse return;
        _ = sdl_c.SDL_SetWindowSize(window, @intCast(width), @intCast(height));
        var bounds: sdl_c.SDL_Rect = undefined;
        var x: c_int = 0;
        var y: c_int = 0;
        if (sdl_c.SDL_GetDisplayUsableBounds(sdl_c.SDL_GetPrimaryDisplay(), &bounds)) {
            x = bounds.x + @divTrunc(bounds.w - @as(c_int, @intCast(width)), 2);
            y = bounds.y + @as(c_int, @intFromFloat(@as(f32, @floatFromInt(bounds.h)) * 0.25));
            const max_y = bounds.y + bounds.h - @as(c_int, @intCast(height));
            if (y > max_y) y = @max(bounds.y, max_y);
        }
        _ = sdl_c.SDL_SetWindowPosition(window, x, y);
        _ = sdl_c.SDL_ShowWindow(window);
        _ = sdl_c.SDL_RaiseWindow(window);
        _ = sdl_c.SDL_StartTextInput(window);
        self.shown = true;
        mod.App.shared().wake();
    }

    /// Hides the panel and clears any field focus it held.
    ///
    /// - `self`: the panel.
    pub fn hide(self: *Self) void {
        if (!self.shown) return;
        self.shown = false;
        self.hidden_ms = sdl_c.SDL_GetTicks();
        if (self.window) |window| {
            _ = sdl_c.SDL_StopTextInput(window);
            _ = sdl_c.SDL_HideWindow(window);
        }
        if (views.Focus.shared().focused() != null) views.Focus.shared().clear();
        mod.App.shared().wake();
    }

    /// Shows the panel when hidden, else hides it.
    ///
    /// - `self`: the panel.
    pub fn toggle(self: *Self) void {
        if (self.shown) self.hide() else self.show();
    }

    /// Resizes the panel window without showing it (a launcher restores the
    /// tray size before hiding, so the next tray click anchors correctly).
    ///
    /// - `self`: the panel.
    /// - `width`: the new width, in points.
    /// - `height`: the new height, in points.
    pub fn setSize(self: *const Self, width: u32, height: u32) void {
        const window = self.window orelse return;
        _ = sdl_c.SDL_SetWindowSize(window, @intCast(width), @intCast(height));
    }

    /// Reports whether a status-item click counts: false for the click that
    /// just closed the panel by taking its focus.
    ///
    /// - `self`: the panel.
    /// - Returns: true when the click should act.
    pub fn statusClickCounts(self: *const Self) bool {
        return self.shown or sdl_c.SDL_GetTicks() - self.hidden_ms >= 300;
    }

    /// Gives an override-redirect X11 window input focus (no window manager
    /// does), so a click elsewhere takes it away again and closes the panel. A
    /// no-op off X11.
    fn x11Focus(window: *sdl_c.SDL_Window) void {
        const properties = sdl_c.SDL_GetWindowProperties(window);
        const display = sdl_c.SDL_GetPointerProperty(properties, sdl_c.SDL_PROP_WINDOW_X11_DISPLAY_POINTER, null) orelse return;
        const x11_window = sdl_c.SDL_GetNumberProperty(properties, sdl_c.SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
        if (x11_window == 0) return;
        const library = std.c.dlopen("libX11.so.6", .{ .LAZY = true }) orelse return;
        const XSetInputFocus = *const fn (?*anyopaque, c_ulong, c_int, c_ulong) callconv(.c) c_int;
        const set_focus: XSetInputFocus = @ptrCast(@alignCast(std.c.dlsym(library, "XSetInputFocus") orelse return));
        _ = set_focus(display, @intCast(x11_window), 1, 0); // RevertToPointerRoot, CurrentTime
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Panel);
    // Nothing here does I/O to trace.
    _ = log;
}
