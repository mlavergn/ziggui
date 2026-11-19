//! The audio outputs a `Player` can route its sound to: the devices the
//! installed `AudioOutputBackend` reports. With none installed (headless, in
//! tests, or an OS whose backend is not written yet) there are none, and an
//! app leaves its output menu out.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_outputs);
const mod = @import("module.zig");

/// The system's audio outputs, through the installed backend.
pub const AudioOutputs = struct {
    const Self = @This();

    /// The backend `list` asks, installed by the SDL runtime as its loop
    /// starts; null headless and in tests, unless a test installs one.
    var installed_backend: ?*const mod.AudioOutputBackend = null;

    /// Installs the backend outputs are listed with; the SDL runtime calls
    /// this as its loop starts and ends.
    ///
    /// - `backend`: the platform's listing; null for none.
    pub fn setBackend(backend: ?*const mod.AudioOutputBackend) void {
        installed_backend = backend;
    }

    /// Whether this platform can list outputs (and so route a player's sound).
    ///
    /// - Returns: true with a backend installed.
    pub fn available() bool {
        return installed_backend != null;
    }

    /// Lists the outputs now, probing the system: call it when a menu opens.
    ///
    /// - `allocator`: owns the list and its strings: free them with `free`,
    ///   or with an arena all at once.
    /// - Returns: the outputs, none without a backend; propagates allocation failure.
    pub fn list(allocator: std.mem.Allocator) std.mem.Allocator.Error![]mod.AudioOutput {
        const backend = installed_backend orelse return &.{};
        return backend.list(allocator);
    }

    /// Frees a list `list` made, and its strings.
    ///
    /// - `allocator`: the allocator `list` was given.
    /// - `outputs`: the list.
    pub fn free(allocator: std.mem.Allocator, outputs: []const mod.AudioOutput) void {
        for (outputs) |output| {
            allocator.free(output.id);
            allocator.free(output.name);
        }
        allocator.free(outputs);
    }

    /// The output among `outputs` whose id is `id`, for a menu's tick.
    ///
    /// - `outputs`: what `list` returned.
    /// - `id`: the id asked for, or null for the system default.
    /// - Returns: its index, or null for the system default or an output gone.
    pub fn indexOf(outputs: []const mod.AudioOutput, id: ?[]const u8) ?usize {
        const wanted = id orelse return null;
        for (outputs, 0..) |output, index| {
            if (std.mem.eql(u8, output.id, wanted)) return index;
        }
        return null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// A backend that reports two devices, for the tests.
const FakeOutputs = struct {
    const Self = @This();

    /// The fake's listing.
    const backend: mod.AudioOutputBackend = .{ .list = Self.list };

    /// Lists a speaker (the default) and headphones, each string owned, as
    /// a backend's are.
    ///
    /// - `allocator`: owns the list and its strings.
    /// - Returns: the two outputs; propagates allocation failure.
    fn list(allocator: std.mem.Allocator) std.mem.Allocator.Error![]mod.AudioOutput {
        const outputs = try allocator.alloc(mod.AudioOutput, 2);
        // Empty until copied: freeing an empty string frees nothing.
        @memset(outputs, .{ .id = "", .name = "" });
        errdefer AudioOutputs.free(allocator, outputs);
        outputs[0].id = try allocator.dupe(u8, "speakers");
        outputs[0].name = try allocator.dupe(u8, "Speakers");
        outputs[0].is_default = true;
        outputs[1].id = try allocator.dupe(u8, "headphones");
        outputs[1].name = try allocator.dupe(u8, "Headphones");
        return outputs;
    }
};

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "audio outputs list nothing without a backend, and the installed one's devices with it" {
    AudioOutputs.setBackend(null);
    try std.testing.expect(!AudioOutputs.available());
    try std.testing.expectEqual(@as(usize, 0), (try AudioOutputs.list(std.testing.allocator)).len);

    AudioOutputs.setBackend(&FakeOutputs.backend);
    defer AudioOutputs.setBackend(null);
    try std.testing.expect(AudioOutputs.available());
    const outputs = try AudioOutputs.list(std.testing.allocator);
    defer AudioOutputs.free(std.testing.allocator, outputs);
    try std.testing.expectEqual(@as(usize, 2), outputs.len);
    try std.testing.expectEqual(@as(?usize, 1), AudioOutputs.indexOf(outputs, "headphones"));
    try std.testing.expectEqual(@as(?usize, null), AudioOutputs.indexOf(outputs, "unplugged"));
    try std.testing.expectEqual(@as(?usize, null), AudioOutputs.indexOf(outputs, null));
}
