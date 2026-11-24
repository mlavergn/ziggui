//! The audio devices `AudioRecorder` records from and `AudioClipPlayer`
//! plays through: SDL's, through the `AudioDeviceBackend` the runtime
//! installs as its loop starts. With none installed (headless, in tests)
//! nothing records or plays, and an app says so.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_devices);
const mod = @import("module.zig");

/// The installed audio device backend, and its device lists.
pub const AudioDevices = struct {
    const Self = @This();

    /// The backend recorders and clip players open streams with; null
    /// headless and in tests, unless a test installs one.
    var installed_backend: ?*const mod.AudioDeviceBackend = null;

    /// Installs the backend streams are opened with; the SDL runtime calls
    /// this as its loop starts and ends. A stream keeps the backend it was
    /// opened with.
    ///
    /// - `installed`: the platform's streams; null for none.
    pub fn setBackend(installed: ?*const mod.AudioDeviceBackend) void {
        installed_backend = installed;
    }

    /// The installed backend.
    ///
    /// - Returns: it, or null for none.
    pub fn backend() ?*const mod.AudioDeviceBackend {
        return installed_backend;
    }

    /// Whether anything can record or play here.
    ///
    /// - Returns: true with a backend installed.
    pub fn available() bool {
        return installed_backend != null;
    }

    /// Lists the devices now: call it when a menu opens, or into the build
    /// arena while one is open.
    ///
    /// - `allocator`: owns the list and its names: free them with `free`, or
    ///   with an arena all at once.
    /// - `direction`: recording or playback devices.
    /// - Returns: the devices, none without a backend; propagates allocation failure.
    pub fn list(allocator: std.mem.Allocator, direction: mod.AudioDirection) std.mem.Allocator.Error![]mod.AudioDevice {
        const installed = installed_backend orelse return &.{};
        return installed.list(allocator, direction);
    }

    /// Frees a list `list` made, and its names.
    ///
    /// - `allocator`: the allocator `list` was given.
    /// - `devices`: the list.
    pub fn free(allocator: std.mem.Allocator, devices: []const mod.AudioDevice) void {
        for (devices) |device| allocator.free(device.name);
        allocator.free(devices);
    }

    /// The device among `devices` whose id is `id`, for a menu's tick.
    ///
    /// - `devices`: what `list` returned.
    /// - `id`: the id asked for, or null for the system default.
    /// - Returns: its index, or null for the system default or a device gone.
    pub fn indexOf(devices: []const mod.AudioDevice, id: ?u32) ?usize {
        const wanted = id orelse return null;
        for (devices, 0..) |device, index| {
            if (device.id == wanted) return index;
        }
        return null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "audio devices: none without a backend, the installed one's with it" {
    AudioDevices.setBackend(null);
    try std.testing.expect(!AudioDevices.available());
    try std.testing.expectEqual(@as(usize, 0), (try AudioDevices.list(std.testing.allocator, .recording)).len);

    mod.TestAudioDevices.install();
    defer mod.TestAudioDevices.uninstall();
    try std.testing.expect(AudioDevices.available());
    const devices = try AudioDevices.list(std.testing.allocator, .recording);
    defer AudioDevices.free(std.testing.allocator, devices);
    try std.testing.expectEqual(@as(usize, 2), devices.len);
    try std.testing.expectEqual(@as(?usize, 1), AudioDevices.indexOf(devices, devices[1].id));
    try std.testing.expectEqual(@as(?usize, null), AudioDevices.indexOf(devices, 999));
    try std.testing.expectEqual(@as(?usize, null), AudioDevices.indexOf(devices, null));
}
