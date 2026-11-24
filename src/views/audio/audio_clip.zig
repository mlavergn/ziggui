//! A recorded sound held in memory: mono 16-bit samples at one rate, what
//! `AudioRecorder` records and `AudioClipPlayer` plays. `encodeWav` and
//! `decodeWav` turn it into a WAV file's bytes and back, so an app keeps
//! its clips wherever it keeps files (ziggui keeps none).

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_clip);

/// What `AudioClip.decodeWav` and `AudioClip.encodeWav` refuse, and
/// allocation failure.
pub const AudioClipError = error{
    /// Not a RIFF WAVE file, or one with no `fmt ` or `data` chunk.
    NotWave,
    /// A WAVE file whose samples are not 16- or 32-bit integers or
    /// 32-bit floats, or whose rate or channel count is out of range; or a
    /// clip to encode whose rate is 0 or past `AudioClip.max_sample_rate`.
    UnsupportedWave,
    /// A clip too long for a WAV file: its samples past 4 GiB.
    ClipTooLong,
} || std.mem.Allocator.Error;

/// How a WAV file stores a sample.
const WaveEncoding = enum {
    const Self = @This();

    /// A signed little-endian integer.
    integer,
    /// An IEEE 754 single.
    float,
};

/// A WAV file's `fmt ` chunk, as `AudioClip.decodeWav` reads it.
const WaveFormat = struct {
    const Self = @This();

    /// How each sample is stored.
    encoding: WaveEncoding,

    /// Channels a frame.
    channels: u16,

    /// Samples a second.
    sample_rate: u32,

    /// Bytes a sample: 2 or 4.
    sample_bytes: u16,

    /// Reads a `fmt ` chunk.
    ///
    /// - `body`: the chunk's bytes.
    /// - Returns: the format; `error.NotWave` for a chunk too short,
    ///   `error.UnsupportedWave` for samples `decode` cannot read.
    fn parse(body: []const u8) AudioClipError!Self {
        if (body.len < 16) return error.NotWave;
        var tag = std.mem.readInt(u16, body[0..2], .little);
        const channels = std.mem.readInt(u16, body[2..4], .little);
        const sample_rate = std.mem.readInt(u32, body[4..8], .little);
        const bits = std.mem.readInt(u16, body[14..16], .little);
        // WAVE_FORMAT_EXTENSIBLE names the real format in its subformat GUID's first two bytes.
        if (tag == 0xFFFE) {
            if (body.len < 26) return error.NotWave;
            tag = std.mem.readInt(u16, body[24..26], .little);
        }
        const encoding: WaveEncoding = switch (tag) {
            1 => .integer,
            3 => .float,
            else => return error.UnsupportedWave,
        };
        if (channels == 0 or sample_rate == 0 or sample_rate > AudioClip.max_sample_rate) return error.UnsupportedWave;
        const supported = switch (encoding) {
            .integer => bits == 16 or bits == 32,
            .float => bits == 32,
        };
        if (!supported) return error.UnsupportedWave;
        const self = Self{ .encoding = encoding, .channels = channels, .sample_rate = sample_rate, .sample_bytes = bits / 8 };
        return self;
    }

    /// The bytes a frame takes: a sample for each channel.
    ///
    /// - `self`: the format.
    /// - Returns: the bytes, never 0.
    fn frameBytes(self: *const Self) usize {
        return @as(usize, self.channels) * self.sample_bytes;
    }

    /// Reads the `data` chunk's whole frames, each mixed down to one 16-bit sample.
    ///
    /// - `self`: the format.
    /// - `data`: the chunk's bytes.
    /// - `allocator`: owns the samples.
    /// - Returns: the clip; propagates allocation failure.
    fn decode(self: *const Self, allocator: std.mem.Allocator, data: []const u8) std.mem.Allocator.Error!AudioClip {
        const frame_bytes = self.frameBytes();
        const frames = data.len / frame_bytes;
        const samples = try allocator.alloc(i16, frames);
        for (samples, 0..) |*sample, frame| {
            var sum: f64 = 0;
            for (0..self.channels) |channel| {
                const at = frame * frame_bytes + channel * self.sample_bytes;
                sum += self.sampleAt(data[at..][0..self.sample_bytes]);
            }
            // On the 16-bit scale, so 16-bit samples read back exactly.
            const mixed = @round(sum / @as(f64, @floatFromInt(self.channels)) * 32768);
            sample.* = @intFromFloat(std.math.clamp(mixed, -32768, 32767));
        }
        const clip = AudioClip{ .samples = samples, .sample_rate = self.sample_rate };
        return clip;
    }

    /// One stored sample as a level.
    ///
    /// - `self`: the format.
    /// - `bytes`: the sample's bytes, `sample_bytes` of them.
    /// - Returns: -1 to 1 (a float past that is clamped by `decode`; NaN is 0).
    fn sampleAt(self: *const Self, bytes: []const u8) f64 {
        return switch (self.encoding) {
            .integer => if (self.sample_bytes == 2)
                @as(f64, @floatFromInt(std.mem.readInt(i16, bytes[0..2], .little))) / 32768.0
            else
                @as(f64, @floatFromInt(std.mem.readInt(i32, bytes[0..4], .little))) / 2147483648.0,
            .float => blk: {
                const value: f32 = @bitCast(std.mem.readInt(u32, bytes[0..4], .little));
                break :blk if (std.math.isNan(value)) 0 else value;
            },
        };
    }
};

/// Where a WAV file's format and samples are: its `fmt ` chunk read, and
/// its `data` chunk's place, as `decodeWav` and `inspectWav` find them.
const WaveLayout = struct {
    const Self = @This();

    /// The `fmt ` chunk.
    format: WaveFormat,

    /// Where the `data` chunk's samples start, in the file.
    data_start: usize,

    /// The `data` chunk's bytes the file holds: its stated length, cut to
    /// the file's end for a file cut short.
    data_length: usize,

    /// Walks a WAV file's chunks to its first `fmt ` and `data` chunks.
    /// The bytes are untrusted: every length is bounded by the file.
    ///
    /// - `bytes`: the file, or its start (a `fmt ` chunk must lie within it).
    /// - `file_length`: the whole file's length, `bytes.len` or more.
    /// - Returns: the layout; `error.NotWave` for a file that is not RIFF
    ///   WAVE or lacks either chunk within `bytes`, `error.UnsupportedWave`
    ///   for samples `WaveFormat` cannot read.
    fn find(bytes: []const u8, file_length: usize) AudioClipError!Self {
        if (bytes.len < 12 or !std.mem.eql(u8, bytes[0..4], "RIFF") or !std.mem.eql(u8, bytes[8..12], "WAVE")) return error.NotWave;
        var format: ?WaveFormat = null;
        var data_start: ?usize = null;
        var data_length: usize = 0;
        var at: usize = 12;
        while (at + 8 <= bytes.len) {
            const id = bytes[at..][0..4];
            const length = std.mem.readInt(u32, bytes[at + 4 ..][0..4], .little);
            const start = at + 8;
            if (std.mem.eql(u8, id, "fmt ")) {
                format = try WaveFormat.parse(bytes[start..@min(bytes.len, start +| length)]);
            } else if (std.mem.eql(u8, id, "data")) {
                data_start = start;
                data_length = @min(length, file_length -| start);
            }
            if (format != null and data_start != null) break;
            // Chunks are padded to an even length.
            at = start +| length +| (length & 1);
        }
        const self = Self{
            .format = format orelse return error.NotWave,
            .data_start = data_start orelse return error.NotWave,
            .data_length = data_length,
        };
        return self;
    }

    /// The whole frames the `data` chunk holds.
    ///
    /// - `self`: the layout.
    /// - Returns: the frames.
    fn frames(self: *const Self) usize {
        return self.data_length / self.format.frameBytes();
    }
};

/// What a WAV file's header says of its sound, without reading its samples
/// (`AudioClip.inspectWav`): enough to list a clip by its length.
pub const AudioClipInfo = struct {
    const Self = @This();

    /// The whole frames the file holds, each one sample of the clip.
    frames: usize,

    /// Samples a second.
    sample_rate: u32,

    /// How long the clip plays.
    ///
    /// - `self`: the info.
    /// - Returns: its length in seconds.
    pub fn duration(self: *const Self) f64 {
        return AudioClip.secondsOf(self.frames, self.sample_rate);
    }
};

/// A mono 16-bit sound.
pub const AudioClip = struct {
    const Self = @This();

    /// The rate `AudioRecorder` records at, in samples a second.
    pub const default_sample_rate: u32 = 48_000;

    /// The highest rate `decodeWav` accepts, in samples a second.
    pub const max_sample_rate: u32 = 384_000;

    /// The length of the header `encodeWav` writes: RIFF, `fmt ` and the
    /// `data` chunk's head.
    pub const wav_header_length = 44;

    /// How much of a file's start `inspectWav` is handed: room for the
    /// header and the small chunks (`LIST`, `fact`) some writers put before
    /// the samples.
    pub const header_read_length = 4096;

    /// The samples, owned by the allocator the clip was made with.
    samples: []i16 = &.{},

    /// Samples a second.
    sample_rate: u32 = default_sample_rate,

    /// Frees the samples.
    ///
    /// - `self`: the clip.
    /// - `allocator`: the allocator the samples came from.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.samples);
        self.* = .{ .sample_rate = self.sample_rate };
    }

    /// How long the clip plays.
    ///
    /// - `self`: the clip.
    /// - Returns: its length in seconds; 0 for a clip with no rate.
    pub fn duration(self: *const Self) f64 {
        return Self.secondsOf(self.samples.len, self.sample_rate);
    }

    /// A count of samples as seconds.
    ///
    /// - `count`: the samples.
    /// - `sample_rate`: samples a second.
    /// - Returns: the seconds; 0 at a rate of 0.
    pub fn secondsOf(count: usize, sample_rate: u32) f64 {
        if (sample_rate == 0) return 0;
        return @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(sample_rate));
    }

    /// The loudest sample's level, for a meter.
    ///
    /// - `samples`: the samples.
    /// - Returns: 0 silent to 1 at full scale; 0 for none.
    pub fn peakLevel(samples: []const i16) f32 {
        var peak: u16 = 0;
        for (samples) |sample| peak = @max(peak, @abs(sample));
        return @min(1, @as(f32, @floatFromInt(peak)) / 32767.0);
    }

    /// The clip as a WAV file: 16-bit PCM, one channel, little-endian.
    ///
    /// - `self`: the clip.
    /// - `allocator`: owns the bytes.
    /// - Returns: the file's bytes; `error.ClipTooLong` for samples a WAV's
    ///   32-bit sizes cannot count, `error.UnsupportedWave` for a rate of 0
    ///   or past `max_sample_rate`; propagates allocation failure.
    pub fn encodeWav(self: *const Self, allocator: std.mem.Allocator) AudioClipError![]u8 {
        if (self.sample_rate == 0 or self.sample_rate > max_sample_rate) return error.UnsupportedWave;
        // The RIFF size counts 36 bytes before the data, in 32 bits.
        if (self.samples.len > (std.math.maxInt(u32) - 36) / 2) return error.ClipTooLong;
        const data_length: u32 = @intCast(self.samples.len * 2);
        const bytes = try allocator.alloc(u8, wav_header_length + data_length);
        @memcpy(bytes[0..4], "RIFF");
        std.mem.writeInt(u32, bytes[4..8], 36 + data_length, .little);
        @memcpy(bytes[8..12], "WAVE");
        @memcpy(bytes[12..16], "fmt ");
        std.mem.writeInt(u32, bytes[16..20], 16, .little);
        std.mem.writeInt(u16, bytes[20..22], 1, .little);
        std.mem.writeInt(u16, bytes[22..24], 1, .little);
        std.mem.writeInt(u32, bytes[24..28], self.sample_rate, .little);
        std.mem.writeInt(u32, bytes[28..32], self.sample_rate * 2, .little);
        std.mem.writeInt(u16, bytes[32..34], 2, .little);
        std.mem.writeInt(u16, bytes[34..36], 16, .little);
        @memcpy(bytes[36..40], "data");
        std.mem.writeInt(u32, bytes[40..44], data_length, .little);
        for (self.samples, 0..) |sample, index| {
            const at = wav_header_length + index * 2;
            std.mem.writeInt(i16, bytes[at..][0..2], sample, .little);
        }
        return bytes;
    }

    /// Reads a WAV file's samples: 16- or 32-bit integer PCM or 32-bit float,
    /// any number of channels (mixed down to one). The bytes are untrusted:
    /// every chunk is bounds-checked, and a `data` chunk cut short keeps the
    /// whole frames it holds.
    ///
    /// - `allocator`: owns the clip's samples.
    /// - `bytes`: the file.
    /// - Returns: the clip; `error.NotWave` or `error.UnsupportedWave` for a
    ///   file it cannot read; propagates allocation failure.
    pub fn decodeWav(allocator: std.mem.Allocator, bytes: []const u8) AudioClipError!Self {
        const layout = try WaveLayout.find(bytes, bytes.len);
        return layout.format.decode(allocator, bytes[layout.data_start..][0..layout.data_length]);
    }

    /// Reads a WAV file's length and rate from its start alone, as
    /// `decodeWav` would read the whole file, so a list of clips costs no
    /// samples in memory.
    ///
    /// - `header`: the file's first bytes (`header_read_length` of them, or
    ///   the whole file when shorter).
    /// - `file_length`: the whole file's length.
    /// - Returns: the frames and rate; `error.NotWave` for a file that is
    ///   not RIFF WAVE or whose `fmt ` or `data` chunk starts past `header`,
    ///   `error.UnsupportedWave` for samples `decodeWav` cannot read.
    pub fn inspectWav(header: []const u8, file_length: usize) AudioClipError!AudioClipInfo {
        const layout = try WaveLayout.find(header, @max(file_length, header.len));
        const info = AudioClipInfo{ .frames = layout.frames(), .sample_rate = layout.format.sample_rate };
        return info;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "audio clip: a WAV round-trips its samples and rate" {
    const allocator = std.testing.allocator;
    var samples = [_]i16{ 0, 1, -1, 32767, -32768, 1234 };
    const clip = AudioClip{ .samples = &samples, .sample_rate = 22_050 };
    const bytes = try clip.encodeWav(allocator);
    defer allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, AudioClip.wav_header_length + samples.len * 2), bytes.len);
    var back = try AudioClip.decodeWav(allocator, bytes);
    defer back.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 22_050), back.sample_rate);
    try std.testing.expectEqualSlices(i16, &samples, back.samples);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0 / 22_050.0), back.duration(), 1e-12);
}

test "audio clip: stereo floats mix down, and other chunks are skipped" {
    const allocator = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);
    try bytes.appendSlice(allocator, "RIFF\x00\x00\x00\x00WAVE");
    // An odd-length chunk before `fmt `, padded.
    try bytes.appendSlice(allocator, "LIST\x03\x00\x00\x00abc\x00");
    try bytes.appendSlice(allocator, "fmt \x10\x00\x00\x00");
    var format: [16]u8 = undefined;
    std.mem.writeInt(u16, format[0..2], 3, .little);
    std.mem.writeInt(u16, format[2..4], 2, .little);
    std.mem.writeInt(u32, format[4..8], 44_100, .little);
    std.mem.writeInt(u32, format[8..12], 44_100 * 8, .little);
    std.mem.writeInt(u16, format[12..14], 8, .little);
    std.mem.writeInt(u16, format[14..16], 32, .little);
    try bytes.appendSlice(allocator, &format);
    try bytes.appendSlice(allocator, "data\x18\x00\x00\x00");
    for ([_]f32{ 1, 0, -0.5, -0.5, 4, 4 }) |value| {
        var sample: [4]u8 = undefined;
        std.mem.writeInt(u32, &sample, @bitCast(value), .little);
        try bytes.appendSlice(allocator, &sample);
    }
    var clip = try AudioClip.decodeWav(allocator, bytes.items);
    defer clip.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 44_100), clip.sample_rate);
    try std.testing.expectEqualSlices(i16, &.{ 16384, -16384, 32767 }, clip.samples);
}

test "audio clip: a cut-short data chunk keeps its whole frames, and bad files are refused" {
    const allocator = std.testing.allocator;
    var samples = [_]i16{ 7, 8, 9 };
    const clip = AudioClip{ .samples = &samples };
    const bytes = try clip.encodeWav(allocator);
    defer allocator.free(bytes);
    var cut = try AudioClip.decodeWav(allocator, bytes[0 .. bytes.len - 1]);
    defer cut.deinit(allocator);
    try std.testing.expectEqualSlices(i16, &.{ 7, 8 }, cut.samples);

    try std.testing.expectError(error.NotWave, AudioClip.decodeWav(allocator, "RIFF"));
    try std.testing.expectError(error.NotWave, AudioClip.decodeWav(allocator, bytes[0..36]));
    var eight_bit = try allocator.dupe(u8, bytes);
    defer allocator.free(eight_bit);
    std.mem.writeInt(u16, eight_bit[34..36], 8, .little);
    try std.testing.expectError(error.UnsupportedWave, AudioClip.decodeWav(allocator, eight_bit));
}

test "audio clip: a header alone gives the length decodeWav reads" {
    const allocator = std.testing.allocator;
    const samples = try allocator.alloc(i16, 5000);
    defer allocator.free(samples);
    @memset(samples, 9);
    const clip = AudioClip{ .samples = samples, .sample_rate = 1000 };
    const bytes = try clip.encodeWav(allocator);
    defer allocator.free(bytes);
    const info = try AudioClip.inspectWav(bytes[0..64], bytes.len);
    try std.testing.expectEqual(@as(usize, 5000), info.frames);
    try std.testing.expectApproxEqAbs(@as(f64, 5), info.duration(), 1e-9);
    // A file cut short counts its whole frames, as `decodeWav` keeps them.
    const cut_length = bytes.len - 3;
    try std.testing.expectEqual(@as(usize, 4998), (try AudioClip.inspectWav(bytes[0..64], cut_length)).frames);
    var cut = try AudioClip.decodeWav(allocator, bytes[0..cut_length]);
    defer cut.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 4998), cut.samples.len);
    // A header with no `data` chunk in reach is not a WAV it can read.
    try std.testing.expectError(error.NotWave, AudioClip.inspectWav(bytes[0..40], bytes.len));
}

test "audio clip: a rate or length a WAV cannot hold is refused, not trapped" {
    var samples = [_]i16{1};
    const no_rate = AudioClip{ .samples = &samples, .sample_rate = 0 };
    try std.testing.expectError(error.UnsupportedWave, no_rate.encodeWav(std.testing.allocator));
    const too_fast = AudioClip{ .samples = &samples, .sample_rate = std.math.maxInt(u32) };
    try std.testing.expectError(error.UnsupportedWave, too_fast.encodeWav(std.testing.allocator));
    // A length past what a WAV counts, never read: refused before any allocation.
    const too_long = AudioClip{ .samples = @as([*]i16, &samples)[0 .. std.math.maxInt(u32) / 2] };
    try std.testing.expectError(error.ClipTooLong, too_long.encodeWav(std.testing.allocator));
}

test "audio clip: the peak level is the loudest sample's" {
    try std.testing.expectEqual(@as(f32, 0), AudioClip.peakLevel(&.{}));
    try std.testing.expectEqual(@as(f32, 1), AudioClip.peakLevel(&.{ 3, -32768 }));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), AudioClip.peakLevel(&.{ 100, -16384 }), 0.001);
}
