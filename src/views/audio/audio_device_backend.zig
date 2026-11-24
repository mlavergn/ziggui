//! The platform's audio streams, as function pointers: the SDL runtime
//! installs its own as its loop starts (`AudioDevices.setBackend`), so
//! `AudioRecorder` and `AudioClipPlayer` stay free of platform code, and
//! tests install a fake. A stream is mono 16-bit samples at the rate it was
//! opened with, converted by the backend to and from the device's own.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_device_backend);
const mod = @import("module.zig");

/// One platform's audio devices and streams. Every call runs on the UI thread.
pub const AudioDeviceBackend = struct {
    const Self = @This();

    /// Lists the devices that record or play now, each once.
    ///
    /// - `allocator`: owns the list and its names (an arena suits).
    /// - `direction`: recording or playback devices.
    /// - Returns: the devices, none where the system reports none; propagates
    ///   allocation failure.
    list: *const fn (allocator: std.mem.Allocator, direction: mod.AudioDirection) std.mem.Allocator.Error![]mod.AudioDevice,

    /// Opens a stream on a device, running: a recording stream starts
    /// capturing, a playback stream plays what is written to it.
    ///
    /// - `direction`: recording or playback.
    /// - `device`: an `AudioDevice.id`, or null for the system's default
    ///   (which follows the system's choice).
    /// - `sample_rate`: the stream's samples a second.
    /// - Returns: the stream, or null when the device cannot be opened (logged).
    open: *const fn (direction: mod.AudioDirection, device: ?u32, sample_rate: u32) ?*anyopaque,

    /// Closes a stream and the device it opened; what it held is dropped.
    ///
    /// - `stream`: what `open` returned.
    close: *const fn (stream: *anyopaque) void,

    /// Stops or restarts a stream's device, keeping what it holds.
    ///
    /// - `stream`: what `open` returned.
    /// - `paused`: true to stop it, false to run it again.
    set_paused: *const fn (stream: *anyopaque, paused: bool) void,

    /// Takes captured samples from a recording stream.
    ///
    /// - `stream`: a recording stream.
    /// - `samples`: where they go.
    /// - Returns: how many were taken, at most `samples.len`; 0 when none
    ///   are waiting.
    read: *const fn (stream: *anyopaque, samples: []i16) usize,

    /// Queues samples on a playback stream, after what it holds, and plays
    /// them to their last: nothing is held back waiting for more (a
    /// resampling stream would keep its last few otherwise, and `queued`
    /// never reach 0).
    ///
    /// - `stream`: a playback stream.
    /// - `samples`: what to play; copied.
    /// - Returns: false when they could not be queued (logged).
    write: *const fn (stream: *anyopaque, samples: []const i16) bool,

    /// How much a playback stream holds that has not played yet.
    ///
    /// - `stream`: a playback stream.
    /// - Returns: the samples still queued.
    queued: *const fn (stream: *anyopaque) usize,

    /// Drops what a stream holds: a playback stream's queued samples, a
    /// recording stream's captured ones.
    ///
    /// - `stream`: what `open` returned.
    clear: *const fn (stream: *anyopaque) void,

    /// Scales a stream's samples as they pass, at once, even mid-play: the
    /// stream's own gain, never the system's volume.
    ///
    /// - `stream`: what `open` returned.
    /// - `gain`: 0 silent, 1 unchanged.
    set_gain: *const fn (stream: *anyopaque, gain: f32) void,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
