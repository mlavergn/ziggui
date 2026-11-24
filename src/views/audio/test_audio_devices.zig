//! A fake `AudioDeviceBackend` for tests (the gallery's too): two devices
//! each way, and one stream each way at a time, whose captured samples a
//! test supplies (`capture`) and whose queued ones it plays out (`playOut`).

const std = @import("std");
const log = std.log.scoped(.ziggui_test_audio_devices);
const mod = @import("module.zig");

/// One fake stream: what was opened, and what it holds.
pub const TestAudioStream = struct {
    const Self = @This();

    /// The most samples a test can leave captured before the recorder reads them.
    pub const capacity = 8192;

    /// The stream is open.
    open: bool = false,

    /// The device asked for; null for the default.
    device: ?u32 = null,

    /// The rate asked for.
    sample_rate: u32 = 0,

    /// The stream's device is stopped.
    paused: bool = false,

    /// Samples captured and not read yet (recording).
    input: [capacity]i16 = undefined,

    /// How many of `input` are waiting.
    input_length: usize = 0,

    /// Every sample written (playback), counted from the stream's open.
    written: usize = 0,

    /// Samples written and not played yet (playback).
    queued: usize = 0,

    /// The gain last set.
    gain: f32 = 1,
};

/// The fake backend and its streams.
pub const TestAudioDevices = struct {
    const Self = @This();

    /// The fake's streams and lists.
    pub const backend: mod.AudioDeviceBackend = .{
        .list = Self.list,
        .open = Self.open,
        .close = Self.close,
        .set_paused = Self.setPaused,
        .read = Self.read,
        .write = Self.write,
        .queued = Self.queued,
        .clear = Self.clear,
        .set_gain = Self.setGain,
    };

    /// The recording stream (0) and the playback stream (1).
    var streams: [2]TestAudioStream = .{ .{}, .{} };

    /// `open` fails, as a device that cannot be opened does.
    pub var refuse_open: bool = false;

    /// Resets the streams and installs the fake for `AudioDevices`.
    pub fn install() void {
        streams = .{ .{}, .{} };
        refuse_open = false;
        mod.AudioDevices.setBackend(&backend);
    }

    /// Uninstalls the fake.
    pub fn uninstall() void {
        mod.AudioDevices.setBackend(null);
    }

    /// The stream one way.
    ///
    /// - `direction`: recording or playback.
    /// - Returns: its state.
    pub fn stream(direction: mod.AudioDirection) *TestAudioStream {
        return &streams[@backingInt(direction)];
    }

    /// Hands the recording stream samples, as a microphone does (dropped
    /// while it is closed or paused, or past its capacity).
    ///
    /// - `samples`: what the microphone heard.
    pub fn capture(samples: []const i16) void {
        const recording = Self.stream(.recording);
        if (!recording.open or recording.paused) return;
        const room = TestAudioStream.capacity - recording.input_length;
        const taken = @min(room, samples.len);
        @memcpy(recording.input[recording.input_length..][0..taken], samples[0..taken]);
        recording.input_length += taken;
    }

    /// Plays out queued samples, as the speaker does (none while paused).
    ///
    /// - `count`: the most to play.
    pub fn playOut(count: usize) void {
        const playback = Self.stream(.playback);
        if (!playback.open or playback.paused) return;
        playback.queued -|= count;
    }

    /// Lists two devices, each name owned, as a backend's are.
    ///
    /// - `allocator`: owns the list and its names.
    /// - `direction`: which two.
    /// - Returns: the devices; propagates allocation failure.
    fn list(allocator: std.mem.Allocator, direction: mod.AudioDirection) std.mem.Allocator.Error![]mod.AudioDevice {
        const names: [2][]const u8 = switch (direction) {
            .recording => .{ "Built-in Microphone", "USB Microphone" },
            .playback => .{ "Speakers", "Headphones" },
        };
        const devices = try allocator.alloc(mod.AudioDevice, 2);
        @memset(devices, .{ .id = 0, .name = "" });
        errdefer mod.AudioDevices.free(allocator, devices);
        for (devices, names, 0..) |*device, name, index| {
            device.* = .{ .id = @intCast(10 + index), .name = try allocator.dupe(u8, name) };
        }
        return devices;
    }

    /// Opens the stream one way, running, unless `refuse_open`.
    ///
    /// - `direction`: which stream.
    /// - `device`: the device asked for.
    /// - `sample_rate`: the rate asked for.
    /// - Returns: the stream, or null when refused.
    fn open(direction: mod.AudioDirection, device: ?u32, sample_rate: u32) ?*anyopaque {
        if (refuse_open) return null;
        const opened = Self.stream(direction);
        opened.* = .{ .open = true, .device = device, .sample_rate = sample_rate };
        return opened;
    }

    /// Closes a stream.
    ///
    /// - `handle`: the stream.
    fn close(handle: *anyopaque) void {
        Self.of(handle).* = .{};
    }

    /// Stops or restarts a stream.
    ///
    /// - `handle`: the stream.
    /// - `paused`: true to stop it.
    fn setPaused(handle: *anyopaque, paused: bool) void {
        Self.of(handle).paused = paused;
    }

    /// Takes captured samples.
    ///
    /// - `handle`: the recording stream.
    /// - `samples`: where they go.
    /// - Returns: how many were taken.
    fn read(handle: *anyopaque, samples: []i16) usize {
        const recording = Self.of(handle);
        const taken = @min(samples.len, recording.input_length);
        @memcpy(samples[0..taken], recording.input[0..taken]);
        @memmove(recording.input[0 .. recording.input_length - taken], recording.input[taken..recording.input_length]);
        recording.input_length -= taken;
        return taken;
    }

    /// Queues samples.
    ///
    /// - `handle`: the playback stream.
    /// - `samples`: what to play.
    /// - Returns: true.
    fn write(handle: *anyopaque, samples: []const i16) bool {
        const playback = Self.of(handle);
        playback.written += samples.len;
        playback.queued += samples.len;
        return true;
    }

    /// The samples still queued.
    ///
    /// - `handle`: the playback stream.
    /// - Returns: them.
    fn queued(handle: *anyopaque) usize {
        return Self.of(handle).queued;
    }

    /// Drops what a stream holds.
    ///
    /// - `handle`: the stream.
    fn clear(handle: *anyopaque) void {
        const cleared = Self.of(handle);
        cleared.queued = 0;
        cleared.input_length = 0;
    }

    /// Sets a stream's gain.
    ///
    /// - `handle`: the stream.
    /// - `gain`: its gain.
    fn setGain(handle: *anyopaque, gain: f32) void {
        Self.of(handle).gain = gain;
    }

    /// A handle as the stream it is.
    ///
    /// - `handle`: what `open` returned.
    /// - Returns: the stream.
    fn of(handle: *anyopaque) *TestAudioStream {
        return @ptrCast(@alignCast(handle));
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
