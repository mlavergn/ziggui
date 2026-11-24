//! SDL's audio devices for `AudioRecorder` and `AudioClipPlayer`: the
//! `AudioDeviceBackend` the event loop installs as it starts. Each stream is
//! an `SDL_AudioStream` bound to a device (`SDL_OpenAudioDeviceStream`), mono
//! 16-bit at the rate asked for, SDL converting to and from the device's own
//! format; no callback runs on SDL's audio thread, the recorder and the
//! player reading and writing the streams from the UI thread once a frame.
//! The audio subsystem starts on first need, so an app that never records or
//! plays a clip never opens the system's audio. It is apart from the
//! platform media player (`VideoBackend`) and the outputs it routes to
//! (`AudioBackend`): SDL's device ids are its own.

const std = @import("std");
const log = std.log.scoped(.ziggui_sdl_audio_devices);
const views = @import("views");
const sdl_c = @import("sdl_c");

/// One stream a recorder or a clip player holds: the handle they are given,
/// which outlives the SDL stream when the loop ends first (`uninstall`
/// closes every stream before `SDL_Quit` would free them).
const SdlAudioSlot = struct {
    const Self = @This();

    /// The SDL stream, null while the slot is free or once `uninstall` closed it.
    stream: ?*sdl_c.SDL_AudioStream = null,

    /// A recorder or player holds the slot (until it calls `close`).
    taken: bool = false,
};

/// SDL's audio devices, as the event loop installs them.
pub const SdlAudioDevices = struct {
    const Self = @This();

    /// The most streams open at once.
    const max_streams = 16;

    /// SDL's `SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK`, the default output, which
    /// follows the system's choice (a cast macro translate-c does not keep).
    const default_playback: sdl_c.SDL_AudioDeviceID = 0xFFFF_FFFF;

    /// SDL's `SDL_AUDIO_DEVICE_DEFAULT_RECORDING`, the default input.
    const default_recording: sdl_c.SDL_AudioDeviceID = 0xFFFF_FFFE;

    /// The streams, as their holders' handles.
    var slots: [max_streams]SdlAudioSlot = @splat(.{});

    /// The audio subsystem was started by `start`.
    var started = false;

    /// The backend `AudioDevices` asks.
    pub const backend: views.AudioDeviceBackend = .{
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

    /// Installs SDL's devices as the ones `AudioDevices` asks.
    pub fn install() void {
        views.AudioDevices.setBackend(&backend);
    }

    /// Uninstalls them, closing every stream still open (its holder's
    /// handle then reads as closed) and the audio subsystem; the loop calls
    /// this before `SDL_Quit`.
    pub fn uninstall() void {
        views.AudioDevices.setBackend(null);
        for (&slots) |*slot| {
            if (slot.stream) |stream| sdl_c.SDL_DestroyAudioStream(stream);
            slot.stream = null;
        }
        if (started) sdl_c.SDL_QuitSubSystem(sdl_c.SDL_INIT_AUDIO);
        started = false;
    }

    /// Starts the audio subsystem, once.
    ///
    /// - Returns: whether it runs.
    fn start() bool {
        if (started) return true;
        if (!sdl_c.SDL_InitSubSystem(sdl_c.SDL_INIT_AUDIO)) {
            log.warn("audio not started: {s}", .{sdl_c.SDL_GetError()});
            return false;
        }
        started = true;
        return true;
    }

    /// Lists SDL's recording or playback devices.
    ///
    /// - `allocator`: owns the list and its names.
    /// - `direction`: which devices.
    /// - Returns: the devices, none when audio cannot start; propagates allocation failure.
    fn list(allocator: std.mem.Allocator, direction: views.AudioDirection) std.mem.Allocator.Error![]views.AudioDevice {
        if (!Self.start()) return &.{};
        var count: c_int = 0;
        const ids = switch (direction) {
            .recording => sdl_c.SDL_GetAudioRecordingDevices(&count),
            .playback => sdl_c.SDL_GetAudioPlaybackDevices(&count),
        } orelse {
            log.warn("audio devices not listed: {s}", .{sdl_c.SDL_GetError()});
            return &.{};
        };
        defer sdl_c.SDL_free(ids);
        var devices: std.ArrayList(views.AudioDevice) = .empty;
        errdefer {
            for (devices.items) |device| allocator.free(device.name);
            devices.deinit(allocator);
        }
        for (ids[0..@intCast(@max(count, 0))]) |id| {
            const name = if (sdl_c.SDL_GetAudioDeviceName(id)) |text| std.mem.span(text) else "";
            try devices.ensureUnusedCapacity(allocator, 1);
            devices.appendAssumeCapacity(.{ .id = id, .name = try allocator.dupe(u8, name) });
        }
        return devices.toOwnedSlice(allocator);
    }

    /// Opens a stream on a device, its device running.
    ///
    /// - `direction`: recording or playback.
    /// - `device`: an `AudioDevice.id`, or null for the default.
    /// - `sample_rate`: the stream's rate.
    /// - Returns: the stream's slot, or null (logged).
    fn open(direction: views.AudioDirection, device: ?u32, sample_rate: u32) ?*anyopaque {
        if (!Self.start()) return null;
        const slot = for (&slots) |*slot| {
            if (!slot.taken) break slot;
        } else {
            log.warn("audio stream not opened: {d} already open", .{max_streams});
            return null;
        };
        const frequency = std.math.cast(c_int, sample_rate) orelse {
            log.warn("audio device not opened: a rate of {d} is out of range", .{sample_rate});
            return null;
        };
        const specification: sdl_c.SDL_AudioSpec = .{ .format = sdl_c.SDL_AUDIO_S16LE, .channels = 1, .freq = frequency };
        const id = device orelse switch (direction) {
            .recording => default_recording,
            .playback => default_playback,
        };
        const stream = sdl_c.SDL_OpenAudioDeviceStream(id, &specification, null, null) orelse {
            log.warn("audio device not opened: {s}", .{sdl_c.SDL_GetError()});
            return null;
        };
        // A device stream opens paused.
        if (!sdl_c.SDL_ResumeAudioStreamDevice(stream)) {
            log.warn("audio device not started: {s}", .{sdl_c.SDL_GetError()});
            sdl_c.SDL_DestroyAudioStream(stream);
            return null;
        }
        slot.* = .{ .stream = stream, .taken = true };
        return slot;
    }

    /// Closes a stream and its device, and frees its slot.
    ///
    /// - `handle`: the stream's slot.
    fn close(handle: *anyopaque) void {
        const slot = Self.of(handle);
        if (slot.stream) |stream| sdl_c.SDL_DestroyAudioStream(stream);
        slot.* = .{};
    }

    /// Stops or restarts a stream's device.
    ///
    /// - `handle`: the stream's slot.
    /// - `paused`: true to stop it.
    fn setPaused(handle: *anyopaque, paused: bool) void {
        const stream = Self.of(handle).stream orelse return;
        const done = if (paused) sdl_c.SDL_PauseAudioStreamDevice(stream) else sdl_c.SDL_ResumeAudioStreamDevice(stream);
        if (!done) log.warn("audio device not {s}: {s}", .{ if (paused) "paused" else "resumed", sdl_c.SDL_GetError() });
    }

    /// Takes captured samples from a recording stream.
    ///
    /// - `handle`: the stream's slot.
    /// - `samples`: where they go.
    /// - Returns: how many were taken.
    fn read(handle: *anyopaque, samples: []i16) usize {
        const stream = Self.of(handle).stream orelse return 0;
        const wanted: c_int = @intCast(@min(samples.len * 2, std.math.maxInt(c_int)));
        const got = sdl_c.SDL_GetAudioStreamData(stream, samples.ptr, wanted);
        if (got < 0) {
            log.warn("audio not read: {s}", .{sdl_c.SDL_GetError()});
            return 0;
        }
        return @as(usize, @intCast(got)) / 2;
    }

    /// Queues samples on a playback stream and flushes it, so they play to
    /// their last.
    ///
    /// - `handle`: the stream's slot.
    /// - `samples`: what to play; SDL copies them.
    /// - Returns: false when they were not queued (logged).
    fn write(handle: *anyopaque, samples: []const i16) bool {
        const stream = Self.of(handle).stream orelse return false;
        if (samples.len == 0) return true;
        const length = std.math.cast(c_int, samples.len * 2) orelse {
            log.warn("audio not queued: {d} samples is too many", .{samples.len});
            return false;
        };
        if (!sdl_c.SDL_PutAudioStreamData(stream, samples.ptr, length)) {
            log.warn("audio not queued: {s}", .{sdl_c.SDL_GetError()});
            return false;
        }
        // Without a flush a resampling stream keeps its last samples for
        // more input, so the clip would never finish.
        if (!sdl_c.SDL_FlushAudioStream(stream)) {
            log.warn("audio not flushed: {s}", .{sdl_c.SDL_GetError()});
            return false;
        }
        return true;
    }

    /// The samples a playback stream holds that have not played.
    ///
    /// - `handle`: the stream's slot.
    /// - Returns: them; 0 for a stream closed.
    fn queued(handle: *anyopaque) usize {
        const stream = Self.of(handle).stream orelse return 0;
        const bytes = sdl_c.SDL_GetAudioStreamQueued(stream);
        return if (bytes < 0) 0 else @as(usize, @intCast(bytes)) / 2;
    }

    /// Drops what a stream holds.
    ///
    /// - `handle`: the stream's slot.
    fn clear(handle: *anyopaque) void {
        const stream = Self.of(handle).stream orelse return;
        if (!sdl_c.SDL_ClearAudioStream(stream)) log.warn("audio stream not cleared: {s}", .{sdl_c.SDL_GetError()});
    }

    /// Sets a stream's gain (`SDL_SetAudioStreamGain`), applied as SDL
    /// converts what is queued, so a change is heard at once.
    ///
    /// - `handle`: the stream's slot.
    /// - `gain`: 0 silent, 1 unchanged.
    fn setGain(handle: *anyopaque, gain: f32) void {
        const stream = Self.of(handle).stream orelse return;
        if (!sdl_c.SDL_SetAudioStreamGain(stream, gain)) log.warn("audio gain not set: {s}", .{sdl_c.SDL_GetError()});
    }

    /// A handle as the slot it is.
    ///
    /// - `handle`: what `open` returned.
    /// - Returns: the slot.
    fn of(handle: *anyopaque) *SdlAudioSlot {
        return @ptrCast(@alignCast(handle));
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// Runs SDL's audio on its dummy driver, so a test opens no real device.
const DummyAudio = struct {
    const Self = @This();

    /// Points SDL at the dummy driver, before the subsystem starts.
    fn use() void {
        _ = sdl_c.SDL_SetHint(sdl_c.SDL_HINT_AUDIO_DRIVER, "dummy");
    }

    /// Puts the driver choice back.
    fn release() void {
        _ = sdl_c.SDL_ResetHint(sdl_c.SDL_HINT_AUDIO_DRIVER);
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "sdl audio devices: a playback stream queues a clip, pauses, clears and closes" {
    DummyAudio.use();
    defer DummyAudio.release();
    SdlAudioDevices.install();
    defer SdlAudioDevices.uninstall();
    const handle = SdlAudioDevices.backend.open(.playback, null, 8000) orelse return error.SkipZigTest;
    defer SdlAudioDevices.backend.close(handle);
    SdlAudioDevices.backend.set_paused(handle, true);
    SdlAudioDevices.backend.set_gain(handle, 0.25);
    try std.testing.expectEqual(@as(f32, 0.25), sdl_c.SDL_GetAudioStreamGain(SdlAudioDevices.slots[0].stream));
    var samples: [800]i16 = @splat(100);
    try std.testing.expect(SdlAudioDevices.backend.write(handle, &samples));
    try std.testing.expectEqual(@as(usize, 800), SdlAudioDevices.backend.queued(handle));
    SdlAudioDevices.backend.clear(handle);
    try std.testing.expectEqual(@as(usize, 0), SdlAudioDevices.backend.queued(handle));
}

test "sdl audio devices: a resampled clip plays to its end, and a rate SDL cannot take is refused" {
    DummyAudio.use();
    defer DummyAudio.release();
    SdlAudioDevices.install();
    defer SdlAudioDevices.uninstall();
    try std.testing.expectEqual(@as(?*anyopaque, null), SdlAudioDevices.backend.open(.playback, null, std.math.maxInt(u32)));
    // A rate no device runs at, so SDL resamples: flushed, nothing waits for more input.
    const handle = SdlAudioDevices.backend.open(.playback, null, 7_919) orelse return error.SkipZigTest;
    defer SdlAudioDevices.backend.close(handle);
    SdlAudioDevices.backend.set_paused(handle, true);
    var samples: [441]i16 = @splat(100);
    try std.testing.expect(SdlAudioDevices.backend.write(handle, &samples));
    const stream = SdlAudioDevices.of(handle).stream.?;
    var converted: [4096]u8 = undefined;
    while (sdl_c.SDL_GetAudioStreamData(stream, &converted, converted.len) > 0) {}
    try std.testing.expectEqual(@as(usize, 0), SdlAudioDevices.backend.queued(handle));
}

test "sdl audio devices: a recording stream opens and reads, and uninstall closes what is left" {
    DummyAudio.use();
    defer DummyAudio.release();
    SdlAudioDevices.install();
    const handle = SdlAudioDevices.backend.open(.recording, null, 16_000) orelse {
        SdlAudioDevices.uninstall();
        return error.SkipZigTest;
    };
    var samples: [64]i16 = undefined;
    _ = SdlAudioDevices.backend.read(handle, &samples);
    const devices = try SdlAudioDevices.backend.list(std.testing.allocator, .recording);
    views.AudioDevices.free(std.testing.allocator, devices);

    // The loop ends with the stream still held: its handle reads as closed.
    SdlAudioDevices.uninstall();
    try std.testing.expectEqual(@as(usize, 0), SdlAudioDevices.backend.read(handle, &samples));
    try std.testing.expect(!SdlAudioDevices.backend.write(handle, &samples));
    SdlAudioDevices.backend.close(handle);
    try std.testing.expect(!SdlAudioDevices.slots[0].taken);
}
