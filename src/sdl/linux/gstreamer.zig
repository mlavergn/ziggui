//! GStreamer, its app sink and the few GLib and GObject calls the Linux video
//! player makes, all resolved at run time (as `Gtk` resolves GTK), so a ziggui
//! app links none of them and runs where they are missing: only a `Player`
//! then fails. GStreamer starts on first need (`start`).

const std = @import("std");
const log = std.log.scoped(.ziggui_gstreamer);
const mod = @import("module.zig");

/// GStreamer's `GstMiniObject`, the head of every message, sample and buffer.
pub const GstMiniObject = extern struct {
    const Self = @This();

    /// Its `GType`.
    type: usize,
    /// Its reference count.
    refcount: c_int,
    /// Its lock state.
    lockstate: c_int,
    /// Its flags.
    flags: c_uint,
    /// Its copy function.
    copy: ?*const anyopaque,
    /// Its dispose function.
    dispose: ?*const anyopaque,
    /// Its free function.
    free: ?*const anyopaque,
    /// Private.
    priv_uint: c_uint,
    /// Private.
    priv_pointer: ?*anyopaque,
};

/// GStreamer's `GstMessage`, as far as the player reads it.
pub const GstMessage = extern struct {
    const Self = @This();

    /// The mini-object head.
    mini_object: GstMiniObject,
    /// The `GstMessageType` (one bit).
    type: c_uint,
    /// When it was posted.
    timestamp: u64,
    /// The object that posted it.
    src: ?*anyopaque,
    /// Its sequence number.
    seqnum: u32,
};

/// GStreamer's `GstMapInfo`: a mapped buffer's bytes.
pub const GstMapInfo = extern struct {
    const Self = @This();

    /// The memory mapped.
    memory: ?*anyopaque = null,
    /// The `GstMapFlags` it was mapped with.
    flags: c_uint = 0,
    /// The bytes.
    data: ?[*]const u8 = null,
    /// How many bytes are valid.
    size: usize = 0,
    /// How many bytes the memory holds.
    maxsize: usize = 0,
    /// The mapper's own.
    user_data: [4]?*anyopaque = @splat(null),
    /// Reserved.
    reserved: [4]?*anyopaque = @splat(null),
};

/// GStreamer's `GstAppSinkCallbacks`, with room to spare: the app sink copies
/// as many bytes as its own version's struct holds.
pub const GstAppSinkCallbacks = extern struct {
    const Self = @This();

    /// End of stream.
    eos: ?*const fn (*anyopaque, ?*anyopaque) callconv(.c) void = null,
    /// A preroll sample (the first frame, paused) is ready.
    new_preroll: ?*const fn (*anyopaque, ?*anyopaque) callconv(.c) c_int = null,
    /// A sample is ready.
    new_sample: ?*const fn (*anyopaque, ?*anyopaque) callconv(.c) c_int = null,
    /// The rest, zeroed: later versions' callbacks and padding.
    rest: [12]?*const anyopaque = @splat(null),
};

/// GLib's `GList`: a doubly linked list node (the device monitor's devices).
pub const GList = extern struct {
    const Self = @This();

    /// The node's item.
    data: ?*anyopaque,
    /// The next node, or null at the end.
    next: ?*GList,
    /// The previous node, or null at the start.
    prev: ?*GList,
};

/// The entry points resolved, by library. Each field mirrors the C function
/// of its name, so they keep its spelling.
pub const GstreamerApi = struct {
    const Self = @This();

    /// `g_free`, resolved from its library.
    g_free: *const fn (?*anyopaque) callconv(.c) void,
    /// `g_error_free`, resolved from its library.
    g_error_free: *const fn (*mod.Gerror) callconv(.c) void,
    /// `g_object_set`, resolved from its library.
    g_object_set: *const fn (*anyopaque, [*:0]const u8, ...) callconv(.c) void,
    /// `g_object_get`, resolved from its library.
    g_object_get: *const fn (*anyopaque, [*:0]const u8, ...) callconv(.c) void,
    /// `g_list_free`, resolved from its library.
    g_list_free: *const fn (?*GList) callconv(.c) void,
    /// `g_signal_emit_by_name`, resolved from its library.
    g_signal_emit_by_name: *const fn (*anyopaque, [*:0]const u8, ...) callconv(.c) void,
    /// `gst_version_string`, resolved from its library.
    gst_version_string: *const fn () callconv(.c) ?[*:0]u8,
    /// `gst_init_check`, resolved from its library.
    gst_init_check: *const fn (?*c_int, ?*anyopaque, ?*?*mod.Gerror) callconv(.c) mod.Gboolean,
    /// `gst_element_factory_make`, resolved from its library.
    gst_element_factory_make: *const fn ([*:0]const u8, ?[*:0]const u8) callconv(.c) ?*anyopaque,
    /// `gst_object_ref_sink`, resolved from its library.
    gst_object_ref_sink: *const fn (*anyopaque) callconv(.c) *anyopaque,
    /// `gst_object_unref`, resolved from its library.
    gst_object_unref: *const fn (*anyopaque) callconv(.c) void,
    /// `gst_mini_object_unref`, resolved from its library.
    gst_mini_object_unref: *const fn (*anyopaque) callconv(.c) void,
    /// `gst_element_set_state`, resolved from its library.
    gst_element_set_state: *const fn (*anyopaque, c_int) callconv(.c) c_int,
    /// `gst_element_query_position`, resolved from its library.
    gst_element_query_position: *const fn (*anyopaque, c_int, *i64) callconv(.c) mod.Gboolean,
    /// `gst_element_query_duration`, resolved from its library.
    gst_element_query_duration: *const fn (*anyopaque, c_int, *i64) callconv(.c) mod.Gboolean,
    /// `gst_element_seek`, resolved from its library.
    gst_element_seek: *const fn (*anyopaque, f64, c_int, c_int, c_int, i64, c_int, i64) callconv(.c) mod.Gboolean,
    /// `gst_element_get_bus`, resolved from its library.
    gst_element_get_bus: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    /// `gst_bus_pop`, resolved from its library.
    gst_bus_pop: *const fn (*anyopaque) callconv(.c) ?*GstMessage,
    /// `gst_message_parse_error`, resolved from its library.
    gst_message_parse_error: *const fn (*GstMessage, ?*?*mod.Gerror, ?*?[*:0]u8) callconv(.c) void,
    /// `gst_message_parse_buffering`, resolved from its library.
    gst_message_parse_buffering: *const fn (*GstMessage, *c_int) callconv(.c) void,
    /// `gst_message_parse_state_changed`, resolved from its library.
    gst_message_parse_state_changed: *const fn (*GstMessage, ?*c_int, ?*c_int, ?*c_int) callconv(.c) void,
    /// `gst_message_get_seqnum`, resolved from its library.
    gst_message_get_seqnum: *const fn (*GstMessage) callconv(.c) u32,
    /// `gst_message_new_eos`, resolved from its library.
    gst_message_new_eos: *const fn (?*anyopaque) callconv(.c) ?*GstMessage,
    /// `gst_caps_from_string`, resolved from its library.
    gst_caps_from_string: *const fn ([*:0]const u8) callconv(.c) ?*anyopaque,
    /// `gst_caps_get_structure`, resolved from its library.
    gst_caps_get_structure: *const fn (*anyopaque, c_uint) callconv(.c) ?*anyopaque,
    /// `gst_structure_get_int`, resolved from its library.
    gst_structure_get_int: *const fn (*anyopaque, [*:0]const u8, *c_int) callconv(.c) mod.Gboolean,
    /// `gst_structure_get_string`, resolved from its library.
    gst_structure_get_string: *const fn (*anyopaque, [*:0]const u8) callconv(.c) ?[*:0]const u8,
    /// `gst_structure_get_boolean`, resolved from its library.
    gst_structure_get_boolean: *const fn (*anyopaque, [*:0]const u8, *mod.Gboolean) callconv(.c) mod.Gboolean,
    /// `gst_structure_free`, resolved from its library.
    gst_structure_free: *const fn (*anyopaque) callconv(.c) void,
    /// `gst_device_monitor_new`, resolved from its library.
    gst_device_monitor_new: *const fn () callconv(.c) ?*anyopaque,
    /// `gst_device_monitor_add_filter`, resolved from its library.
    gst_device_monitor_add_filter: *const fn (*anyopaque, ?[*:0]const u8, ?*anyopaque) callconv(.c) c_uint,
    /// `gst_device_monitor_start`, resolved from its library.
    gst_device_monitor_start: *const fn (*anyopaque) callconv(.c) mod.Gboolean,
    /// `gst_device_monitor_stop`, resolved from its library.
    gst_device_monitor_stop: *const fn (*anyopaque) callconv(.c) void,
    /// `gst_device_monitor_get_devices`, resolved from its library.
    gst_device_monitor_get_devices: *const fn (*anyopaque) callconv(.c) ?*GList,
    /// `gst_device_get_display_name`, resolved from its library.
    gst_device_get_display_name: *const fn (*anyopaque) callconv(.c) ?[*:0]u8,
    /// `gst_device_get_properties`, resolved from its library.
    gst_device_get_properties: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    /// `gst_device_create_element`, resolved from its library.
    gst_device_create_element: *const fn (*anyopaque, ?[*:0]const u8) callconv(.c) ?*anyopaque,
    /// `gst_sample_get_buffer`, resolved from its library.
    gst_sample_get_buffer: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    /// `gst_sample_get_caps`, resolved from its library.
    gst_sample_get_caps: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
    /// `gst_buffer_map`, resolved from its library.
    gst_buffer_map: *const fn (*anyopaque, *GstMapInfo, c_uint) callconv(.c) mod.Gboolean,
    /// `gst_buffer_unmap`, resolved from its library.
    gst_buffer_unmap: *const fn (*anyopaque, *GstMapInfo) callconv(.c) void,
    /// `gst_buffer_new_allocate`, resolved from its library.
    gst_buffer_new_allocate: *const fn (?*anyopaque, usize, ?*anyopaque) callconv(.c) ?*anyopaque,
    /// `gst_tag_list_get_string`, resolved from its library.
    gst_tag_list_get_string: *const fn (*anyopaque, [*:0]const u8, *?[*:0]u8) callconv(.c) mod.Gboolean,
    /// `gst_uri_is_valid`, resolved from its library.
    gst_uri_is_valid: *const fn ([*:0]const u8) callconv(.c) mod.Gboolean,
    /// `gst_filename_to_uri`, resolved from its library.
    gst_filename_to_uri: *const fn ([*:0]const u8, ?*?*mod.Gerror) callconv(.c) ?[*:0]u8,
    /// `gst_is_missing_plugin_message`, resolved from its library.
    gst_is_missing_plugin_message: *const fn (*GstMessage) callconv(.c) mod.Gboolean,
    /// `gst_missing_plugin_message_get_description`, resolved from its library.
    gst_missing_plugin_message_get_description: *const fn (*GstMessage) callconv(.c) ?[*:0]u8,
    /// `gst_app_sink_try_pull_sample`, resolved from its library.
    gst_app_sink_try_pull_sample: *const fn (*anyopaque, u64) callconv(.c) ?*anyopaque,
    /// `gst_app_sink_try_pull_preroll`, resolved from its library.
    gst_app_sink_try_pull_preroll: *const fn (*anyopaque, u64) callconv(.c) ?*anyopaque,
    /// `gst_app_sink_set_callbacks`, resolved from its library.
    gst_app_sink_set_callbacks: *const fn (*anyopaque, *const GstAppSinkCallbacks, ?*anyopaque, ?*const anyopaque) callconv(.c) void,
};

/// Where GStreamer stands in this process.
const GstreamerStatus = enum {
    const Self = @This();

    /// Not tried yet.
    untried,
    /// Running: `api` is filled.
    running,
    /// Tried and failed; never tried again.
    failed,
};

/// GStreamer in this process: whether it started, and the entry points once
/// it did.
pub const Gstreamer = struct {
    const Self = @This();

    /// `GST_STATE_NULL`.
    pub const state_null: c_int = 1;
    /// `GST_STATE_PAUSED`.
    pub const state_paused: c_int = 3;
    /// `GST_STATE_PLAYING`.
    pub const state_playing: c_int = 4;
    /// `GST_STATE_CHANGE_FAILURE`.
    pub const state_change_failure: c_int = 0;
    /// `GST_STATE_CHANGE_NO_PREROLL`: a live source, which has no frame to
    /// show before it plays.
    pub const state_change_no_preroll: c_int = 3;
    /// `GST_FORMAT_TIME`.
    pub const format_time: c_int = 3;
    /// `GST_SEEK_FLAG_FLUSH`.
    pub const seek_flush: c_int = 1 << 0;
    /// `GST_SEEK_FLAG_ACCURATE`.
    pub const seek_accurate: c_int = 1 << 1;
    /// `GST_SEEK_TYPE_NONE`.
    pub const seek_type_none: c_int = 0;
    /// `GST_SEEK_TYPE_SET`.
    pub const seek_type_set: c_int = 1;
    /// `GST_MAP_READ`.
    pub const map_read: c_uint = 1;
    /// `GST_MESSAGE_EOS`.
    pub const message_eos: c_uint = 1 << 0;
    /// `GST_MESSAGE_ERROR`.
    pub const message_error: c_uint = 1 << 1;
    /// `GST_MESSAGE_BUFFERING`.
    pub const message_buffering: c_uint = 1 << 5;
    /// `GST_MESSAGE_STATE_CHANGED`.
    pub const message_state_changed: c_uint = 1 << 6;
    /// `GST_MESSAGE_ELEMENT`: an element's own message (a missing plug-in).
    pub const message_element: c_uint = 1 << 15;
    /// `GST_MESSAGE_ASYNC_DONE`.
    pub const message_async_done: c_uint = 1 << 21;
    /// playbin's `GST_PLAY_FLAG_TEXT`: subtitles shown.
    pub const play_flag_text: c_int = 1 << 2;
    /// Nanoseconds in a second, GStreamer's time unit.
    pub const nanoseconds_per_second: f64 = 1e9;

    /// Each library, the soname it is opened by.
    const libraries = [_][:0]const u8{
        "libglib-2.0.so.0",
        "libgobject-2.0.so.0",
        "libgstreamer-1.0.so.0",
        "libgstapp-1.0.so.0",
        "libgstpbutils-1.0.so.0",
    };

    /// Where GStreamer stands.
    var status: GstreamerStatus = .untried;

    /// The entry points, once running.
    var api: GstreamerApi = undefined;

    /// Starts GStreamer on first call: loads the libraries and initializes it.
    /// Later calls report how that went.
    ///
    /// - Returns: the entry points, or null when a library or entry point is
    ///   missing, or GStreamer would not start.
    pub fn start() ?*const GstreamerApi {
        switch (status) {
            .running => return &api,
            .failed => return null,
            .untried => {},
        }
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        status = .failed;
        if (!mod.DynamicApi.load(GstreamerApi, &api, &libraries, Self.libraryOf, "video")) return null;
        var failure: ?*mod.Gerror = null;
        if (api.gst_init_check(null, null, &failure) == 0) {
            log.warn("GStreamer would not start: {s}", .{if (failure) |reported| std.mem.span(reported.message orelse "") else ""});
            if (failure) |reported| api.g_error_free(reported);
            return null;
        }
        status = .running;
        return &api;
    }

    /// The entry points, when GStreamer is running; never starts it.
    ///
    /// - Returns: the entry points, or null.
    pub fn running() ?*const GstreamerApi {
        return if (status == .running) &api else null;
    }

    /// Which of `libraries` defines a `GstreamerApi` field, by its prefix.
    ///
    /// - `name`: the field's name.
    /// - Returns: the index into `libraries`.
    fn libraryOf(comptime name: []const u8) usize {
        @setEvalBranchQuota(10_000);
        if (std.mem.startsWith(u8, name, "g_object") or std.mem.startsWith(u8, name, "g_signal")) return 1;
        if (std.mem.startsWith(u8, name, "g_")) return 0;
        if (std.mem.startsWith(u8, name, "gst_app_")) return 3;
        if (std.mem.startsWith(u8, name, "gst_is_missing_plugin") or std.mem.startsWith(u8, name, "gst_missing_plugin")) return 4;
        if (std.mem.startsWith(u8, name, "gst_")) return 2;
        @compileError("no library for " ++ name);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "every GStreamer entry point names its library" {
    inline for (@typeInfo(GstreamerApi).@"struct".field_names) |name| {
        _ = comptime Gstreamer.libraryOf(name);
    }
    try std.testing.expectEqual(@as(usize, 3), comptime Gstreamer.libraryOf("gst_app_sink_try_pull_sample"));
    try std.testing.expectEqual(@as(usize, 2), comptime Gstreamer.libraryOf("gst_bus_pop"));
}

test "GStreamer's records keep the C layout" {
    // 64-bit: the mini-object head is 64 bytes, a message's type follows it.
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(GstMiniObject));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(GstMessage, "type"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(GstMapInfo, "data"));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(GstMapInfo));
    // Where GStreamer is installed, a real message and buffer agree.
    if (comptime mod.os_tag != .linux) return;
    const api = Gstreamer.start() orelse return;
    const message = api.gst_message_new_eos(null) orelse return error.NoMessage;
    defer api.gst_mini_object_unref(message);
    try std.testing.expectEqual(Gstreamer.message_eos, message.type);
    try std.testing.expectEqual(api.gst_message_get_seqnum(message), message.seqnum);
    const buffer = api.gst_buffer_new_allocate(null, 16, null) orelse return error.NoBuffer;
    defer api.gst_mini_object_unref(buffer);
    var map: GstMapInfo = .{};
    try std.testing.expect(api.gst_buffer_map(buffer, &map, Gstreamer.map_read) != 0);
    defer api.gst_buffer_unmap(buffer, &map);
    try std.testing.expectEqual(@as(usize, 16), map.size);
}
