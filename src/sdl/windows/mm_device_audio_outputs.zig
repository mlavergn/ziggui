//! The Windows `AudioOutputBackend`: the active render endpoints Core Audio's
//! MMDevice API lists (`IMMDeviceEnumerator`), each known by its endpoint id
//! (`IMMDevice::GetId`, the same across launches), which
//! `MediaFoundationPlayer` hands its engine (`IMFMediaEngineAudioEndpointId`)
//! to route one player's sound without touching the system default.
//! Windows only: other targets reach it only behind `os_tag == .windows`.

const std = @import("std");
const log = std.log.scoped(.ziggui_mm_device_audio_outputs);
const mod = @import("module.zig");
const views = @import("views");

/// The identifiers the listing needs.
const Guid = struct {
    const Self = @This();

    /// `CLSID_MMDeviceEnumerator`.
    const device_enumerator = std.os.windows.GUID.parse("{bcde0395-e52f-467c-8e3d-c4579291692e}");
    /// `IID_IMMDeviceEnumerator`.
    const iid_device_enumerator = std.os.windows.GUID.parse("{a95664d2-9614-4f35-a746-de8db63617e6}");
};

/// The vtable slots the listing calls, `IUnknown`'s three counted.
const EndpointSlot = struct {
    const Self = @This();

    /// `IMMDeviceEnumerator::EnumAudioEndpoints(EDataFlow, DWORD, IMMDeviceCollection**)`.
    const enum_audio_endpoints = 3;
    /// `IMMDeviceEnumerator::GetDefaultAudioEndpoint(EDataFlow, ERole, IMMDevice**)`.
    const get_default_audio_endpoint = 4;
    /// `IMMDeviceCollection::GetCount(UINT*)`.
    const get_count = 3;
    /// `IMMDeviceCollection::Item(UINT, IMMDevice**)`.
    const item = 4;
    /// `IMMDevice::OpenPropertyStore(DWORD, IPropertyStore**)`.
    const open_property_store = 4;
    /// `IMMDevice::GetId(LPWSTR*)`.
    const get_id = 5;
    /// `IPropertyStore::GetValue(REFPROPERTYKEY, PROPVARIANT*)`.
    const get_value = 5;
};

/// `PROPERTYKEY`: a property of a property store.
const PROPERTYKEY = extern struct {
    const Self = @This();

    /// `fmtid`: the property set.
    fmtid: std.os.windows.GUID,
    /// `pid`: the property in it.
    pid: u32,
};

/// The endpoint an `EndpointWalk` is on, borrowed until the walk moves on.
const Endpoint = struct {
    const Self = @This();

    /// The `IMMDevice`.
    device: *anyopaque,
    /// Its id (`IMMDevice::GetId`), UTF-16.
    id: [:0]const u16,
};

/// The active render endpoints, walked in the enumerator's order, each with
/// its id: what `hasOutput` and `list` both walk.
const EndpointWalk = struct {
    const Self = @This();

    /// The `IMMDeviceEnumerator`, owned.
    enumerator: *anyopaque,
    /// The `IMMDeviceCollection` of active render endpoints, owned.
    collection: *anyopaque,
    /// How many endpoints it holds.
    count: u32,
    /// The next one to visit.
    index: u32 = 0,
    /// The endpoint the walk is on, owned.
    device: ?*anyopaque = null,
    /// Its id, owned (`Com.freeTask`).
    id: ?[*:0]u16 = null,

    /// Lists the active render endpoints now.
    ///
    /// - Returns: the walk, before its first endpoint; null when COM would
    ///   not list them.
    fn init() ?Self {
        // A thread COM already runs multithreaded on can still list.
        _ = mod.Com.enterApartment();
        const enumerator = mod.Com.create(&Guid.device_enumerator, &Guid.iid_device_enumerator) orelse return null;
        var collection: ?*anyopaque = null;
        const listed = mod.Com.method(*const fn (*anyopaque, u32, u32, *?*anyopaque) callconv(.winapi) mod.HRESULT, enumerator, EndpointSlot.enum_audio_endpoints)(enumerator, MmDeviceAudioOutputs.render, MmDeviceAudioOutputs.state_active, &collection);
        const endpoints = collection orelse {
            log.warn("the audio endpoints could not be listed [0x{x}]", .{@as(u32, @bitCast(listed))});
            mod.Com.release(enumerator);
            return null;
        };
        var count: u32 = 0;
        if (mod.Com.method(*const fn (*anyopaque, *u32) callconv(.winapi) mod.HRESULT, endpoints, EndpointSlot.get_count)(endpoints, &count) < 0) count = 0;
        const self = Self{ .enumerator = enumerator, .collection = endpoints, .count = count };
        return self;
    }

    /// Releases the endpoint the walk is on, the collection and the enumerator.
    ///
    /// - `self`: the walk.
    fn deinit(self: *Self) void {
        self.releaseCurrent();
        mod.Com.release(self.collection);
        mod.Com.release(self.enumerator);
    }

    /// Moves to the next endpoint that has an id.
    ///
    /// - `self`: the walk.
    /// - Returns: the endpoint, the walk's until the next call; null after
    ///   the last.
    fn next(self: *Self) ?Endpoint {
        while (self.index < self.count) {
            self.releaseCurrent();
            const index = self.index;
            self.index += 1;
            var device: ?*anyopaque = null;
            if (mod.Com.method(*const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) mod.HRESULT, self.collection, EndpointSlot.item)(self.collection, index, &device) < 0) continue;
            const found = device orelse continue;
            self.device = found;
            const id = MmDeviceAudioOutputs.endpointId(found) orelse continue;
            self.id = id;
            return .{ .device = found, .id = std.mem.span(id) };
        }
        self.releaseCurrent();
        return null;
    }

    /// Releases the current endpoint and its id.
    ///
    /// - `self`: the walk.
    fn releaseCurrent(self: *Self) void {
        mod.Com.freeTask(self.id);
        mod.Com.release(self.device);
        self.id = null;
        self.device = null;
    }

    /// The id of the endpoint media plays through by default.
    ///
    /// - `self`: the walk.
    /// - Returns: the id, owned (`Com.freeTask`), or null with none.
    fn defaultId(self: *const Self) ?[*:0]u16 {
        var device: ?*anyopaque = null;
        if (mod.Com.method(*const fn (*anyopaque, u32, u32, *?*anyopaque) callconv(.winapi) mod.HRESULT, self.enumerator, EndpointSlot.get_default_audio_endpoint)(self.enumerator, MmDeviceAudioOutputs.render, MmDeviceAudioOutputs.multimedia_role, &device) < 0) return null;
        const found = device orelse return null;
        defer mod.Com.release(found);
        return MmDeviceAudioOutputs.endpointId(found);
    }
};

/// The audio outputs Windows lists.
pub const MmDeviceAudioOutputs = struct {
    const Self = @This();

    /// The backend `AudioOutputs` lists with.
    pub const backend: views.AudioOutputBackend = .{ .list = Self.list };

    /// `eRender`: endpoints that play sound.
    const render: u32 = 0;
    /// `eMultimedia`: the role a media player plays in.
    const multimedia_role: u32 = 1;
    /// `DEVICE_STATE_ACTIVE`: plugged in and enabled.
    const state_active: u32 = 1;
    /// `STGM_READ`.
    const storage_read: u32 = 0;
    /// `PKEY_Device_FriendlyName`: the name Sound settings show.
    const friendly_name: PROPERTYKEY = .{ .fmtid = std.os.windows.GUID.parse("{a45c254e-df1c-4efd-8020-67d146a850e0}"), .pid = 14 };

    /// Whether an active render endpoint has the id `id` now.
    ///
    /// - `id`: the output's `AudioOutput.id`.
    /// - Returns: true when one does.
    pub fn hasOutput(id: []const u8) bool {
        const allocator = std.heap.c_allocator;
        const wanted = mod.Com.wide(allocator, id) catch |err| {
            log.warn("audio output id not converted: {s}", .{@errorName(err)});
            return false;
        };
        defer allocator.free(wanted);
        var walk = EndpointWalk.init() orelse return false;
        defer walk.deinit();
        while (walk.next()) |endpoint| {
            if (std.mem.eql(u16, endpoint.id, wanted)) return true;
        }
        return false;
    }

    /// Lists the endpoints that can play sound now, the default marked.
    ///
    /// - `allocator`: owns the list and its strings; on failure nothing is
    ///   left allocated.
    /// - Returns: the outputs, none where COM will not list them; propagates
    ///   allocation failure.
    fn list(allocator: std.mem.Allocator) std.mem.Allocator.Error![]views.AudioOutput {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        var walk = EndpointWalk.init() orelse return &.{};
        defer walk.deinit();
        const default_id = walk.defaultId();
        defer mod.Com.freeTask(default_id);
        var collector = views.AudioOutputCollector.init(allocator);
        defer collector.deinit();
        while (walk.next()) |endpoint| {
            const id = try mod.Com.narrow(allocator, endpoint.id.ptr);
            defer allocator.free(id);
            if (id.len == 0) continue;
            const name = try Self.friendlyName(allocator, endpoint.device);
            defer allocator.free(name);
            const is_default = if (default_id) |known| std.mem.eql(u16, std.mem.span(known), endpoint.id) else false;
            try collector.add(id, if (name.len > 0) name else id, is_default);
        }
        return collector.finish();
    }

    /// An endpoint's id.
    ///
    /// - `device`: the `IMMDevice`.
    /// - Returns: the id, owned (`Com.freeTask`), or null when it gives none.
    fn endpointId(device: *anyopaque) ?[*:0]u16 {
        var id: ?[*:0]u16 = null;
        if (mod.Com.method(*const fn (*anyopaque, *?[*:0]u16) callconv(.winapi) mod.HRESULT, device, EndpointSlot.get_id)(device, &id) < 0) return null;
        return id;
    }

    /// An endpoint's name as Sound settings show it ("Speakers (Realtek(R) Audio)").
    ///
    /// - `allocator`: owns the name.
    /// - `device`: the `IMMDevice`.
    /// - Returns: the name, empty when it has none; propagates allocation failure.
    fn friendlyName(allocator: std.mem.Allocator, device: *anyopaque) std.mem.Allocator.Error![]u8 {
        var store: ?*anyopaque = null;
        if (mod.Com.method(*const fn (*anyopaque, u32, *?*anyopaque) callconv(.winapi) mod.HRESULT, device, EndpointSlot.open_property_store)(device, storage_read, &store) < 0) return allocator.alloc(u8, 0);
        const properties = store orelse return allocator.alloc(u8, 0);
        defer mod.Com.release(properties);
        var value: mod.PROPVARIANT = .{};
        const result = mod.Com.method(*const fn (*anyopaque, *const PROPERTYKEY, *mod.PROPVARIANT) callconv(.winapi) mod.HRESULT, properties, EndpointSlot.get_value)(properties, &friendly_name, &value);
        defer mod.Com.clearVariant(&value);
        if (result < 0 or value.vt != mod.PROPVARIANT.vt_lpwstr) return allocator.alloc(u8, 0);
        return mod.Com.narrow(allocator, @ptrCast(@alignCast(value.pointer)));
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
        views.AudioOutputs.free(allocator, try MmDeviceAudioOutputs.list(allocator));
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "the Windows audio outputs list each endpoint once, each one found by its id" {
    // The endpoints are whatever this machine has (none on a headless
    // runner), so only their shape is checked.
    if (comptime mod.os_tag != .windows) return error.SkipZigTest;
    const outputs = try MmDeviceAudioOutputs.list(std.testing.allocator);
    defer views.AudioOutputs.free(std.testing.allocator, outputs);
    var defaults: usize = 0;
    for (outputs, 0..) |output, index| {
        try std.testing.expect(output.id.len > 0 and output.name.len > 0);
        try std.testing.expectEqual(@as(?usize, index), views.AudioOutputs.indexOf(outputs, output.id));
        try std.testing.expect(MmDeviceAudioOutputs.hasOutput(output.id));
        if (output.is_default) defaults += 1;
    }
    try std.testing.expect(defaults <= 1);
    try std.testing.expect(!MmDeviceAudioOutputs.hasOutput("no such output"));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, ListProbe.listAndFree, .{});
}
