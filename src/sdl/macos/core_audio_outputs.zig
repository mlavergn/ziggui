//! The macOS `AudioOutputBackend`: Core Audio's devices that have output
//! streams, each known by its UID (`kAudioDevicePropertyDeviceUID`, the same
//! across launches and replugs), which `AvFoundationPlayer` hands to
//! `AVPlayer.audioOutputDeviceUniqueID` to route one player's sound without
//! touching the system default. Core Audio's strings are `CFString`s, which
//! are `NSString`s, so `ObjectiveC.utf8` and `release` read and free them.
//! macOS only: other targets reach it only behind `os_tag == .macos`.

const std = @import("std");
const log = std.log.scoped(.ziggui_core_audio_outputs);
const mod = @import("module.zig");
const views = @import("views");

/// Core Audio's `AudioObjectPropertyAddress`: which property of an object.
const AudioObjectPropertyAddress = extern struct {
    const Self = @This();

    /// `mSelector`: the property.
    mSelector: u32,
    /// `mScope`: global, input or output.
    mScope: u32,
    /// `mElement`: the element; 0, the main one.
    mElement: u32 = 0,
};

/// The output device an `OutputDeviceWalk` is on, its strings borrowed until
/// the walk moves on.
const OutputDevice = struct {
    const Self = @This();

    /// The device.
    device: u32,
    /// Its UID (`AudioOutput.id`).
    id: []const u8,
    /// Its name, or its UID when it has none.
    name: []const u8,
};

/// The devices with output streams, in Core Audio's order, each with its
/// UID and name: what `hasOutput` and `list` both walk. Run it inside an
/// autorelease pool, since the strings are read through `UTF8String`.
const OutputDeviceWalk = struct {
    const Self = @This();

    /// The system's devices, inputs and outputs alike.
    buffer: [CoreAudioOutputs.max_devices]u32 = undefined,
    /// How many of `buffer` are devices.
    count: usize = 0,
    /// The next to visit.
    index: usize = 0,
    /// The UID of the device the walk is on, owned.
    uid: mod.Id = null,
    /// Its name, owned.
    name: mod.Id = null,

    /// Lists the system's devices now.
    ///
    /// - Returns: the walk, before its first output.
    fn init() Self {
        var self = Self{};
        self.count = CoreAudioOutputs.devices(&self.buffer).len;
        return self;
    }

    /// Releases the strings of the device the walk is on.
    ///
    /// - `self`: the walk.
    fn deinit(self: *Self) void {
        self.releaseCurrent();
    }

    /// Moves to the next device that can play sound and has a UID.
    ///
    /// - `self`: the walk.
    /// - Returns: the device, its strings borrowed until the next call;
    ///   null after the last.
    fn next(self: *Self) ?OutputDevice {
        while (self.index < self.count) {
            self.releaseCurrent();
            const device = self.buffer[self.index];
            self.index += 1;
            if (!CoreAudioOutputs.hasOutputStreams(device)) continue;
            self.uid = CoreAudioOutputs.stringProperty(device, CoreAudioOutputs.uid_property) orelse continue;
            const id = mod.ObjectiveC.utf8(self.uid);
            if (id.len == 0) continue;
            self.name = CoreAudioOutputs.stringProperty(device, CoreAudioOutputs.name_property);
            const shown = mod.ObjectiveC.utf8(self.name);
            return .{ .device = device, .id = id, .name = if (shown.len > 0) shown else id };
        }
        self.releaseCurrent();
        return null;
    }

    /// Releases the current device's strings.
    ///
    /// - `self`: the walk.
    fn releaseCurrent(self: *Self) void {
        mod.ObjectiveC.release(self.uid);
        mod.ObjectiveC.release(self.name);
        self.uid = null;
        self.name = null;
    }
};

/// The output devices Core Audio sees.
pub const CoreAudioOutputs = struct {
    const Self = @This();

    /// The backend `AudioOutputs` lists with.
    pub const backend: views.AudioOutputBackend = .{ .list = Self.list };

    /// The most devices read; a Mac has a handful.
    const max_devices = 128;

    /// `kAudioObjectSystemObject`: the object the devices hang from.
    const system_object: u32 = 1;
    /// `kAudioHardwarePropertyDevices`.
    const devices_property = Self.code("dev#");
    /// `kAudioHardwarePropertyDefaultOutputDevice`.
    const default_output_property = Self.code("dOut");
    /// `kAudioDevicePropertyStreams`.
    const streams_property = Self.code("stm#");
    /// `kAudioObjectPropertyName`.
    const name_property = Self.code("lnam");
    /// `kAudioDevicePropertyDeviceUID`.
    const uid_property = Self.code("uid ");
    /// `kAudioObjectPropertyScopeGlobal`.
    const global_scope = Self.code("glob");
    /// `kAudioObjectPropertyScopeOutput`.
    const output_scope = Self.code("outp");

    extern fn AudioObjectGetPropertyDataSize(object: u32, address: *const AudioObjectPropertyAddress, qualifier_size: u32, qualifier: ?*const anyopaque, size: *u32) i32;
    extern fn AudioObjectGetPropertyData(object: u32, address: *const AudioObjectPropertyAddress, qualifier_size: u32, qualifier: ?*const anyopaque, size: *u32, data: *anyopaque) i32;

    /// Whether a device with output streams has the UID `id` now.
    ///
    /// - `id`: the output's `AudioOutput.id`.
    /// - Returns: true when one does.
    pub fn hasOutput(id: []const u8) bool {
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        var walk = OutputDeviceWalk.init();
        defer walk.deinit();
        while (walk.next()) |output| {
            if (std.mem.eql(u8, output.id, id)) return true;
        }
        return false;
    }

    /// Lists the devices that can play sound now, the default marked.
    ///
    /// - `allocator`: owns the list and its strings; on failure nothing is
    ///   left allocated.
    /// - Returns: the outputs; propagates allocation failure.
    fn list(allocator: std.mem.Allocator) std.mem.Allocator.Error![]views.AudioOutput {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const default_output = Self.defaultOutput();
        var collector = views.AudioOutputCollector.init(allocator);
        defer collector.deinit();
        var walk = OutputDeviceWalk.init();
        defer walk.deinit();
        while (walk.next()) |output| try collector.add(output.id, output.name, output.device == default_output);
        return collector.finish();
    }

    /// The system's audio devices, inputs and outputs alike.
    ///
    /// - `buffer`: where their ids go.
    /// - Returns: the ids, in `buffer`; none when Core Audio would not say.
    fn devices(buffer: *[max_devices]u32) []const u32 {
        const address: AudioObjectPropertyAddress = .{ .mSelector = devices_property, .mScope = global_scope };
        var size: u32 = @sizeOf(@TypeOf(buffer.*));
        if (AudioObjectGetPropertyData(system_object, &address, 0, null, &size, buffer) != 0) {
            log.warn("Core Audio listed no devices", .{});
            return &.{};
        }
        return buffer[0 .. size / @sizeOf(u32)];
    }

    /// The system's default output device.
    ///
    /// - Returns: its id, or 0 (no device) when there is none.
    fn defaultOutput() u32 {
        const address: AudioObjectPropertyAddress = .{ .mSelector = default_output_property, .mScope = global_scope };
        var device: u32 = 0;
        var size: u32 = @sizeOf(u32);
        if (AudioObjectGetPropertyData(system_object, &address, 0, null, &size, &device) != 0) return 0;
        return device;
    }

    /// Whether a device has output streams: it can play sound.
    ///
    /// - `device`: the device.
    /// - Returns: true for an output device.
    fn hasOutputStreams(device: u32) bool {
        const address: AudioObjectPropertyAddress = .{ .mSelector = streams_property, .mScope = output_scope };
        var size: u32 = 0;
        return AudioObjectGetPropertyDataSize(device, &address, 0, null, &size) == 0 and size > 0;
    }

    /// A device's string property (its name or UID).
    ///
    /// - `device`: the device.
    /// - `property`: the property's selector.
    /// - Returns: the `CFString`, owned (`ObjectiveC.release`), or null when
    ///   the device has none.
    fn stringProperty(device: u32, property: u32) mod.Id {
        const address: AudioObjectPropertyAddress = .{ .mSelector = property, .mScope = global_scope };
        var value: mod.Id = null;
        var size: u32 = @sizeOf(mod.Id);
        if (AudioObjectGetPropertyData(device, &address, 0, null, &size, @ptrCast(&value)) != 0) return null;
        return value;
    }

    /// A Core Audio four-character code, as its headers spell it (`'dev#'`).
    ///
    /// - `text`: the four characters.
    /// - Returns: the code.
    fn code(comptime text: *const [4]u8) u32 {
        return std.mem.readInt(u32, text, .big);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// Lists the outputs with a general-purpose allocator and frees them, for the
/// allocation-failure test.
const ListProbe = struct {
    const Self = @This();

    /// Lists the outputs, then frees them.
    ///
    /// - `allocator`: the allocator the list is made with.
    /// - Returns: nothing; propagates allocation failure.
    fn listAndFree(allocator: std.mem.Allocator) std.mem.Allocator.Error!void {
        views.AudioOutputs.free(allocator, try CoreAudioOutputs.list(allocator));
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "the macOS audio outputs list each device once, each one found by its id" {
    // The devices are whatever this Mac has (none on a headless runner), so
    // only their shape is checked.
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    try std.testing.expectEqual(@as(u32, 0x64657623), CoreAudioOutputs.devices_property);
    const outputs = try CoreAudioOutputs.list(std.testing.allocator);
    defer views.AudioOutputs.free(std.testing.allocator, outputs);
    var defaults: usize = 0;
    for (outputs, 0..) |output, index| {
        try std.testing.expect(output.id.len > 0 and output.name.len > 0);
        try std.testing.expectEqual(@as(?usize, index), views.AudioOutputs.indexOf(outputs, output.id));
        try std.testing.expect(CoreAudioOutputs.hasOutput(output.id));
        if (output.is_default) defaults += 1;
    }
    try std.testing.expect(defaults <= 1);
    try std.testing.expect(!CoreAudioOutputs.hasOutput("no such output"));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, ListProbe.listAndFree, .{});
}
