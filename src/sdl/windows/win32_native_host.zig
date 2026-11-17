//! The Windows native-view host: each `NativeView` handle is a child `HWND`
//! (a WebView2 page's container, say) that lives under a hidden parking
//! window until a frame shows it, then is moved into SDL's window *above*
//! its swapchain and framed from its `NativeRegion`, clipped with a window
//! region to the visible part and the corner radius. Being above the
//! surface, nothing ziggui draws can cover it, so while an overlay is open
//! every view is hidden, and the view that held the keyboard gets it back
//! when the overlay closes.
//!
//! Clicks and keys on a view go to its own window and never reach SDL, so
//! there is nothing to absorb and no key to drop; `release` puts the
//! keyboard back on SDL's window when a press lands on ziggui's surface.
//! A view in another process (WebView2's) reports its focus through the
//! `focus_property` the host checks beside `GetFocus`. Windows only: every
//! caller is behind `os_tag == .windows`.

const std = @import("std");
const log = std.log.scoped(.ziggui_win32_native_host);
const mod = @import("module.zig");
const renderer = @import("renderer");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// A GDI region handle.
const HRGN = ?*anyopaque;

extern "user32" fn SetParent(child: mod.HWND, parent: mod.HWND) callconv(.winapi) mod.HWND;
extern "user32" fn GetParent(window: mod.HWND) callconv(.winapi) mod.HWND;
extern "user32" fn SetWindowPos(window: mod.HWND, insert_after: mod.HWND, x: i32, y: i32, width: i32, height: i32, flags: u32) callconv(.winapi) i32;
extern "user32" fn ShowWindow(window: mod.HWND, command: i32) callconv(.winapi) i32;
extern "user32" fn IsWindow(window: mod.HWND) callconv(.winapi) i32;
extern "user32" fn IsWindowVisible(window: mod.HWND) callconv(.winapi) i32;
extern "user32" fn IsChild(parent: mod.HWND, window: mod.HWND) callconv(.winapi) i32;
extern "user32" fn GetFocus() callconv(.winapi) mod.HWND;
extern "user32" fn SetFocus(window: mod.HWND) callconv(.winapi) mod.HWND;
extern "user32" fn SetWindowRgn(window: mod.HWND, region: HRGN, redraw: i32) callconv(.winapi) i32;
extern "user32" fn GetPropW(window: mod.HWND, name: [*:0]const u16) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn CreateRectRgn(left: i32, top: i32, right: i32, bottom: i32) callconv(.winapi) HRGN;
extern "gdi32" fn CreateRoundRectRgn(left: i32, top: i32, right: i32, bottom: i32, ellipse_width: i32, ellipse_height: i32) callconv(.winapi) HRGN;
extern "gdi32" fn CombineRgn(destination: HRGN, first: HRGN, second: HRGN, mode: i32) callconv(.winapi) i32;

/// How many platform views one window places at once.
const max_hosts = 16;

/// A placed view's frame and clip, in the window's pixels, as last applied.
const Placement = struct {
    const Self = @This();

    /// The frame's left edge, in client pixels.
    x: i32 = 0,
    /// The frame's top edge, in client pixels.
    y: i32 = 0,
    /// The frame's width, in pixels.
    width: i32 = 0,
    /// The frame's height, in pixels.
    height: i32 = 0,
    /// The visible part's left edge, relative to the frame.
    clip_x: i32 = 0,
    /// The visible part's top edge, relative to the frame.
    clip_y: i32 = 0,
    /// The visible part's width.
    clip_width: i32 = 0,
    /// The visible part's height.
    clip_height: i32 = 0,
    /// The corner radius, in pixels.
    radius: i32 = 0,

    /// Reports whether two placements put the window in the same place with
    /// the same clip.
    ///
    /// - `self`: the placement.
    /// - `other`: the other one.
    /// - Returns: true when nothing changed.
    fn eql(self: *const Self, other: Self) bool {
        return std.meta.eql(self.*, other);
    }
};

/// One app window and where it was placed.
const Host = struct {
    const Self = @This();

    /// The app's child window.
    window: mod.HWND,
    /// The window is hidden.
    hidden: bool = true,
    /// What was last applied, to skip unchanged frames (moving a window
    /// repaints it).
    placement: Placement = .{},
    /// The placement has been applied once.
    placed: bool = false,
    /// The part on screen last placed, in the window's points.
    visible: renderer.Rect = .{},
    /// The frame (`Win32NativeHost.frame_number`) it was last shown in.
    shown_in_frame: u64 = 0,
};

/// The Windows host behind every `NativeView`.
pub const Win32NativeHost = struct {
    const Self = @This();

    /// The host places views over the window's surface.
    pub const presents = true;

    /// The window property a view in another process sets (to any non-null
    /// value) on its handle while it holds the keyboard.
    pub const focus_property = std.unicode.utf8ToUtf16LeStringLiteral("ZigguiNativeFocus");

    /// `SWP_NOACTIVATE`.
    const swp_no_activate: u32 = 0x10;
    /// `SWP_SHOWWINDOW`.
    const swp_show_window: u32 = 0x40;
    /// `SWP_NOZORDER`.
    const swp_no_z_order: u32 = 0x4;
    /// `SW_HIDE`.
    const sw_hide: i32 = 0;
    /// `RGN_AND`.
    const rgn_and: i32 = 1;
    /// `WS_POPUP`.
    const ws_popup: u32 = 0x80000000;
    /// `WS_EX_TOOLWINDOW`: no taskbar button for the parking window.
    const ws_ex_tool_window: u32 = 0x80;

    /// The views placed so far, in the order they first appeared.
    var hosts: [max_hosts]Host = undefined;

    /// How many of `hosts` are live.
    var host_count: usize = 0;

    /// Counts `present` calls, so a view not shown in the latest is hidden.
    var frame_number: u64 = 0;

    /// SDL's window, once a view was placed in it.
    var sdl_window: mod.HWND = null;

    /// The hidden window the views live under while not placed.
    var parking: mod.HWND = null;

    /// Every view is hidden for an open overlay.
    var suppressed: bool = false;

    /// The view that held the keyboard when an overlay hid it.
    var refocus: mod.HWND = null;

    /// The hidden top-level window views are made under and go back to when
    /// the main window goes, so they outlive it as the app's views do.
    ///
    /// - Returns: the window, or null when Windows refused to make it.
    pub fn parkingWindow() mod.HWND {
        if (parking) |window| if (IsWindow(window) != 0) return window;
        const instance = mod.Win32.GetModuleHandleW(null);
        const class_name = std.unicode.utf8ToUtf16LeStringLiteral("ZigguiNativeParking");
        _ = mod.Win32.RegisterClassExW(&.{ .lpfnWndProc = mod.Win32.DefWindowProcW, .hInstance = instance, .lpszClassName = class_name });
        parking = mod.Win32.CreateWindowExW(Self.ws_ex_tool_window, class_name, null, Self.ws_popup, 0, 0, 1, 1, null, null, instance, null);
        if (parking == null) log.warn("parking window not made", .{});
        return parking;
    }

    /// Puts each region's view where its `NativeView` is, and hides every view
    /// no `NativeView` showed this frame, or all of them while an overlay is
    /// open. Runs on the UI thread after the view tree painted.
    ///
    /// - `window`: the main window.
    /// - `regions`: the frame's `NativeView` regions, in points.
    /// - `overlay_open`: a sheet, alert, popover or menu is drawn this frame.
    pub fn present(window: *sdl_c.SDL_Window, regions: []const views.NativeRegion, overlay_open: bool) void {
        frame_number += 1;
        if (regions.len == 0 and host_count == 0) return;
        const parent: mod.HWND = sdl_c.SDL_GetPointerProperty(sdl_c.SDL_GetWindowProperties(window), sdl_c.SDL_PROP_WINDOW_WIN32_HWND_POINTER, null);
        if (parent == null) return;
        sdl_window = parent;
        const display_scale = sdl_c.SDL_GetWindowDisplayScale(window);
        const scale: f32 = if (display_scale > 0) display_scale else 1;

        // An overlay opening takes the keyboard from the view, to give back
        // when it closes.
        if (overlay_open and !suppressed) {
            suppressed = true;
            refocus = Self.focusedHost();
            if (refocus != null) Self.release();
        }
        const reopening = !overlay_open and suppressed;
        if (reopening) suppressed = false;

        for (regions) |region| {
            const host = Self.hostFor(region.handle) orelse continue;
            host.shown_in_frame = frame_number;
            if (!suppressed) Self.place(host, parent, region, scale);
        }
        var index: usize = 0;
        while (index < host_count) {
            const host = &hosts[index];
            // The app destroyed its window: the host goes too.
            if (IsWindow(host.window) == 0) {
                Self.drop(index);
                continue;
            }
            if (suppressed or host.shown_in_frame != frame_number) Self.hide(host);
            index += 1;
        }

        if (reopening) {
            // The overlay took the keyboard (`release`), so the view holds it
            // no longer: it gets it back while it is still placed and shown.
            if (refocus) |held| if (Self.shows(held)) {
                _ = SetFocus(held);
            };
            refocus = null;
        }
    }

    /// Reports whether one of the placed views, or a window inside one, holds
    /// the keyboard.
    ///
    /// - Returns: true while a placed view holds the keyboard.
    pub fn hasFocus() bool {
        return Self.focusedHost() != null;
    }

    /// Hands the keyboard back to SDL's window when a placed view holds it.
    pub fn release() void {
        const focused = Self.focusedHost() orelse return;
        _ = mod.Win32.RemovePropW(focused, Self.focus_property);
        if (sdl_window) |window| _ = SetFocus(window);
    }

    /// Never takes an editing key: the view's own window gets every key,
    /// Ctrl+C and the rest included, before SDL could.
    ///
    /// - `keycode`: the key's `SDL_Keycode`; unused.
    /// - `modifiers`: its `SDL_Keymod` mask; unused.
    /// - Returns: false.
    pub fn performEdit(keycode: u32, modifiers: u16) bool {
        _ = keycode;
        _ = modifiers;
        return false;
    }

    /// Reports whether a point falls on a shown view.
    ///
    /// - `point`: the point, in the window's points.
    /// - Returns: true over a shown view.
    pub fn contains(point: renderer.Point) bool {
        for (hosts[0..host_count]) |*host| {
            if (!host.hidden and host.visible.contains(point)) return true;
        }
        return false;
    }

    /// Takes every view out of the main window, back under the parking
    /// window: the loop is ending, and the window goes before the app's views.
    pub fn detachAll() void {
        while (host_count > 0) Self.drop(host_count - 1);
        sdl_window = null;
        refocus = null;
        suppressed = false;
    }

    /// No toolkit loop runs inside SDL's (WebView2 runs on SDL's own message
    /// pump): nothing to do.
    ///
    /// - Returns: null: the wait is not limited.
    pub fn beforeWait() ?u32 {
        return null;
    }

    /// No toolkit loop runs inside SDL's: nothing to do.
    pub fn afterWait() void {}

    /// No toolkit wakes the loop.
    ///
    /// - `event_type`: the event's type.
    /// - Returns: false.
    pub fn isWake(event_type: u32) bool {
        _ = event_type;
        return false;
    }

    /// The host of a view, added (hidden) the first time the view is shown.
    ///
    /// - `handle`: the view's `HWND`.
    /// - Returns: the host, or null when the window is gone or the table is full.
    fn hostFor(handle: *anyopaque) ?*Host {
        for (hosts[0..host_count]) |*host| {
            if (host.window == handle) return host;
        }
        if (IsWindow(handle) == 0) return null;
        if (host_count == max_hosts) {
            log.warn("more than {d} native views; the rest are not placed", .{max_hosts});
            return null;
        }
        hosts[host_count] = .{ .window = handle };
        host_count += 1;
        return &hosts[host_count - 1];
    }

    /// Moves a host's window into the main window, frames it on its region
    /// and clips it to the visible part, rounded at the corners.
    ///
    /// - `host`: the host.
    /// - `parent`: SDL's window.
    /// - `region`: where its `NativeView` is, in points.
    /// - `scale`: pixels per point.
    fn place(host: *Host, parent: mod.HWND, region: views.NativeRegion, scale: f32) void {
        if (region.visible.width <= 0 or region.visible.height <= 0) {
            Self.hide(host);
            return;
        }
        if (GetParent(host.window) != parent) {
            _ = SetParent(host.window, parent);
            host.placed = false;
        }
        const x = Self.pixels(region.rect.x, scale);
        const y = Self.pixels(region.rect.y, scale);
        const right = Self.pixels(region.rect.x + region.rect.width, scale);
        const bottom = Self.pixels(region.rect.y + region.rect.height, scale);
        const clip_left = Self.pixels(region.visible.x, scale) - x;
        const clip_top = Self.pixels(region.visible.y, scale) - y;
        const placement = Placement{
            .x = x,
            .y = y,
            .width = right - x,
            .height = bottom - y,
            .clip_x = clip_left,
            .clip_y = clip_top,
            .clip_width = Self.pixels(region.visible.x + region.visible.width, scale) - x - clip_left,
            .clip_height = Self.pixels(region.visible.y + region.visible.height, scale) - y - clip_top,
            .radius = Self.pixels(region.corner_radius, scale),
        };
        host.visible = region.visible;
        if (host.placed and placement.eql(host.placement) and !host.hidden) return;
        host.placement = placement;
        host.placed = true;
        host.hidden = false;
        _ = SetWindowRgn(host.window, Self.clipRegion(placement), 1);
        _ = SetWindowPos(host.window, null, placement.x, placement.y, placement.width, placement.height, Self.swp_no_activate | Self.swp_show_window | Self.swp_no_z_order);
    }

    /// The window region for a placement: the visible part, intersected with
    /// the frame's rounded corners. Windows owns it once set.
    ///
    /// - `placement`: the frame and clip.
    /// - Returns: the region, or null for the whole window (no clip, square
    ///   corners).
    fn clipRegion(placement: Placement) HRGN {
        const whole = placement.clip_x == 0 and placement.clip_y == 0 and
            placement.clip_width == placement.width and placement.clip_height == placement.height;
        if (whole and placement.radius == 0) return null;
        const clip = CreateRectRgn(placement.clip_x, placement.clip_y, placement.clip_x + placement.clip_width, placement.clip_y + placement.clip_height);
        if (placement.radius == 0) return clip;
        const diameter = placement.radius * 2;
        const rounded = CreateRoundRectRgn(0, 0, placement.width + 1, placement.height + 1, diameter, diameter);
        defer _ = mod.Win32.DeleteObject(rounded);
        _ = CombineRgn(clip, clip, rounded, Self.rgn_and);
        return clip;
    }

    /// Hides a host's window.
    ///
    /// - `host`: the host.
    fn hide(host: *Host) void {
        if (host.hidden) return;
        host.hidden = true;
        if (Self.holds(host.window) and sdl_window != null) _ = SetFocus(sdl_window);
        _ = ShowWindow(host.window, Self.sw_hide);
    }

    /// Takes a host's window back under the parking window and forgets it.
    ///
    /// - `index`: the host's index in `hosts`.
    fn drop(index: usize) void {
        const host = hosts[index];
        if (IsWindow(host.window) != 0) {
            _ = ShowWindow(host.window, Self.sw_hide);
            _ = SetParent(host.window, Self.parkingWindow());
        }
        if (refocus == host.window) refocus = null;
        @memmove(hosts[index .. host_count - 1], hosts[index + 1 .. host_count]);
        host_count -= 1;
    }

    /// The placed view holding the keyboard, if any.
    ///
    /// - Returns: its window, or null.
    fn focusedHost() mod.HWND {
        for (hosts[0..host_count]) |*host| {
            if (!host.hidden and Self.holds(host.window)) return host.window;
        }
        return null;
    }

    /// Reports whether a view's window is still a placed host on show.
    ///
    /// - `window`: the view's window.
    /// - Returns: true when it lives and its host is not hidden.
    fn shows(window: mod.HWND) bool {
        if (IsWindow(window) == 0) return false;
        for (hosts[0..host_count]) |*host| {
            if (host.window == window) return !host.hidden;
        }
        return false;
    }

    /// Reports whether a view's window, or one inside it, holds the keyboard.
    ///
    /// - `window`: the view's window.
    /// - Returns: true when it does.
    fn holds(window: mod.HWND) bool {
        if (GetPropW(window, Self.focus_property) != null) return true;
        const focused = GetFocus() orelse return false;
        return focused == window or IsChild(window, focused) != 0;
    }

    /// Converts points to whole client pixels.
    ///
    /// - `points`: the length or coordinate, in points.
    /// - `scale`: pixels per point.
    /// - Returns: the pixels, rounded.
    fn pixels(points: f32, scale: f32) i32 {
        return @intFromFloat(@round(points * scale));
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "win32 native host: nothing placed covers no point" {
    try std.testing.expect(Win32NativeHost.presents);
    try std.testing.expect(!Win32NativeHost.contains(.{ .x = 1, .y = 1 }));
}
