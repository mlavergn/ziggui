//! Plays an `AudioClip` through the installed `AudioDeviceBackend` (SDL's),
//! modeled on AVFoundation's `AVAudioPlayer`: play, pause, seek, stop. It
//! is apart from `Player` and the platform's media player: the clip is
//! queued on its own stream to the system's default output (or the device
//! asked for), whatever output a `Player` plays through. App-owned and
//! polled once a frame (`update`).

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_clip_player);
const mod = @import("module.zig");

/// A clip player the app owns. Call it from the UI thread.
pub const AudioClipPlayer = struct {
    const Self = @This();

    /// How often `update` asks for a frame while a clip plays, so a clock
    /// keeps up, in milliseconds.
    pub const refresh_interval_ms: u64 = 100;

    /// How long the stream stays open once its queue has run dry, in
    /// milliseconds: the device still plays what it took into its own
    /// buffer, which closing the stream at once would cut off.
    pub const tail_ms: u64 = 200;

    /// The device to play through (an `AudioDevice.id`), or null for the
    /// system's default; read as a clip starts.
    device: ?u32 = null,

    /// The volume, 0 silent to 1 full: the stream's own gain, never the
    /// system's volume; kept for the next clip, and heard at once mid-play.
    volume: f32 = 1,

    /// The clip loaded, borrowed: the app keeps it alive and in place
    /// until `stop` (or another clip's `play`).
    clip: ?*const mod.AudioClip = null,

    /// The clip is playing (else paused, or nothing loaded).
    playing: bool = false,

    /// The last `play` could not open the device or queue the clip.
    failed: bool = false,

    /// The sample of the clip the queue began at (0, or where it was sought to).
    start_sample: usize = 0,

    /// The `FrameClock` time the queue was first seen empty while playing,
    /// so the stream closes `tail_ms` later; null while samples are queued.
    drained_at_ms: ?u64 = null,

    /// The stream the clip plays through, while one is open.
    stream: ?*anyopaque = null,

    /// The backend `stream` came from.
    backend: ?*const mod.AudioDeviceBackend = null,

    /// Stops playing and closes the device.
    ///
    /// - `self`: the player.
    pub fn deinit(self: *Self) void {
        self.stop();
    }

    /// Plays a clip from its start, or resumes it where it was paused.
    ///
    /// - `self`: the player.
    /// - `clip`: what to play, borrowed until `stop` or another clip's `play`.
    /// - Returns: false when nothing can play (no backend, the device would
    ///   not open, the clip could not be queued: `failed`), or the clip is empty.
    pub fn play(self: *Self, clip: *const mod.AudioClip) bool {
        if (self.clip == clip and self.stream != null) {
            if (!self.playing) self.backend.?.set_paused(self.stream.?, false);
            self.playing = true;
            // Paused while its device played the last of it: that tail plays now.
            self.drained_at_ms = null;
            return true;
        }
        self.stop();
        if (clip.samples.len == 0) return false;
        const installed = mod.AudioDevices.backend() orelse {
            self.failed = true;
            return false;
        };
        const opened = installed.open(.playback, self.device, clip.sample_rate) orelse {
            self.failed = true;
            return false;
        };
        self.stream = opened;
        self.backend = installed;
        self.clip = clip;
        self.start_sample = 0;
        installed.set_gain(opened, self.volume);
        if (!installed.write(opened, clip.samples)) {
            self.stop();
            self.failed = true;
            return false;
        }
        self.playing = true;
        self.failed = false;
        return true;
    }

    /// Pauses the clip where it is; `play` with it resumes.
    ///
    /// - `self`: the player.
    pub fn pause(self: *Self) void {
        const stream = self.stream orelse return;
        if (!self.playing) return;
        self.backend.?.set_paused(stream, true);
        self.playing = false;
    }

    /// Moves the playhead, playing or paused.
    ///
    /// - `self`: the player.
    /// - `seconds`: where to, clamped to the clip.
    pub fn seek(self: *Self, seconds: f64) void {
        const stream = self.stream orelse return;
        const clip = self.clip.?;
        const wanted = if (std.math.isNan(seconds)) 0 else @max(0, seconds) * @as(f64, @floatFromInt(clip.sample_rate));
        const sample: usize = @intFromFloat(@min(wanted, @as(f64, @floatFromInt(clip.samples.len))));
        self.backend.?.clear(stream);
        self.start_sample = sample;
        self.drained_at_ms = null;
        if (!self.backend.?.write(stream, clip.samples[sample..])) {
            self.stop();
            self.failed = true;
        }
    }

    /// Sets the volume, on the clip playing too.
    ///
    /// - `self`: the player.
    /// - `volume`: 0 silent to 1 full, clamped; a value that is not finite is ignored.
    pub fn setVolume(self: *Self, volume: f32) void {
        if (!std.math.isFinite(volume)) return;
        self.volume = std.math.clamp(volume, 0, 1);
        if (self.stream) |stream| self.backend.?.set_gain(stream, self.volume);
    }

    /// The volume as a binding, for a `Slider(player.volumeBinding(), 0, 1)`:
    /// it reads `volume` and writes through `setVolume`. Its context is the
    /// player, so a slider dragged across frames stays the same slider.
    ///
    /// - `self`: the player.
    /// - Returns: the binding.
    pub fn volumeBinding(self: *Self) mod.Binding(f32) {
        return .{ .context = self, .get_fn = Self.boundVolume, .set_fn = Self.bindVolume };
    }

    /// Stops playing, closes the device and lets go of the clip.
    ///
    /// - `self`: the player.
    pub fn stop(self: *Self) void {
        if (self.stream) |stream| self.backend.?.close(stream);
        self.stream = null;
        self.backend = null;
        self.clip = null;
        self.playing = false;
        self.start_sample = 0;
        self.drained_at_ms = null;
    }

    /// Stops once the clip has played to its end (`tail_ms` after its queue
    /// ran dry, at once with no clock: headless and in tests), and while it
    /// plays asks for the next frame; call it once a frame.
    ///
    /// - `self`: the player.
    pub fn update(self: *Self) void {
        const stream = self.stream orelse return;
        if (!self.playing) return;
        const clock = mod.FrameClock.shared();
        const now = clock.time();
        if (self.backend.?.queued(stream) > 0) {
            self.drained_at_ms = null;
            clock.requestFrameAt(now + refresh_interval_ms);
            return;
        }
        const drained = self.drained_at_ms orelse now;
        self.drained_at_ms = drained;
        if (now == 0 or now >= drained + tail_ms) return self.stop();
        clock.requestFrameAt(drained + tail_ms);
    }

    /// Whether a clip is the one loaded (playing or paused).
    ///
    /// - `self`: the player.
    /// - `clip`: the clip.
    /// - Returns: true while it is loaded.
    pub fn holds(self: *const Self, clip: *const mod.AudioClip) bool {
        return self.clip == clip;
    }

    /// Where the playhead is.
    ///
    /// - `self`: the player.
    /// - Returns: seconds into the clip loaded; 0 with none.
    pub fn currentTime(self: *const Self) f64 {
        const clip = self.clip orelse return 0;
        const stream = self.stream orelse return 0;
        const left = @min(self.backend.?.queued(stream), clip.samples.len);
        return mod.AudioClip.secondsOf(clip.samples.len - left, clip.sample_rate);
    }

    /// `volumeBinding`'s reader.
    ///
    /// - `context`: the player.
    /// - Returns: its volume.
    fn boundVolume(context: *anyopaque) f32 {
        const self: *Self = @ptrCast(@alignCast(context));
        return self.volume;
    }

    /// `volumeBinding`'s writer.
    ///
    /// - `context`: the player.
    /// - `volume`: the new volume, as `setVolume` takes it.
    fn bindVolume(context: *anyopaque, volume: f32) void {
        const self: *Self = @ptrCast(@alignCast(context));
        self.setVolume(volume);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "audio clip player: queues the clip, pauses, resumes, seeks and stops at its end" {
    mod.TestAudioDevices.install();
    defer mod.TestAudioDevices.uninstall();
    var samples: [8]i16 = @splat(0);
    const clip = mod.AudioClip{ .samples = &samples, .sample_rate = 4 };
    var player: AudioClipPlayer = .{};
    defer player.deinit();

    try std.testing.expect(player.play(&clip));
    const stream = mod.TestAudioDevices.stream(.playback);
    try std.testing.expectEqual(@as(u32, 4), stream.sample_rate);
    try std.testing.expectEqual(@as(usize, 8), stream.queued);
    try std.testing.expect(player.holds(&clip) and player.playing);

    mod.TestAudioDevices.playOut(2);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), player.currentTime(), 1e-9);
    player.pause();
    try std.testing.expect(stream.paused and !player.playing);
    mod.TestAudioDevices.playOut(2);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), player.currentTime(), 1e-9);
    try std.testing.expect(player.play(&clip));
    try std.testing.expect(!stream.paused);
    try std.testing.expectEqual(@as(usize, 8), stream.written);

    // A seek queues the clip from there; past the end, nothing is left.
    player.seek(1.5);
    try std.testing.expectEqual(@as(usize, 2), stream.queued);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), player.currentTime(), 1e-9);
    mod.TestAudioDevices.playOut(2);
    player.update();
    try std.testing.expect(!player.holds(&clip));
    try std.testing.expect(!stream.open);
    try std.testing.expectEqual(@as(f64, 0), player.currentTime());
}

test "audio clip player: the stream stays open for the device's last buffer once the queue runs dry" {
    mod.TestAudioDevices.install();
    defer mod.TestAudioDevices.uninstall();
    const clock = mod.FrameClock.shared();
    clock.setTime(1000);
    defer clock.setTime(0);
    // Another test's request would win as the earliest.
    _ = clock.frameDueIn(std.math.maxInt(u64));
    var samples = [_]i16{ 1, 2, 3, 4 };
    const clip = mod.AudioClip{ .samples = &samples, .sample_rate = 4 };
    var player: AudioClipPlayer = .{};
    defer player.deinit();
    try std.testing.expect(player.play(&clip));
    mod.TestAudioDevices.playOut(4);
    player.update();
    try std.testing.expect(player.holds(&clip) and player.playing);
    try std.testing.expectEqual(@as(?u64, AudioClipPlayer.tail_ms), clock.frameDueIn(1000));
    clock.setTime(1000 + AudioClipPlayer.tail_ms - 1);
    player.update();
    try std.testing.expect(player.holds(&clip));
    clock.setTime(1000 + AudioClipPlayer.tail_ms);
    player.update();
    try std.testing.expect(!player.holds(&clip));
    try std.testing.expect(!mod.TestAudioDevices.stream(.playback).open);
}

test "audio clip player: an empty clip or no device plays nothing" {
    mod.TestAudioDevices.install();
    defer mod.TestAudioDevices.uninstall();
    var player: AudioClipPlayer = .{};
    defer player.deinit();
    const empty = mod.AudioClip{};
    try std.testing.expect(!player.play(&empty));
    var samples = [_]i16{ 1, 2 };
    const clip = mod.AudioClip{ .samples = &samples };
    mod.TestAudioDevices.refuse_open = true;
    try std.testing.expect(!player.play(&clip));
    try std.testing.expect(player.failed);
    mod.TestAudioDevices.uninstall();
    mod.TestAudioDevices.refuse_open = false;
    try std.testing.expect(!player.play(&clip));
}

test "audio clip player: the volume sets the stream's gain, as a clip starts and while it plays" {
    mod.TestAudioDevices.install();
    defer mod.TestAudioDevices.uninstall();
    var samples = [_]i16{ 1, 2, 3 };
    const clip = mod.AudioClip{ .samples = &samples };
    var player: AudioClipPlayer = .{};
    defer player.deinit();
    const binding = player.volumeBinding();
    binding.set(0.5);
    try std.testing.expect(player.play(&clip));
    const stream = mod.TestAudioDevices.stream(.playback);
    try std.testing.expectEqual(@as(f32, 0.5), stream.gain);
    binding.set(2);
    try std.testing.expectEqual(@as(f32, 1), stream.gain);
    player.setVolume(std.math.nan(f32));
    try std.testing.expectEqual(@as(f32, 1), binding.get());
    binding.set(-1);
    try std.testing.expectEqual(@as(f32, 0), stream.gain);
}
