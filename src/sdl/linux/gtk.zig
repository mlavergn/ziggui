//! GTK 3, WebKitGTK (the 4.1 API, on libsoup 3) and the few GLib, GDK and
//! Xlib calls the Linux web view and native-view host make, all resolved at
//! run time (as `StatusNotifier` resolves libdbus), so a ziggui app links
//! none of them and runs where they are missing: only a `WebPage` then fails.
//!
//! GTK 3, not 4: SDL's own tray loads GTK 3 into the process (`SDL_gtk.c`),
//! and one process cannot hold two GTK majors. GTK 4 also cannot place a
//! window inside a foreign one, which the native-view host does on X11.
//!
//! GTK starts on first need (`start`), on the UI thread, and only where SDL
//! drew its window on X11 (XWayland included): a GTK window can sit inside
//! SDL's only as an X11 child window. GDK is pinned to X11 for that reason.

const std = @import("std");
const log = std.log.scoped(.ziggui_gtk);
const mod = @import("module.zig");
const sdl_c = @import("sdl_c");

/// GLib's `gboolean`.
pub const Gboolean = c_int;

/// GLib's `GPollFD`: the same layout as `struct pollfd` on Linux.
pub const GpollFd = extern struct {
    const Self = @This();

    /// The file descriptor.
    fd: c_int,
    /// The events to poll for.
    events: c_ushort,
    /// The events that happened.
    revents: c_ushort,
};

/// GLib's `GError`.
pub const Gerror = extern struct {
    const Self = @This();

    /// The error's domain (a `GQuark`).
    domain: u32,
    /// The error's code within its domain.
    code: c_int,
    /// What went wrong, in words.
    message: ?[*:0]const u8,
};

/// The fields every `GdkEvent` starts with (`GdkEventAny`).
pub const GdkEventAny = extern struct {
    const Self = @This();

    /// The `GdkEventType`.
    type: c_int,
    /// The `GdkWindow` it happened in.
    window: ?*anyopaque,
    /// Whether it was sent by another client.
    send_event: i8,
};

/// GDK's `GdkEventKey`, as far as the host reads it.
pub const GdkEventKey = extern struct {
    const Self = @This();

    /// The `GdkEventType`.
    type: c_int,
    /// The `GdkWindow` it happened in.
    window: ?*anyopaque,
    /// Whether it was sent by another client.
    send_event: i8,
    /// The server time of the event.
    time: u32,
    /// The `GdkModifierType` mask held.
    state: c_uint,
    /// The key's symbol (`GDK_KEY_*`).
    keyval: c_uint,
};

/// GDK's `GdkEventFocus`, which `gtk_widget_send_focus_change` takes.
pub const GdkEventFocus = extern struct {
    const Self = @This();

    /// `GDK_FOCUS_CHANGE`.
    type: c_int,
    /// The `GdkWindow` gaining or losing focus.
    window: ?*anyopaque,
    /// Whether it was sent by another client.
    send_event: i8,
    /// 1 for focus in, 0 for focus out.
    in: i16,
};

/// The entry points resolved, by library. Each field mirrors the C function
/// of its name (with the library's prefix), so they keep its spelling.
pub const GtkApi = struct {
    const Self = @This();

    // GLib.
    /// `g_main_context_default`, resolved from its library.
    g_main_context_default: *const fn () callconv(.c) ?*anyopaque,
    /// `g_main_context_acquire`, resolved from its library.
    g_main_context_acquire: *const fn (?*anyopaque) callconv(.c) Gboolean,
    /// `g_main_context_prepare`, resolved from its library.
    g_main_context_prepare: *const fn (?*anyopaque, *c_int) callconv(.c) Gboolean,
    /// `g_main_context_query`, resolved from its library.
    g_main_context_query: *const fn (?*anyopaque, c_int, *c_int, [*]GpollFd, c_int) callconv(.c) c_int,
    /// `g_main_context_iteration`, resolved from its library.
    g_main_context_iteration: *const fn (?*anyopaque, Gboolean) callconv(.c) Gboolean,
    /// `g_idle_add`, resolved from its library.
    g_idle_add: *const fn (*const fn (?*anyopaque) callconv(.c) Gboolean, ?*anyopaque) callconv(.c) c_uint,
    /// `g_free`, resolved from its library.
    g_free: *const fn (?*anyopaque) callconv(.c) void,
    // GObject.
    /// `g_object_ref`, resolved from its library.
    g_object_ref: *const fn (*anyopaque) callconv(.c) *anyopaque,
    /// `g_object_ref_sink`, resolved from its library.
    g_object_ref_sink: *const fn (*anyopaque) callconv(.c) *anyopaque,
    /// `g_object_unref`, resolved from its library.
    g_object_unref: *const fn (*anyopaque) callconv(.c) void,
    /// `g_signal_connect_data`, resolved from its library.
    g_signal_connect_data: *const fn (*anyopaque, [*:0]const u8, *const anyopaque, ?*anyopaque, ?*const anyopaque, c_int) callconv(.c) c_ulong,
    /// `g_signal_handlers_disconnect_matched`, resolved from its library.
    g_signal_handlers_disconnect_matched: *const fn (*anyopaque, c_int, c_uint, u32, ?*anyopaque, ?*const anyopaque, ?*anyopaque) callconv(.c) c_uint,
    // GDK.
    /// `gdk_set_allowed_backends`, resolved from its library.
    gdk_set_allowed_backends: *const fn ([*:0]const u8) callconv(.c) void,
    /// `gdk_event_handler_set`, resolved from its library.
    gdk_event_handler_set: *const fn (*const fn (*anyopaque, ?*anyopaque) callconv(.c) void, ?*anyopaque, ?*const anyopaque) callconv(.c) void,
    /// `gdk_window_get_toplevel`, resolved from its library.
    gdk_window_get_toplevel: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    /// `gdk_x11_window_get_xid`, resolved from its library.
    gdk_x11_window_get_xid: *const fn (*anyopaque) callconv(.c) c_ulong,
    /// `gdk_x11_window_set_frame_sync_enabled`, resolved from its library.
    gdk_x11_window_set_frame_sync_enabled: *const fn (*anyopaque, Gboolean) callconv(.c) void,
    /// `gdk_display_get_default`, resolved from its library.
    gdk_display_get_default: *const fn () callconv(.c) ?*anyopaque,
    /// `gdk_x11_display_get_xdisplay`, resolved from its library.
    gdk_x11_display_get_xdisplay: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    /// `gdk_display_flush`, resolved from its library.
    gdk_display_flush: *const fn (*anyopaque) callconv(.c) void,
    /// `gdk_window_get_events`, resolved from its library.
    gdk_window_get_events: *const fn (*anyopaque) callconv(.c) c_int,
    /// `gdk_window_set_events`, resolved from its library.
    gdk_window_set_events: *const fn (*anyopaque, c_int) callconv(.c) void,
    /// `gdk_x11_display_error_trap_push`, resolved from its library.
    gdk_x11_display_error_trap_push: *const fn (*anyopaque) callconv(.c) void,
    /// `gdk_x11_display_error_trap_pop_ignored`, resolved from its library.
    gdk_x11_display_error_trap_pop_ignored: *const fn (*anyopaque) callconv(.c) void,
    // GTK.
    /// `gtk_init_check`, resolved from its library.
    gtk_init_check: *const fn (?*c_int, ?*anyopaque) callconv(.c) Gboolean,
    /// `gtk_main_do_event`, resolved from its library.
    gtk_main_do_event: *const fn (*anyopaque) callconv(.c) void,
    /// `gtk_window_new`, resolved from its library.
    gtk_window_new: *const fn (c_int) callconv(.c) ?*anyopaque,
    /// `gtk_window_move`, resolved from its library.
    gtk_window_move: *const fn (*anyopaque, c_int, c_int) callconv(.c) void,
    /// `gtk_window_resize`, resolved from its library.
    gtk_window_resize: *const fn (*anyopaque, c_int, c_int) callconv(.c) void,
    /// `gtk_layout_new`, resolved from its library.
    gtk_layout_new: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) ?*anyopaque,
    /// `gtk_layout_put`, resolved from its library.
    gtk_layout_put: *const fn (*anyopaque, *anyopaque, c_int, c_int) callconv(.c) void,
    /// `gtk_layout_move`, resolved from its library.
    gtk_layout_move: *const fn (*anyopaque, *anyopaque, c_int, c_int) callconv(.c) void,
    /// `gtk_container_add`, resolved from its library.
    gtk_container_add: *const fn (*anyopaque, *anyopaque) callconv(.c) void,
    /// `gtk_container_remove`, resolved from its library.
    gtk_container_remove: *const fn (*anyopaque, *anyopaque) callconv(.c) void,
    /// `gtk_widget_realize`, resolved from its library.
    gtk_widget_realize: *const fn (*anyopaque) callconv(.c) void,
    /// `gtk_widget_show`, resolved from its library.
    gtk_widget_show: *const fn (*anyopaque) callconv(.c) void,
    /// `gtk_widget_hide`, resolved from its library.
    gtk_widget_hide: *const fn (*anyopaque) callconv(.c) void,
    /// `gtk_widget_destroy`, resolved from its library.
    gtk_widget_destroy: *const fn (*anyopaque) callconv(.c) void,
    /// `gtk_widget_set_size_request`, resolved from its library.
    gtk_widget_set_size_request: *const fn (*anyopaque, c_int, c_int) callconv(.c) void,
    /// `gtk_widget_get_parent`, resolved from its library.
    gtk_widget_get_parent: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    /// `gtk_widget_get_window`, resolved from its library.
    gtk_widget_get_window: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    /// `gtk_widget_get_scale_factor`, resolved from its library.
    gtk_widget_get_scale_factor: *const fn (*anyopaque) callconv(.c) c_int,
    /// `gtk_widget_send_focus_change`, resolved from its library.
    gtk_widget_send_focus_change: *const fn (*anyopaque, *GdkEventFocus) callconv(.c) Gboolean,
    // WebKitGTK.
    /// `webkit_user_content_manager_new`, resolved from its library.
    webkit_user_content_manager_new: *const fn () callconv(.c) ?*anyopaque,
    /// `webkit_user_content_manager_register_script_message_handler_in_world`, resolved from its library.
    webkit_user_content_manager_register_script_message_handler_in_world: *const fn (*anyopaque, [*:0]const u8, [*:0]const u8) callconv(.c) Gboolean,
    /// `webkit_user_content_manager_unregister_script_message_handler_in_world`, resolved from its library.
    webkit_user_content_manager_unregister_script_message_handler_in_world: *const fn (*anyopaque, [*:0]const u8, [*:0]const u8) callconv(.c) void,
    /// `webkit_user_content_manager_add_script`, resolved from its library.
    webkit_user_content_manager_add_script: *const fn (*anyopaque, *anyopaque) callconv(.c) void,
    /// `webkit_user_content_manager_remove_all_scripts`, resolved from its library.
    webkit_user_content_manager_remove_all_scripts: *const fn (*anyopaque) callconv(.c) void,
    /// `webkit_user_script_new`, resolved from its library.
    webkit_user_script_new: *const fn ([*:0]const u8, c_int, c_int, ?*const anyopaque, ?*const anyopaque) callconv(.c) ?*anyopaque,
    /// `webkit_user_script_new_for_world`, resolved from its library.
    webkit_user_script_new_for_world: *const fn ([*:0]const u8, c_int, c_int, [*:0]const u8, ?*const anyopaque, ?*const anyopaque) callconv(.c) ?*anyopaque,
    /// `webkit_user_script_unref`, resolved from its library.
    webkit_user_script_unref: *const fn (*anyopaque) callconv(.c) void,
    /// `webkit_web_view_new_with_user_content_manager`, resolved from its library.
    webkit_web_view_new_with_user_content_manager: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    /// `webkit_web_view_load_uri`, resolved from its library.
    webkit_web_view_load_uri: *const fn (*anyopaque, [*:0]const u8) callconv(.c) void,
    /// `webkit_web_view_stop_loading`, resolved from its library.
    webkit_web_view_stop_loading: *const fn (*anyopaque) callconv(.c) void,
    /// `webkit_web_view_go_back`, resolved from its library.
    webkit_web_view_go_back: *const fn (*anyopaque) callconv(.c) void,
    /// `webkit_web_view_go_forward`, resolved from its library.
    webkit_web_view_go_forward: *const fn (*anyopaque) callconv(.c) void,
    /// `webkit_web_view_reload`, resolved from its library.
    webkit_web_view_reload: *const fn (*anyopaque) callconv(.c) void,
    /// `webkit_web_view_can_go_back`, resolved from its library.
    webkit_web_view_can_go_back: *const fn (*anyopaque) callconv(.c) Gboolean,
    /// `webkit_web_view_can_go_forward`, resolved from its library.
    webkit_web_view_can_go_forward: *const fn (*anyopaque) callconv(.c) Gboolean,
    /// `webkit_web_view_get_uri`, resolved from its library.
    webkit_web_view_get_uri: *const fn (*anyopaque) callconv(.c) ?[*:0]const u8,
    /// `webkit_web_view_get_title`, resolved from its library.
    webkit_web_view_get_title: *const fn (*anyopaque) callconv(.c) ?[*:0]const u8,
    /// `webkit_web_view_get_back_forward_list`, resolved from its library.
    webkit_web_view_get_back_forward_list: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    /// `webkit_javascript_result_get_js_value`, resolved from its library.
    webkit_javascript_result_get_js_value: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    // JavaScriptCore.
    /// `jsc_value_is_string`, resolved from its library.
    jsc_value_is_string: *const fn (*anyopaque) callconv(.c) Gboolean,
    /// `jsc_value_to_string`, resolved from its library.
    jsc_value_to_string: *const fn (*anyopaque) callconv(.c) ?[*:0]u8,
    // Xlib, on GDK's display connection.
    /// `XReparentWindow`, resolved from its library.
    XReparentWindow: *const fn (*anyopaque, c_ulong, c_ulong, c_int, c_int) callconv(.c) c_int,
    /// `XSetInputFocus`, resolved from its library.
    XSetInputFocus: *const fn (*anyopaque, c_ulong, c_int, c_ulong) callconv(.c) c_int,
    /// `XGetInputFocus`, resolved from its library.
    XGetInputFocus: *const fn (*anyopaque, *c_ulong, *c_int) callconv(.c) c_int,
};

/// Where GTK stands in this process.
const GtkStatus = enum {
    const Self = @This();

    /// Not tried yet.
    untried,
    /// Running: `api` is filled.
    running,
    /// Tried and failed; never tried again.
    failed,
};

/// GTK in this process: whether it started, and the entry points once it did.
pub const Gtk = struct {
    const Self = @This();

    /// `GTK_WINDOW_POPUP`: a window the window manager never sees.
    pub const window_popup: c_int = 1;
    /// `GDK_BUTTON_PRESS`.
    pub const event_button_press: c_int = 4;
    /// `GDK_KEY_PRESS`.
    pub const event_key_press: c_int = 8;
    /// `GDK_FOCUS_CHANGE`.
    pub const event_focus_change: c_int = 12;
    /// `GDK_SHIFT_MASK`.
    pub const shift_mask: c_uint = 1 << 0;
    /// `GDK_CONTROL_MASK`.
    pub const control_mask: c_uint = 1 << 2;
    /// `GDK_MOD1_MASK` (Alt).
    pub const alt_mask: c_uint = 1 << 3;
    /// `GDK_SUPER_MASK`.
    pub const super_mask: c_uint = 1 << 26;
    /// `GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK`.
    pub const key_masks: c_int = (1 << 10) | (1 << 11);
    /// `G_SIGNAL_MATCH_DATA`, for `g_signal_handlers_disconnect_matched`.
    pub const signal_match_data: c_int = 1 << 4;
    /// Xlib's `RevertToParent`.
    pub const revert_to_parent: c_int = 2;
    /// `GDK_KEY_Return`.
    pub const key_return: c_uint = 0xff0d;
    /// `GDK_KEY_Escape`.
    pub const key_escape: c_uint = 0xff1b;
    /// `GDK_KEY_Tab`.
    pub const key_tab: c_uint = 0xff09;
    /// `GDK_KEY_BackSpace`.
    pub const key_backspace: c_uint = 0xff08;
    /// `GDK_KEY_Delete`.
    pub const key_delete: c_uint = 0xffff;
    /// `GDK_KEY_Left`.
    pub const key_left: c_uint = 0xff51;
    /// `GDK_KEY_Up`.
    pub const key_up: c_uint = 0xff52;
    /// `GDK_KEY_Right`.
    pub const key_right: c_uint = 0xff53;
    /// `GDK_KEY_Down`.
    pub const key_down: c_uint = 0xff54;

    /// Each library, the soname it is opened by.
    const libraries = [_][:0]const u8{
        "libglib-2.0.so.0",
        "libgobject-2.0.so.0",
        "libgdk-3.so.0",
        "libgtk-3.so.0",
        "libwebkit2gtk-4.1.so.0",
        "libjavascriptcoregtk-4.1.so.0",
        "libX11.so.6",
    };

    /// Where GTK stands.
    var status: GtkStatus = .untried;

    /// The entry points, once running.
    var api: GtkApi = undefined;

    /// GDK's Xlib display, once running.
    var x_display: ?*anyopaque = null;

    /// Starts GTK on first call (on the UI thread, with SDL's video up): loads
    /// the libraries, pins GDK to X11 and initializes GTK. Later calls report
    /// how that went.
    ///
    /// - Returns: the entry points, or null when SDL is not on X11, a library
    ///   or entry point is missing, or GTK would not start.
    pub fn start() ?*const GtkApi {
        switch (status) {
            .running => return &api,
            .failed => return null,
            .untried => {},
        }
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        status = .failed;
        const driver = sdl_c.SDL_GetCurrentVideoDriver() orelse return null;
        if (!std.mem.eql(u8, std.mem.span(driver), "x11")) {
            log.warn("web views need SDL on X11 (run with SDL_VIDEO_DRIVER=x11); this window is on {s}", .{driver});
            return null;
        }
        // WebKit's DMA-BUF renderer allocates GBM buffers on the DRM device,
        // which the NVIDIA driver (and a session without DRM access) refuses
        // ("DRM_IOCTL_MODE_CREATE_DUMB failed"), leaving every page blank. Its
        // shared-memory path draws everywhere. Set before the first web
        // process starts; a value the user set wins.
        _ = sdl_c.SDL_setenv_unsafe("WEBKIT_DISABLE_DMABUF_RENDERER", "1", 0);
        if (!mod.DynamicApi.load(GtkApi, &api, &libraries, Self.libraryOf, "web views")) return null;
        api.gdk_set_allowed_backends("x11");
        if (api.gtk_init_check(null, null) == 0) {
            log.warn("GTK would not start: web views are unavailable", .{});
            return null;
        }
        const default_display = api.gdk_display_get_default() orelse return null;
        x_display = api.gdk_x11_display_get_xdisplay(default_display) orelse return null;
        status = .running;
        log.debug("GTK running on X11 display {*}", .{x_display});
        return &api;
    }

    /// The entry points, when GTK is running; never starts it.
    ///
    /// - Returns: the entry points, or null.
    pub fn running() ?*const GtkApi {
        return if (status == .running) &api else null;
    }

    /// GDK's Xlib display, when GTK is running.
    ///
    /// - Returns: the `Display *`, or null.
    pub fn display() ?*anyopaque {
        return if (status == .running) x_display else null;
    }

    /// Flushes GDK's requests to the X server.
    pub fn flush() void {
        if (status != .running) return;
        if (api.gdk_display_get_default()) |default| api.gdk_display_flush(default);
    }

    /// Starts catching X errors instead of letting GDK abort on them: a focus
    /// or reparent request races the window manager (a window iconified
    /// between frames is not viewable), and losing that race is harmless.
    /// Pair each call with `untrapErrors`.
    pub fn trapErrors() void {
        if (status != .running) return;
        if (api.gdk_display_get_default()) |default| api.gdk_x11_display_error_trap_push(default);
    }

    /// Stops catching X errors, dropping any caught since `trapErrors`.
    pub fn untrapErrors() void {
        if (status != .running) return;
        if (api.gdk_display_get_default()) |default| api.gdk_x11_display_error_trap_pop_ignored(default);
    }

    /// Which of `libraries` defines a `GtkApi` field, by its prefix.
    ///
    /// - `name`: the field's name.
    /// - Returns: the index into `libraries`.
    fn libraryOf(comptime name: []const u8) usize {
        @setEvalBranchQuota(10_000);
        if (std.mem.startsWith(u8, name, "g_signal") or std.mem.startsWith(u8, name, "g_object")) return 1;
        if (std.mem.startsWith(u8, name, "g_")) return 0;
        if (std.mem.startsWith(u8, name, "gdk_")) return 2;
        if (std.mem.startsWith(u8, name, "gtk_")) return 3;
        if (std.mem.startsWith(u8, name, "webkit_")) return 4;
        if (std.mem.startsWith(u8, name, "jsc_")) return 5;
        if (std.mem.startsWith(u8, name, "X")) return 6;
        @compileError("no library for " ++ name);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "every GTK entry point names its library" {
    inline for (@typeInfo(GtkApi).@"struct".field_names) |name| {
        _ = comptime Gtk.libraryOf(name);
    }
    try std.testing.expectEqual(@as(usize, 1), comptime Gtk.libraryOf("g_object_unref"));
    try std.testing.expectEqual(@as(usize, 0), comptime Gtk.libraryOf("g_free"));
    try std.testing.expectEqual(@as(usize, 6), comptime Gtk.libraryOf("XSetInputFocus"));
}

test "GLib's poll record has the layout of poll's" {
    if (comptime mod.os_tag != .linux) return error.SkipZigTest;
    try std.testing.expectEqual(@sizeOf(std.c.pollfd), @sizeOf(GpollFd));
    try std.testing.expectEqual(@offsetOf(std.c.pollfd, "revents"), @offsetOf(GpollFd, "revents"));
}

test "GDK's event records keep the C layout" {
    // 64-bit: type (4), padding, window (8), send_event (1), padding, time (4), state, keyval.
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(GdkEventKey, "window"));
    try std.testing.expectEqual(@as(usize, 20), @offsetOf(GdkEventKey, "time"));
    try std.testing.expectEqual(@as(usize, 28), @offsetOf(GdkEventKey, "keyval"));
    try std.testing.expectEqual(@as(usize, 18), @offsetOf(GdkEventFocus, "in"));
}
