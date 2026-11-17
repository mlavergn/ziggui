//! The Linux native-view host: each app `GtkWidget` a `NativeView` shows sits
//! in a borderless GTK window made an X11 child of SDL's window, framed each
//! frame from its `NativeRegion`. Being a window above the surface, nothing
//! ziggui draws can cover it, so while an overlay is open every one is
//! hidden, and the view that held the keyboard gets it back when the overlay
//! closes.
//!
//! The X server sends a press on a placed view to the view's window, never
//! SDL's, so clicks need no absorbing; a press there also moves the X input
//! focus to that window (`claim`), so keys go to the view and never reach
//! SDL. X sends a key to the window under the pointer when that window is
//! inside the focused one, so a view's window listens for keys only while it
//! holds the keyboard (`listenForKeys`): typing in a ziggui field with the
//! pointer resting on a view still reaches the field. GTK's key bindings
//! give the view its copy, cut, paste and select-all, so `performEdit` has
//! nothing to do; a key with Ctrl (or Super) is offered to the app's key
//! handler first, as the loop offers it on macOS. A press on
//! ziggui's own surface hands the focus back (`release`). After the user
//! leaves the window and comes back, the window manager focuses SDL's window,
//! and the next frame hands the focus back to the view that held it.
//!
//! GTK starts here on first need (`toolkit`), with the GLib pump around the
//! loop's waits and GDK's events passing through `filterEvent` first. Only
//! where SDL's window is on X11; elsewhere nothing is placed. Corners are
//! square: an X11 window has no radius. Linux only; other targets reach it
//! only behind `os_tag == .linux`.

const std = @import("std");
const log = std.log.scoped(.ziggui_gtk_native_host);
const mod = @import("module.zig");
const renderer = @import("renderer");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// How many platform views one window places at once.
const max_hosts = 16;

/// One app widget and the window that places and clips it.
const Host = struct {
    const Self = @This();

    /// The app's `GtkWidget`, referenced while placed: the app may take it
    /// out and drop it between frames.
    view: *anyopaque,
    /// The popup `GtkWindow` holding it, an X11 child of SDL's window.
    window: *anyopaque,
    /// The `GtkLayout` inside the window, where the view sits at an offset
    /// (a layout asks for no room of its own, so a view cut by a scroll view
    /// never grows the window).
    layout: *anyopaque,
    /// The window's X11 id.
    xid: c_ulong,
    /// The window is hidden.
    hidden: bool = true,
    /// The part on screen last placed, in the window's points.
    visible: renderer.Rect = .{},
    /// The window's frame last set, in GTK units: x, y, width, height.
    window_frame: [4]c_int = @splat(-1),
    /// The view's frame last set inside the window, in GTK units.
    view_frame: [4]c_int = @splat(-1),
    /// The frame (`GtkNativeHost.frame_number`) it was last shown in.
    shown_in_frame: u64 = 0,
};

/// The Linux host behind every `NativeView`.
pub const GtkNativeHost = struct {
    const Self = @This();

    /// The host places views over the window's surface (where SDL is on X11).
    pub const presents = true;

    /// The views placed so far, in the order they first appeared.
    var hosts: [max_hosts]Host = undefined;

    /// How many of `hosts` are live.
    var host_count: usize = 0;

    /// Counts `present` calls, so a view not shown in the latest is hidden.
    var frame_number: u64 = 0;

    /// SDL's window the views are placed in, once one was.
    var sdl_window: ?*sdl_c.SDL_Window = null;

    /// SDL's window's X11 id, once one was placed.
    var sdl_xid: c_ulong = 0;

    /// Every window is hidden for an open overlay.
    var suppressed: bool = false;

    /// The view whose window holds (or last held) the keyboard, until a
    /// press on ziggui's surface releases it.
    var holder: ?*anyopaque = null;

    /// The view that held the keyboard when an overlay hid it, to refocus
    /// when the overlay closes.
    var refocus: ?*anyopaque = null;

    /// GDK's events pass through `filterEvent`.
    var filtering: bool = false;

    /// Starts GTK, the GLib pump and the event filter on first call.
    ///
    /// - Returns: GTK's entry points, or null where GTK cannot run (SDL not
    ///   on X11, the libraries missing).
    pub fn toolkit() ?*const mod.GtkApi {
        const api = mod.Gtk.start() orelse return null;
        if (!filtering) {
            filtering = true;
            if (!mod.GlibPump.shared().start(api)) log.warn("GLib runs on a timer: its watcher did not start", .{});
            api.gdk_event_handler_set(Self.filterEvent, null, null);
        }
        return api;
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
        const api = Self.toolkit() orelse return;
        const xid = sdl_c.SDL_GetNumberProperty(sdl_c.SDL_GetWindowProperties(window), sdl_c.SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
        if (xid == 0) return;
        sdl_window = window;
        sdl_xid = @intCast(xid);

        // An overlay opening takes the keyboard from the view, to give back
        // when it closes.
        if (overlay_open and !suppressed) {
            suppressed = true;
            refocus = if (Self.hasFocus()) holder else null;
            Self.release();
        }
        const reopening = !overlay_open and suppressed;
        if (reopening) suppressed = false;

        // Points to GTK units: SDL lays out at the display scale, GTK at its own.
        const display_scale = sdl_c.SDL_GetWindowDisplayScale(window);
        const pixels_per_point: f32 = if (display_scale > 0) display_scale else 1;
        for (regions) |region| {
            const host = Self.hostFor(api, region.handle) orelse continue;
            host.shown_in_frame = frame_number;
            if (!suppressed) Self.place(api, host, region, pixels_per_point);
        }
        var index: usize = 0;
        while (index < host_count) {
            const host = &hosts[index];
            // The app took its widget out of the layout: the host goes too.
            if (api.gtk_widget_get_parent(host.view) != host.layout) {
                Self.drop(api, index);
                continue;
            }
            if (suppressed or host.shown_in_frame != frame_number) Self.hide(api, host);
            index += 1;
        }

        if (reopening) {
            if (refocus) |view| if (Self.hostOfView(view)) |host| if (!host.hidden) {
                // In the background the view only becomes the holder again,
                // to take the keyboard back once the user returns (below).
                if (sdl_c.SDL_GetKeyboardFocus() == window) Self.claim(api, host) else holder = view;
            };
            refocus = null;
        }
        // Back from another window: the window manager focused SDL's window,
        // and the view that held the keyboard takes it back.
        if (!suppressed and holder != null and sdl_c.SDL_GetKeyboardFocus() == window and !Self.hasFocus()) {
            if (Self.hostOfView(holder.?)) |host| {
                if (!host.hidden) Self.claim(api, host);
            }
        }
        mod.Gtk.flush();
    }

    /// Reports whether one of the placed views' windows has the X input focus.
    ///
    /// - Returns: true while a placed view holds the keyboard.
    pub fn hasFocus() bool {
        const api = mod.Gtk.running() orelse return false;
        const view = holder orelse return false;
        const host = Self.hostOfView(view) orelse return false;
        const x_display = mod.Gtk.display() orelse return false;
        var focused: c_ulong = 0;
        var revert: c_int = 0;
        _ = api.XGetInputFocus(x_display, &focused, &revert);
        return focused == host.xid;
    }

    /// Hands the keyboard back to SDL's window when a placed view holds it;
    /// a press on ziggui's own surface calls this. The X input focus moves
    /// only while the view has it: once the user went to another
    /// application, that one stays focused (a view hidden or dropped on a
    /// frame drawn in the background must not pull the focus back).
    pub fn release() void {
        const api = mod.Gtk.running() orelse return;
        const focused = Self.hasFocus();
        const view = holder orelse return;
        holder = null;
        const host = Self.hostOfView(view) orelse return;
        Self.sendFocus(api, host, false);
        Self.listenForKeys(api, host, false);
        if (focused and sdl_xid != 0) {
            if (mod.Gtk.display()) |x_display| {
                mod.Gtk.trapErrors();
                _ = api.XSetInputFocus(x_display, sdl_xid, mod.Gtk.revert_to_parent, 0);
                mod.Gtk.untrapErrors();
            }
        }
        mod.Gtk.flush();
    }

    /// Nothing to send: keys reach the view itself, and GTK's key bindings
    /// copy, cut, paste and select there.
    ///
    /// - `keycode`: the key's `SDL_Keycode`.
    /// - `modifiers`: its `SDL_Keymod` mask.
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

    /// Takes every window out of SDL's: the loop is ending, and SDL's window
    /// goes before the app's views do.
    pub fn detachAll() void {
        const api = mod.Gtk.running() orelse return;
        Self.release();
        while (host_count > 0) Self.drop(api, host_count - 1);
        mod.Gtk.flush();
        sdl_window = null;
        sdl_xid = 0;
        holder = null;
        refocus = null;
        suppressed = false;
    }

    /// Runs GLib's ready work and hands its descriptors to the watcher; the
    /// loop calls it before each wait.
    ///
    /// - Returns: the longest the wait may last, in milliseconds, or null for
    ///   no limit (`GlibPump.beforeWait`).
    pub fn beforeWait() ?u32 {
        return mod.GlibPump.shared().beforeWait();
    }

    /// Takes GLib's descriptors back and runs its ready work; the loop calls
    /// it after each wait.
    pub fn afterWait() void {
        mod.GlibPump.shared().afterWait();
    }

    /// Reports whether an SDL event only woke the loop for GLib.
    ///
    /// - `event_type`: the event's type.
    /// - Returns: true for the GLib watcher's event, which asks for no frame.
    pub fn isWake(event_type: u32) bool {
        return mod.GlibPump.shared().isWake(event_type);
    }

    /// GDK's event handler: a press in a placed view's window gives it the
    /// keyboard, and a key with Ctrl or Super there goes to the app's key
    /// handler first; then GTK handles the event as usual.
    ///
    /// - `event`: the `GdkEvent`.
    /// - `data`: unused.
    fn filterEvent(event: *anyopaque, data: ?*anyopaque) callconv(.c) void {
        _ = data;
        const api = mod.Gtk.running() orelse return;
        const any: *const mod.GdkEventAny = @ptrCast(@alignCast(event));
        if (any.window) |gdk_window| if (Self.hostOfGdkWindow(api, gdk_window)) |host| {
            if (any.type == mod.Gtk.event_button_press) {
                Self.claim(api, host);
                // The press never reached ziggui, so its field would keep a caret.
                views.Focus.shared().clear();
                mod.App.shared().wake();
            } else if (any.type == mod.Gtk.event_key_press) {
                const key: *const mod.GdkEventKey = @ptrCast(@alignCast(event));
                if (Self.offerKey(key)) return;
            }
        };
        api.gtk_main_do_event(event);
    }

    /// Offers a key pressed in a placed view to the app's key handler, when
    /// it carries Ctrl or Super (an app's shortcut).
    ///
    /// - `key`: the key event.
    /// - Returns: true when the handler consumed it, so the view never sees it.
    fn offerKey(key: *const mod.GdkEventKey) bool {
        if ((key.state & (mod.Gtk.control_mask | mod.Gtk.super_mask)) == 0) return false;
        const handler = mod.App.shared().key_handler orelse return false;
        const keycode = Self.keycodeOf(key.keyval) orelse return false;
        if (!handler(keycode, Self.modifiersOf(key.state))) return false;
        mod.App.shared().wake();
        return true;
    }

    /// The SDL keycode of a GDK key symbol: printable ASCII as SDL names it
    /// (lowercase), and the few named keys a shortcut uses.
    ///
    /// - `keyval`: the `GDK_KEY_*` symbol.
    /// - Returns: the `SDL_Keycode`, or null for a key no shortcut uses.
    fn keycodeOf(keyval: c_uint) ?u32 {
        if (keyval >= 0x20 and keyval <= 0x7e) return std.ascii.toLower(@intCast(keyval));
        return switch (keyval) {
            mod.Gtk.key_return => sdl_c.SDLK_RETURN,
            mod.Gtk.key_escape => sdl_c.SDLK_ESCAPE,
            mod.Gtk.key_tab => sdl_c.SDLK_TAB,
            mod.Gtk.key_backspace => sdl_c.SDLK_BACKSPACE,
            mod.Gtk.key_delete => sdl_c.SDLK_DELETE,
            mod.Gtk.key_left => sdl_c.SDLK_LEFT,
            mod.Gtk.key_up => sdl_c.SDLK_UP,
            mod.Gtk.key_right => sdl_c.SDLK_RIGHT,
            mod.Gtk.key_down => sdl_c.SDLK_DOWN,
            else => null,
        };
    }

    /// The SDL modifier mask of a GDK one.
    ///
    /// - `state`: the `GdkModifierType` mask.
    /// - Returns: the `SDL_Keymod` mask, left-hand keys standing for either.
    fn modifiersOf(state: c_uint) u16 {
        var modifiers: u16 = 0;
        if ((state & mod.Gtk.shift_mask) != 0) modifiers |= @intCast(sdl_c.SDL_KMOD_LSHIFT);
        if ((state & mod.Gtk.control_mask) != 0) modifiers |= @intCast(sdl_c.SDL_KMOD_LCTRL);
        if ((state & mod.Gtk.alt_mask) != 0) modifiers |= @intCast(sdl_c.SDL_KMOD_LALT);
        if ((state & mod.Gtk.super_mask) != 0) modifiers |= @intCast(sdl_c.SDL_KMOD_LGUI);
        return modifiers;
    }

    /// Gives a placed view's window the X input focus, has it listen for
    /// keys and tells GTK it is active.
    ///
    /// - `api`: GTK's entry points.
    /// - `host`: the host.
    fn claim(api: *const mod.GtkApi, host: *Host) void {
        if (holder != null and holder.? != host.view) Self.release();
        holder = host.view;
        const x_display = mod.Gtk.display() orelse return;
        Self.listenForKeys(api, host, true);
        // Trapped: a window iconified since this frame began is not viewable.
        mod.Gtk.trapErrors();
        _ = api.XSetInputFocus(x_display, host.xid, mod.Gtk.revert_to_parent, 0);
        mod.Gtk.untrapErrors();
        Self.sendFocus(api, host, true);
        mod.Gtk.flush();
    }

    /// Turns a host's window's key events on or off: X hands a key to the
    /// window under the pointer when it sits inside the focused window, so a
    /// view not holding the keyboard would take keys typed into ziggui.
    ///
    /// - `api`: GTK's entry points.
    /// - `host`: the host.
    /// - `listening`: true to receive keys.
    fn listenForKeys(api: *const mod.GtkApi, host: *Host, listening: bool) void {
        const gdk_window = api.gtk_widget_get_window(host.window) orelse return;
        const events = api.gdk_window_get_events(gdk_window);
        const wanted = if (listening) events | mod.Gtk.key_masks else events & ~mod.Gtk.key_masks;
        if (wanted != events) api.gdk_window_set_events(gdk_window, wanted);
    }

    /// Tells a host's window it gained or lost the focus: a window the window
    /// manager never sees gets no focus events of its own, and WebKit draws
    /// no caret and takes no keys in a window GTK thinks inactive.
    ///
    /// - `api`: GTK's entry points.
    /// - `host`: the host.
    /// - `focused`: true when it gained the focus.
    fn sendFocus(api: *const mod.GtkApi, host: *Host, focused: bool) void {
        var event = mod.GdkEventFocus{
            .type = mod.Gtk.event_focus_change,
            .window = api.gtk_widget_get_window(host.window),
            .send_event = 1,
            .in = if (focused) 1 else 0,
        };
        if (event.window == null) return;
        _ = api.gtk_widget_send_focus_change(host.window, &event);
    }

    /// The host placing `view`, made on its first frame: a popup window
    /// realized and made a child of SDL's window, hidden until placed.
    ///
    /// - `api`: GTK's entry points.
    /// - `view`: the app's `GtkWidget`.
    /// - Returns: the host, or null when every slot is taken or GTK refused.
    fn hostFor(api: *const mod.GtkApi, view: *anyopaque) ?*Host {
        if (Self.hostOfView(view)) |host| return host;
        if (host_count == max_hosts) {
            log.warn("native view not placed: {d} are already shown", .{max_hosts});
            return null;
        }
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const x_display = mod.Gtk.display() orelse return null;
        const window = api.gtk_window_new(mod.Gtk.window_popup) orelse return null;
        const layout = api.gtk_layout_new(null, null) orelse {
            api.gtk_widget_destroy(window);
            return null;
        };
        api.gtk_container_add(window, layout);
        _ = api.g_object_ref(view);
        api.gtk_layout_put(layout, view, 0, 0);
        api.gtk_window_resize(window, 1, 1);
        api.gtk_widget_realize(window);
        const gdk_window = api.gtk_widget_get_window(window) orelse {
            // The app's widget leaves first: destroying a window destroys
            // what it holds, and the widget stays the app's (as in `drop`).
            api.gtk_container_remove(layout, view);
            api.gtk_widget_destroy(window);
            api.g_object_unref(view);
            return null;
        };
        // GDK waits after each frame for the compositor's `_NET_WM_FRAME_DRAWN`,
        // which never comes for a window inside another client's: its frame
        // clock would stop after the first frame, and the view never draw.
        api.gdk_x11_window_set_frame_sync_enabled(gdk_window, 0);
        const xid = api.gdk_x11_window_get_xid(gdk_window);
        log.debug("native view window 0x{x} placed in SDL's 0x{x}", .{ xid, sdl_xid });
        mod.Gtk.trapErrors();
        _ = api.XReparentWindow(x_display, xid, sdl_xid, 0, 0);
        mod.Gtk.untrapErrors();
        api.gtk_widget_show(layout);
        api.gtk_widget_show(view);
        hosts[host_count] = .{ .view = view, .window = window, .layout = layout, .xid = xid };
        host_count += 1;
        const host = &hosts[host_count - 1];
        Self.listenForKeys(api, host, false);
        return host;
    }

    /// Frames a host's window to the region's visible part and its view to
    /// the whole region inside it, then shows it.
    ///
    /// - `api`: GTK's entry points.
    /// - `host`: the host.
    /// - `region`: where its `NativeView` is this frame.
    /// - `pixels_per_point`: SDL's window pixels per point.
    fn place(api: *const mod.GtkApi, host: *Host, region: views.NativeRegion, pixels_per_point: f32) void {
        const visible = region.visible;
        if (visible.width <= 0 or visible.height <= 0) {
            Self.hide(api, host);
            return;
        }
        host.visible = visible;
        const gtk_scale: f32 = @floatFromInt(@max(api.gtk_widget_get_scale_factor(host.window), 1));
        const factor = pixels_per_point / gtk_scale;
        const window_frame = Self.frameOf(visible, factor);
        if (window_frame[2] <= 0 or window_frame[3] <= 0) {
            Self.hide(api, host);
            return;
        }
        if (!std.mem.eql(c_int, &window_frame, &host.window_frame)) {
            api.gtk_window_move(host.window, window_frame[0], window_frame[1]);
            api.gtk_window_resize(host.window, window_frame[2], window_frame[3]);
            host.window_frame = window_frame;
        }
        // The view's frame relative to the window, so a view cut by a scroll
        // view keeps its scrolled part out of sight.
        const whole = Self.frameOf(region.rect, factor);
        const view_frame = [4]c_int{ whole[0] - window_frame[0], whole[1] - window_frame[1], @max(whole[2], 1), @max(whole[3], 1) };
        if (!std.mem.eql(c_int, &view_frame, &host.view_frame)) {
            api.gtk_layout_move(host.layout, host.view, view_frame[0], view_frame[1]);
            api.gtk_widget_set_size_request(host.view, view_frame[2], view_frame[3]);
            host.view_frame = view_frame;
        }
        if (host.hidden) {
            api.gtk_widget_show(host.window);
            host.hidden = false;
        }
    }

    /// A rectangle in points as whole GTK units: x, y, width, height, the
    /// edges rounded so neighbors meet.
    ///
    /// - `rect`: the rectangle, in points.
    /// - `factor`: GTK units per point.
    /// - Returns: the frame.
    fn frameOf(rect: renderer.Rect, factor: f32) [4]c_int {
        const left: c_int = @intFromFloat(@round(rect.x * factor));
        const top: c_int = @intFromFloat(@round(rect.y * factor));
        const right: c_int = @intFromFloat(@round((rect.x + rect.width) * factor));
        const bottom: c_int = @intFromFloat(@round((rect.y + rect.height) * factor));
        return .{ left, top, right - left, bottom - top };
    }

    /// Hides a host's window, handing the keyboard back to SDL first when its
    /// view held it.
    ///
    /// - `api`: GTK's entry points.
    /// - `host`: the host.
    fn hide(api: *const mod.GtkApi, host: *Host) void {
        if (host.hidden) return;
        if (holder == host.view) Self.release();
        api.gtk_widget_hide(host.window);
        host.hidden = true;
        host.visible = .{};
    }

    /// Destroys a host's window and frees its slot. The app's widget leaves
    /// the window first, and stays the app's.
    ///
    /// - `api`: GTK's entry points.
    /// - `index`: the host's slot.
    fn drop(api: *const mod.GtkApi, index: usize) void {
        const host = &hosts[index];
        if (holder == host.view) Self.release();
        if (refocus == host.view) refocus = null;
        if (api.gtk_widget_get_parent(host.view) == host.layout) api.gtk_container_remove(host.layout, host.view);
        api.gtk_widget_destroy(host.window);
        api.g_object_unref(host.view);
        hosts[index] = hosts[host_count - 1];
        host_count -= 1;
    }

    /// The host placing a widget.
    ///
    /// - `view`: the app's `GtkWidget`.
    /// - Returns: its host, or null.
    fn hostOfView(view: *anyopaque) ?*Host {
        for (hosts[0..host_count]) |*host| {
            if (host.view == view) return host;
        }
        return null;
    }

    /// The host whose window holds a `GdkWindow` (its own or a child's).
    ///
    /// - `api`: GTK's entry points.
    /// - `gdk_window`: the `GdkWindow` an event came in.
    /// - Returns: its host, or null for any other window.
    fn hostOfGdkWindow(api: *const mod.GtkApi, gdk_window: *anyopaque) ?*Host {
        if (host_count == 0) return null;
        const toplevel = api.gdk_window_get_toplevel(gdk_window) orelse return null;
        for (hosts[0..host_count]) |*host| {
            if (api.gtk_widget_get_window(host.window) == toplevel) return host;
        }
        return null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "with nothing placed the GTK host holds no focus and no point" {
    try std.testing.expect(GtkNativeHost.presents);
    try std.testing.expect(!GtkNativeHost.hasFocus());
    try std.testing.expect(!GtkNativeHost.contains(.{ .x = 10, .y = 10 }));
    try std.testing.expect(!GtkNativeHost.performEdit(sdl_c.SDLK_C, @intCast(sdl_c.SDL_KMOD_LCTRL)));
}

test "GTK host maps shortcut keys to SDL's" {
    try std.testing.expectEqual(@as(?u32, 'q'), GtkNativeHost.keycodeOf('Q'));
    try std.testing.expectEqual(@as(?u32, 'l'), GtkNativeHost.keycodeOf('l'));
    try std.testing.expectEqual(@as(?u32, sdl_c.SDLK_RETURN), GtkNativeHost.keycodeOf(mod.Gtk.key_return));
    // `GDK_KEY_F1`: a key no shortcut uses.
    try std.testing.expectEqual(@as(?u32, null), GtkNativeHost.keycodeOf(0xffbe));
    const modifiers = GtkNativeHost.modifiersOf(mod.Gtk.control_mask | mod.Gtk.shift_mask);
    try std.testing.expect((modifiers & sdl_c.SDL_KMOD_CTRL) != 0 and (modifiers & sdl_c.SDL_KMOD_SHIFT) != 0);
    try std.testing.expect((modifiers & sdl_c.SDL_KMOD_ALT) == 0);
}

test "GTK host rounds a frame's edges" {
    const frame = GtkNativeHost.frameOf(.{ .x = 10.4, .y = 20.6, .width = 100.2, .height = 50.1 }, 1);
    try std.testing.expectEqual([4]c_int{ 10, 21, 101, 50 }, frame);
    const doubled = GtkNativeHost.frameOf(.{ .x = 10, .y = 20, .width = 100, .height = 50 }, 2);
    try std.testing.expectEqual([4]c_int{ 20, 40, 200, 100 }, doubled);
}
