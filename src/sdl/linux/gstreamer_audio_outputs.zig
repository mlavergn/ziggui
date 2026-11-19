//! The Linux `AudioOutputBackend`: GStreamer's device monitor, asked for the
//! audio sinks its providers see (PipeWire's, PulseAudio's, ALSA's; a
//! provider that another stands in for is hidden by GStreamer itself), and the
//! sink element of one of them, which `GstreamerPlayer` hands its `playbin`
//! to route one player's sound there without touching the system default.
//! GStreamer starts on first need, as for a player; where it cannot, there
//! are no outputs. Linux only: other targets reach it only behind
//! `os_tag == .linux`.

const std = @import("std");
const log = std.log.scoped(.ziggui_gstreamer_audio_outputs);
const mod = @import("module.zig");
const views = @import("views");

/// What one monitored device says about itself, held while it is read.
const DeviceText = struct {
    const Self = @This();

    /// The device's display name, owned (`g_free`), or null when it has none.
    name: ?[*:0]u8,
    /// Its properties, owned (`gst_structure_free`), or null when it has none.
    properties: ?*anyopaque,

    /// Reads a device's name and properties.
    ///
    /// - `api`: GStreamer's entry points.
    /// - `device`: the `GstDevice`.
    /// - Returns: what it says.
    fn read(api: *const mod.GstreamerApi, device: *anyopaque) Self {
        const self = Self{ .name = api.gst_device_get_display_name(device), .properties = api.gst_device_get_properties(device) };
        return self;
    }

    /// Frees what was read.
    ///
    /// - `self`: the text.
    /// - `api`: GStreamer's entry points.
    fn deinit(self: *Self, api: *const mod.GstreamerApi) void {
        if (self.name) |owned| api.g_free(owned);
        if (self.properties) |owned| api.gst_structure_free(owned);
    }

    /// PipeWire's `node.name` for the device, stable while it stays plugged in.
    ///
    /// - `self`: the text.
    /// - `api`: GStreamer's entry points.
    /// - Returns: the name, borrowed from the text; null where the provider
    ///   gives none.
    fn nodeName(self: *const Self, api: *const mod.GstreamerApi) ?[]const u8 {
        const properties = self.properties orelse return null;
        const name = api.gst_structure_get_string(properties, "node.name") orelse return null;
        return std.mem.span(name);
    }

    /// The device's display name.
    ///
    /// - `self`: the text.
    /// - Returns: the name, borrowed from the text; null when it has none.
    fn displayName(self: *const Self) ?[]const u8 {
        const name = self.name orelse return null;
        return std.mem.span(name);
    }

    /// Whether the device is the system's default output now, as its
    /// provider says (PulseAudio's and PipeWire's set `is-default`).
    ///
    /// - `self`: the text.
    /// - `api`: GStreamer's entry points.
    /// - Returns: true for the default.
    fn isDefault(self: *const Self, api: *const mod.GstreamerApi) bool {
        const properties = self.properties orelse return false;
        var value: mod.Gboolean = 0;
        return api.gst_structure_get_boolean(properties, "is-default", &value) != 0 and value != 0;
    }
};

/// The device a `DeviceWalk` is on, its strings borrowed until it moves on.
const DeviceEntry = struct {
    const Self = @This();

    /// The `GstDevice`.
    device: *anyopaque,
    /// Its id (`AudioOutput.id`).
    id: []const u8,
    /// Its display name, or its id when it has none.
    name: []const u8,
    /// It is the system's default output now.
    is_default: bool,
};

/// The audio sinks a device monitor sees, walked in its order, each with its
/// id: PipeWire's `node.name` where the provider gives one, else the display
/// name, with " #2", " #3", … after the second and later devices of one name
/// (two of one headset), so identical devices stay apart. The same devices
/// in the same order give the same ids, so `list` and `createSink` agree.
const DeviceWalk = struct {
    const Self = @This();

    /// The device class the monitor is filtered to: sound outputs.
    const device_class = "Audio/Sink";

    /// The most bytes of an id made from a name and its ordinal.
    const id_capacity = 256;

    /// GStreamer's entry points.
    api: *const mod.GstreamerApi,
    /// The device monitor, owned.
    monitor: *anyopaque,
    /// The monitor was started, so it is stopped with the walk.
    started: bool,
    /// The devices it listed, each reference owned.
    devices: ?*mod.GList,
    /// The next node to visit.
    node: ?*mod.GList,
    /// What the device the walk is on says, owned.
    text: ?DeviceText = null,
    /// The id of the device the walk is on, when made from its name and ordinal.
    id_buffer: [id_capacity]u8 = undefined,

    /// Lists the audio sinks the monitor sees now.
    ///
    /// - `api`: GStreamer's entry points.
    /// - Returns: the walk, before its first device; null when GStreamer would
    ///   not make a monitor.
    fn init(api: *const mod.GstreamerApi) ?Self {
        const monitor = api.gst_device_monitor_new() orelse {
            log.warn("GStreamer made no device monitor: no audio outputs", .{});
            return null;
        };
        _ = api.gst_device_monitor_add_filter(monitor, device_class, null);
        // Started, not only probed: PulseAudio's provider marks the default
        // (`is-default`) only once it watches the server. A monitor that will
        // not start still probes.
        const started = api.gst_device_monitor_start(monitor) != 0;
        if (!started) log.debug("the device monitor did not start: probing", .{});
        const devices = api.gst_device_monitor_get_devices(monitor);
        const self = Self{ .api = api, .monitor = monitor, .started = started, .devices = devices, .node = devices };
        return self;
    }

    /// Frees the devices and their list, and stops and frees the monitor.
    ///
    /// - `self`: the walk.
    fn deinit(self: *Self) void {
        if (self.text) |*text| text.deinit(self.api);
        var node = self.devices;
        while (node) |current| : (node = current.next) {
            if (current.data) |device| self.api.gst_object_unref(device);
        }
        self.api.g_list_free(self.devices);
        if (self.started) self.api.gst_device_monitor_stop(self.monitor);
        self.api.gst_object_unref(self.monitor);
    }

    /// Moves to the next device that has an id.
    ///
    /// - `self`: the walk.
    /// - Returns: the device, its strings borrowed until the next call; null
    ///   after the last.
    fn next(self: *Self) ?DeviceEntry {
        while (self.node) |current| {
            self.node = current.next;
            if (self.text) |*text| text.deinit(self.api);
            self.text = null;
            const device = current.data orelse continue;
            self.text = DeviceText.read(self.api, device);
            const text = &self.text.?;
            const id = self.idOf(current, text) orelse continue;
            return .{ .device = device, .id = id, .name = text.displayName() orelse id, .is_default = text.isDefault(self.api) };
        }
        return null;
    }

    /// The id of the device at `current`: its `node.name`, else its display
    /// name, with its ordinal among the earlier devices of that name.
    ///
    /// - `self`: the walk.
    /// - `current`: the device's node.
    /// - `text`: what the device says.
    /// - Returns: the id, borrowed from `text` or the walk; null with neither name.
    fn idOf(self: *Self, current: *mod.GList, text: *const DeviceText) ?[]const u8 {
        if (text.nodeName(self.api)) |name| return name;
        const name = text.displayName() orelse return null;
        var ordinal: usize = 1;
        var node = self.devices;
        while (node) |earlier| : (node = earlier.next) {
            if (earlier == current) break;
            const device = earlier.data orelse continue;
            var other = DeviceText.read(self.api, device);
            defer other.deinit(self.api);
            if (other.nodeName(self.api) != null) continue;
            const other_name = other.displayName() orelse continue;
            if (std.mem.eql(u8, other_name, name)) ordinal += 1;
        }
        if (ordinal == 1) return name;
        // Room left for " #" and the ordinal's digits.
        const kept = views.DisplayText.fitLength(name, id_capacity - 24);
        return std.mem.print(&self.id_buffer, "{s} #{d}", .{ name[0..kept], ordinal }) catch name;
    }
};

/// The audio outputs GStreamer's device monitor sees.
pub const GstreamerAudioOutputs = struct {
    const Self = @This();

    /// The backend `AudioOutputs` lists with.
    pub const backend: views.AudioOutputBackend = .{ .list = Self.list };

    /// The sink element of the output whose id is `id`, for a `playbin`'s
    /// `audio-sink`.
    ///
    /// - `api`: GStreamer's entry points.
    /// - `id`: the output's `AudioOutput.id`.
    /// - Returns: the element (floating: the `playbin` takes it), or null when
    ///   no device has that id now.
    pub fn createSink(api: *const mod.GstreamerApi, id: []const u8) ?*anyopaque {
        var walk = DeviceWalk.init(api) orelse return null;
        defer walk.deinit();
        while (walk.next()) |entry| {
            if (std.mem.eql(u8, entry.id, id)) return api.gst_device_create_element(entry.device, null);
        }
        return null;
    }

    /// Lists the audio sinks the monitor sees now, each id once.
    ///
    /// - `allocator`: owns the list and its strings; on failure nothing is
    ///   left allocated.
    /// - Returns: the outputs, none where GStreamer cannot start; propagates
    ///   allocation failure.
    fn list(allocator: std.mem.Allocator) std.mem.Allocator.Error![]views.AudioOutput {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const api = mod.Gstreamer.start() orelse return &.{};
        var walk = DeviceWalk.init(api) orelse return &.{};
        defer walk.deinit();
        var collector = views.AudioOutputCollector.init(allocator);
        defer collector.deinit();
        // One device two providers both see shares its `node.name`: the
        // collector keeps it once.
        while (walk.next()) |entry| try collector.add(entry.id, entry.name, entry.is_default);
        return collector.finish();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the Linux audio outputs list each sink once, and make a sink for each" {
    // Only where GStreamer runs (a Linux with it installed: its loader needs
    // `dlopen`, which Windows lacks); the outputs are whatever the machine
    // has, so only their shape is checked.
    if (comptime mod.os_tag != .linux) return error.SkipZigTest;
    const api = mod.Gstreamer.start() orelse return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const outputs = try GstreamerAudioOutputs.list(arena.allocator());
    for (outputs, 0..) |output, index| {
        try std.testing.expect(output.id.len > 0 and output.name.len > 0);
        try std.testing.expectEqual(@as(?usize, index), views.AudioOutputs.indexOf(outputs, output.id));
        const sink = GstreamerAudioOutputs.createSink(api, output.id) orelse return error.TestUnexpectedResult;
        api.gst_object_unref(api.gst_object_ref_sink(sink));
    }
    try std.testing.expect(GstreamerAudioOutputs.createSink(api, "no such output") == null);
}

/// Lists the outputs with a general-purpose allocator and frees them, for the
/// allocation-failure test.
const ListProbe = struct {
    const Self = @This();

    /// Lists the outputs, then frees the list and its strings.
    ///
    /// - `allocator`: the allocator the list is made with.
    /// - Returns: nothing; propagates allocation failure.
    fn listAndFree(allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        views.AudioOutputs.free(allocator, try GstreamerAudioOutputs.list(allocator));
    }
};

test "the Linux audio outputs leave nothing allocated when an allocation fails" {
    if (comptime mod.os_tag != .linux) return error.SkipZigTest;
    _ = mod.Gstreamer.start() orelse return error.SkipZigTest;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, ListProbe.listAndFree, .{});
}
