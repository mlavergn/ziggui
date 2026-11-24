//! A sound recorder modeled on AVFoundation's `AVAudioRecorder`: records
//! mono 16-bit samples from a microphone through the installed
//! `AudioDeviceBackend` (SDL's), pauses and resumes, and hands the take over
//! as an `AudioClip` on `stop`. App-owned and polled once a frame
//! (`update`), as a `Player` is: no callbacks reach it from the audio thread.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_recorder);
const mod = @import("module.zig");

/// What a recorder is doing.
pub const AudioRecorderStatus = enum {
    const Self = @This();

    /// Nothing recorded since the last `stop` or `cancel`.
    idle,
    /// Capturing from the microphone.
    recording,
    /// Holding a take, its device stopped; `record` resumes it.
    paused,
};

/// A microphone recorder the app owns. Call it from the UI thread.
pub const AudioRecorder = struct {
    const Self = @This();

    /// The longest take `record` keeps by default, in seconds (a memo, not
    /// an album: ten minutes at 48 kHz is about 55 MB).
    pub const default_limit_seconds: u32 = 600;

    /// How often `update` asks for a frame while recording, so a meter and
    /// a clock keep up, in milliseconds.
    pub const refresh_interval_ms: u64 = 50;

    /// The highest `gain`: twice the microphone's level.
    pub const max_gain: f32 = 2;

    /// The samples `update` takes from the stream at a time.
    const read_chunk = 4096;

    /// How much room the take grows by at a time, in seconds: a step rather
    /// than doubling, so a long take holds at most this much spare (doubling
    /// held up to as much again as it recorded, and more while it copied).
    pub const growth_seconds: u32 = 30;

    /// Owns the take.
    allocator: std.mem.Allocator,

    /// The rate the take is recorded at.
    sample_rate: u32 = mod.AudioClip.default_sample_rate,

    /// The longest take, in seconds: at it, recording pauses and
    /// `reached_limit` is set.
    limit_seconds: u32 = default_limit_seconds,

    /// The device to record from (an `AudioDevice.id`), or null for the
    /// system's default; read as a take starts.
    device: ?u32 = null,

    /// Software gain, 0 to `max_gain`, 1 unchanged: the recording stream
    /// scales the samples before the take (and `level`) gets them, so noise
    /// rises with the voice and a sample past full scale clips. It is not the
    /// microphone's own input level, which the system's sound settings set.
    gain: f32 = 1,

    /// What the recorder is doing.
    status: AudioRecorderStatus = .idle,

    /// The take so far.
    samples: std.ArrayList(i16) = .empty,

    /// The loudest of the samples the last `update` took, 0 to 1, for a meter.
    level: f32 = 0,

    /// The take reached `limit_seconds` and recording paused.
    reached_limit: bool = false,

    /// The last `record` could not open the device; cleared by the next
    /// `record` that opens it.
    failed: bool = false,

    /// The take could not grow (memory ran out) and recording paused;
    /// cleared as the take ends or a new one starts.
    out_of_memory: bool = false,

    /// The stream the take is recorded through, while one is open.
    stream: ?*anyopaque = null,

    /// The backend `stream` came from.
    backend: ?*const mod.AudioDeviceBackend = null,

    /// A recorder holding nothing.
    ///
    /// - `allocator`: owns the takes.
    /// - Returns: the recorder.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Closes the device and drops the take.
    ///
    /// - `self`: the recorder.
    pub fn deinit(self: *Self) void {
        self.closeStream();
        self.samples.deinit(self.allocator);
        self.* = .{ .allocator = self.allocator, .sample_rate = self.sample_rate, .limit_seconds = self.limit_seconds, .device = self.device, .gain = self.gain };
    }

    /// Starts a take, or resumes a paused one; the device opens on a take's
    /// start (macOS asks the user for the microphone then, the first time).
    ///
    /// - `self`: the recorder.
    /// - Returns: false when nothing can record (no backend, or the device
    ///   would not open: `failed`), or a paused take is at its limit or out
    ///   of memory.
    pub fn record(self: *Self) bool {
        switch (self.status) {
            .recording => return true,
            .paused => {
                if (self.reached_limit or self.out_of_memory) return false;
                self.backend.?.set_paused(self.stream.?, false);
                self.status = .recording;
                return true;
            },
            .idle => {},
        }
        const installed = mod.AudioDevices.backend() orelse {
            self.failed = true;
            return false;
        };
        const opened = installed.open(.recording, self.device, self.sample_rate) orelse {
            self.failed = true;
            return false;
        };
        self.samples.clearRetainingCapacity();
        installed.set_gain(opened, self.gain);
        self.stream = opened;
        self.backend = installed;
        self.status = .recording;
        self.level = 0;
        self.reached_limit = false;
        self.out_of_memory = false;
        self.failed = false;
        return true;
    }

    /// Pauses the take, keeping what was recorded; `record` resumes it.
    ///
    /// - `self`: the recorder.
    pub fn pause(self: *Self) void {
        if (self.status != .recording) return;
        self.drain();
        // `drain` may have paused it at the limit already.
        if (self.status != .recording) return;
        self.backend.?.set_paused(self.stream.?, true);
        self.status = .paused;
        self.level = 0;
    }

    /// Ends the take and closes the device.
    ///
    /// - `self`: the recorder.
    /// - Returns: the take, owned by the recorder's allocator (`AudioClip.deinit`
    ///   frees it), or null when nothing was recorded; propagates allocation failure.
    pub fn stop(self: *Self) std.mem.Allocator.Error!?mod.AudioClip {
        if (self.status == .idle) return null;
        if (self.status == .recording) self.drain();
        self.closeStream();
        self.status = .idle;
        self.level = 0;
        self.reached_limit = false;
        self.out_of_memory = false;
        if (self.samples.items.len == 0) return null;
        const samples = try self.samples.toOwnedSlice(self.allocator);
        const clip = mod.AudioClip{ .samples = samples, .sample_rate = self.sample_rate };
        return clip;
    }

    /// Ends the take and drops it.
    ///
    /// - `self`: the recorder.
    pub fn cancel(self: *Self) void {
        self.closeStream();
        self.samples.clearRetainingCapacity();
        self.status = .idle;
        self.level = 0;
        self.reached_limit = false;
        self.out_of_memory = false;
    }

    /// Sets the software gain, on the take recording too.
    ///
    /// - `self`: the recorder.
    /// - `gain`: 0 to `max_gain`, clamped; a value that is not finite is ignored.
    pub fn setGain(self: *Self, gain: f32) void {
        if (!std.math.isFinite(gain)) return;
        self.gain = std.math.clamp(gain, 0, max_gain);
        if (self.stream) |stream| self.backend.?.set_gain(stream, self.gain);
    }

    /// The software gain as a binding, for a
    /// `Slider(recorder.gainBinding(), 0, AudioRecorder.max_gain)`: it reads
    /// `gain` and writes through `setGain`. Its context is the recorder, so a
    /// slider dragged across frames stays the same slider.
    ///
    /// - `self`: the recorder.
    /// - Returns: the binding.
    pub fn gainBinding(self: *Self) mod.Binding(f32) {
        return .{ .context = self, .get_fn = Self.boundGain, .set_fn = Self.bindGain };
    }

    /// Takes what the microphone captured since the last call into the take
    /// and sets `level`, and while recording asks for the next frame; call
    /// it once a frame, as the recorder's view builds.
    ///
    /// - `self`: the recorder.
    pub fn update(self: *Self) void {
        if (self.status != .recording) return;
        self.drain();
        if (self.status == .recording) {
            const clock = mod.FrameClock.shared();
            clock.requestFrameAt(clock.time() + refresh_interval_ms);
        }
    }

    /// The take so far.
    ///
    /// - `self`: the recorder.
    /// - Returns: its samples, borrowed until the recorder next changes.
    pub fn recorded(self: *const Self) []const i16 {
        return self.samples.items;
    }

    /// How long the take is.
    ///
    /// - `self`: the recorder.
    /// - Returns: its length in seconds.
    pub fn currentTime(self: *const Self) f64 {
        return mod.AudioClip.secondsOf(self.samples.items.len, self.sample_rate);
    }

    /// `gainBinding`'s reader.
    ///
    /// - `context`: the recorder.
    /// - Returns: its gain.
    fn boundGain(context: *anyopaque) f32 {
        const self: *Self = @ptrCast(@alignCast(context));
        return self.gain;
    }

    /// `gainBinding`'s writer.
    ///
    /// - `context`: the recorder.
    /// - `gain`: the new gain, as `setGain` takes it.
    fn bindGain(context: *anyopaque, gain: f32) void {
        const self: *Self = @ptrCast(@alignCast(context));
        self.setGain(gain);
    }

    /// Takes every waiting sample into the take, up to the limit, where it
    /// pauses; a take that cannot grow pauses too, `out_of_memory` set.
    ///
    /// - `self`: the recorder.
    fn drain(self: *Self) void {
        const stream = self.stream orelse return;
        const installed = self.backend.?;
        const limit = @as(usize, self.limit_seconds) * self.sample_rate;
        var chunk: [read_chunk]i16 = undefined;
        var peak: ?f32 = null;
        while (true) {
            const taken = installed.read(stream, &chunk);
            if (taken == 0) break;
            const room = limit -| self.samples.items.len;
            const kept = chunk[0..@min(taken, room)];
            self.reserve(kept.len, limit) catch |err| {
                log.warn("recording paused: {s}", .{@errorName(err)});
                self.out_of_memory = true;
                self.pauseStream();
                return;
            };
            self.samples.appendSliceAssumeCapacity(kept);
            peak = @max(peak orelse 0, mod.AudioClip.peakLevel(kept));
            if (self.samples.items.len >= limit) {
                self.reached_limit = true;
                self.pauseStream();
                break;
            }
        }
        // A take that paused on the way keeps its meter at rest.
        if (self.status != .recording) return;
        if (peak) |value| self.level = value;
    }

    /// Makes room in the take for samples about to be added, growing it by
    /// `growth_seconds` at a time, never past the limit.
    ///
    /// - `self`: the recorder.
    /// - `count`: the samples to be added, which fit under the limit.
    /// - `limit`: the most samples the take holds.
    /// - Returns: nothing; propagates allocation failure.
    fn reserve(self: *Self, count: usize, limit: usize) std.mem.Allocator.Error!void {
        if (self.samples.unusedCapacitySlice().len >= count) return;
        const step = @as(usize, growth_seconds) * self.sample_rate;
        const wanted = @min(limit, self.samples.items.len + @max(count, step));
        try self.samples.ensureTotalCapacityPrecise(self.allocator, @max(wanted, self.samples.items.len + count));
    }

    /// Stops the device, keeping the take, as the limit or a failure does.
    ///
    /// - `self`: the recorder.
    fn pauseStream(self: *Self) void {
        self.backend.?.set_paused(self.stream.?, true);
        self.status = .paused;
        self.level = 0;
    }

    /// Closes the stream, if one is open.
    ///
    /// - `self`: the recorder.
    fn closeStream(self: *Self) void {
        if (self.stream) |stream| self.backend.?.close(stream);
        self.stream = null;
        self.backend = null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "audio recorder: records what the microphone hears, pauses, resumes and hands the take over" {
    mod.TestAudioDevices.install();
    defer mod.TestAudioDevices.uninstall();
    var recorder = AudioRecorder.init(std.testing.allocator);
    defer recorder.deinit();
    recorder.device = 11;

    try std.testing.expect(recorder.record());
    const stream = mod.TestAudioDevices.stream(.recording);
    try std.testing.expect(stream.open and !stream.paused);
    try std.testing.expectEqual(@as(?u32, 11), stream.device);
    try std.testing.expectEqual(mod.AudioClip.default_sample_rate, stream.sample_rate);

    mod.TestAudioDevices.capture(&.{ 1, -16384, 3 });
    recorder.update();
    try std.testing.expectEqualSlices(i16, &.{ 1, -16384, 3 }, recorder.recorded());
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), recorder.level, 0.001);

    // Paused, the device stops and nothing more is taken; resumed, it adds on.
    recorder.pause();
    try std.testing.expectEqual(AudioRecorderStatus.paused, recorder.status);
    try std.testing.expect(stream.paused);
    mod.TestAudioDevices.capture(&.{ 9, 9 });
    recorder.update();
    try std.testing.expectEqual(@as(usize, 3), recorder.recorded().len);
    try std.testing.expect(recorder.record());
    mod.TestAudioDevices.capture(&.{4});

    // `stop` takes what is still waiting, then closes the device.
    var clip = (try recorder.stop()).?;
    defer clip.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(i16, &.{ 1, -16384, 3, 4 }, clip.samples);
    try std.testing.expect(!stream.open);
    try std.testing.expectEqual(AudioRecorderStatus.idle, recorder.status);
    try std.testing.expectEqual(@as(?mod.AudioClip, null), try recorder.stop());
}

test "audio recorder: pauses at its limit, and fails without a device" {
    mod.TestAudioDevices.install();
    defer mod.TestAudioDevices.uninstall();
    var recorder = AudioRecorder.init(std.testing.allocator);
    defer recorder.deinit();
    recorder.sample_rate = 4;
    recorder.limit_seconds = 1;

    try std.testing.expect(recorder.record());
    mod.TestAudioDevices.capture(&.{ 1, 2, 3, 4, 5, 6 });
    recorder.update();
    try std.testing.expectEqualSlices(i16, &.{ 1, 2, 3, 4 }, recorder.recorded());
    try std.testing.expect(recorder.reached_limit);
    try std.testing.expectEqual(AudioRecorderStatus.paused, recorder.status);
    try std.testing.expectEqual(@as(f32, 0), recorder.level);
    try std.testing.expect(!recorder.record());
    try std.testing.expectApproxEqAbs(@as(f64, 1), recorder.currentTime(), 1e-9);

    // Stopping keeps the take and ends the limit with it.
    var clip = (try recorder.stop()).?;
    clip.deinit(std.testing.allocator);
    try std.testing.expect(!recorder.reached_limit);
    try std.testing.expect(recorder.record());

    // A cancelled take is dropped; a device that will not open fails the next.
    recorder.cancel();
    try std.testing.expectEqual(@as(usize, 0), recorder.recorded().len);
    mod.TestAudioDevices.refuse_open = true;
    try std.testing.expect(!recorder.record());
    try std.testing.expect(recorder.failed);
    try std.testing.expectEqual(AudioRecorderStatus.idle, recorder.status);

    mod.TestAudioDevices.uninstall();
    mod.TestAudioDevices.refuse_open = false;
    try std.testing.expect(!recorder.record());
}

test "audio recorder: the take grows a step at a time, never past its limit" {
    mod.TestAudioDevices.install();
    defer mod.TestAudioDevices.uninstall();
    var recorder = AudioRecorder.init(std.testing.allocator);
    defer recorder.deinit();
    recorder.sample_rate = 10;
    recorder.limit_seconds = 100;
    try std.testing.expect(recorder.record());
    mod.TestAudioDevices.capture(&.{ 1, 2, 3 });
    recorder.update();
    // One step: 30 seconds at 10 a second, not a doubling of 3.
    try std.testing.expectEqual(@as(usize, AudioRecorder.growth_seconds * 10), recorder.samples.capacity);
    var many: [400]i16 = @splat(1);
    mod.TestAudioDevices.capture(&many);
    recorder.update();
    // A read past a step grows by what it needs; the limit caps the room.
    try std.testing.expectEqual(@as(usize, 403), recorder.samples.items.len);
    try std.testing.expect(recorder.samples.capacity <= 1000);
    mod.TestAudioDevices.capture(&many);
    mod.TestAudioDevices.capture(&many);
    recorder.update();
    try std.testing.expectEqual(@as(usize, 1000), recorder.samples.capacity);
    try std.testing.expect(recorder.reached_limit);
}

test "audio recorder: asks for frames while it records" {
    mod.TestAudioDevices.install();
    defer mod.TestAudioDevices.uninstall();
    const clock = mod.FrameClock.shared();
    clock.setTime(1000);
    defer clock.setTime(0);
    _ = clock.frameDueIn(std.math.maxInt(u64));
    var recorder = AudioRecorder.init(std.testing.allocator);
    defer recorder.deinit();
    recorder.update();
    try std.testing.expectEqual(@as(?u64, null), clock.frameDueIn(1000));
    _ = recorder.record();
    recorder.update();
    try std.testing.expectEqual(@as(?u64, AudioRecorder.refresh_interval_ms), clock.frameDueIn(1000));
}

test "audio recorder: the software gain sets the stream's gain, as a take starts and while it records" {
    mod.TestAudioDevices.install();
    defer mod.TestAudioDevices.uninstall();
    var recorder = AudioRecorder.init(std.testing.allocator);
    defer recorder.deinit();
    const binding = recorder.gainBinding();
    binding.set(1.5);
    try std.testing.expect(recorder.record());
    const stream = mod.TestAudioDevices.stream(.recording);
    try std.testing.expectEqual(@as(f32, 1.5), stream.gain);
    binding.set(5);
    try std.testing.expectEqual(AudioRecorder.max_gain, stream.gain);
    recorder.setGain(std.math.inf(f32));
    try std.testing.expectEqual(AudioRecorder.max_gain, binding.get());
    binding.set(-1);
    try std.testing.expectEqual(@as(f32, 0), stream.gain);
    recorder.cancel();
    try std.testing.expectEqual(@as(f32, 0), recorder.gain);
}
