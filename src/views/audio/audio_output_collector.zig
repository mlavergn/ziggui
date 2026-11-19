//! Builds the list an `AudioOutputBackend.list` returns, as every platform's
//! backend does: each output's strings copied, an id already added skipped,
//! and nothing left allocated when an allocation fails.

const std = @import("std");
const log = std.log.scoped(.ziggui_audio_output_collector);
const mod = @import("module.zig");

/// The outputs a backend has found so far.
pub const AudioOutputCollector = struct {
    const Self = @This();

    /// Owns the list and its strings.
    allocator: std.mem.Allocator,
    /// What was added, each string owned.
    outputs: std.ArrayList(mod.AudioOutput) = .empty,

    /// An empty collector.
    ///
    /// - `allocator`: owns the list and its strings (`AudioOutputs.free`).
    /// - Returns: the collector.
    pub fn init(allocator: std.mem.Allocator) Self {
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Frees what was collected and not handed over by `finish`; defer it.
    ///
    /// - `self`: the collector.
    pub fn deinit(self: *Self) void {
        for (self.outputs.items) |output| {
            self.allocator.free(output.id);
            self.allocator.free(output.name);
        }
        self.outputs.deinit(self.allocator);
    }

    /// Adds an output, copying its strings; an id already added is skipped
    /// (one device that two of the platform's providers both report).
    ///
    /// - `self`: the collector.
    /// - `id`: the output's id (`AudioOutput.id`).
    /// - `name`: its name as the system shows it.
    /// - `is_default`: it is the system's default output now.
    /// - Returns: nothing; propagates allocation failure.
    pub fn add(self: *Self, id: []const u8, name: []const u8, is_default: bool) std.mem.Allocator.Error!void {
        if (mod.AudioOutputs.indexOf(self.outputs.items, id) != null) return;
        const id_copy = try self.allocator.dupe(u8, id);
        errdefer self.allocator.free(id_copy);
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        try self.outputs.append(self.allocator, .{ .id = id_copy, .name = name_copy, .is_default = is_default });
    }

    /// Hands the list over, leaving the collector empty.
    ///
    /// - `self`: the collector.
    /// - Returns: the outputs, owned by the caller (`AudioOutputs.free`);
    ///   propagates allocation failure, the outputs still the collector's.
    pub fn finish(self: *Self) std.mem.Allocator.Error![]mod.AudioOutput {
        return self.outputs.toOwnedSlice(self.allocator);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// Collects two outputs, one of them twice, and frees the list, for the
/// allocation-failure test.
const CollectProbe = struct {
    const Self = @This();

    /// Collects and frees.
    ///
    /// - `allocator`: the allocator the list is made with.
    /// - Returns: nothing; propagates allocation failure and a failed check.
    fn collectAndFree(allocator: std.mem.Allocator) !void {
        var collector = AudioOutputCollector.init(allocator);
        defer collector.deinit();
        try collector.add("speakers", "Speakers", true);
        try collector.add("headphones", "Headphones", false);
        try collector.add("speakers", "Speakers again", false);
        const outputs = try collector.finish();
        defer mod.AudioOutputs.free(allocator, outputs);
        try std.testing.expectEqual(@as(usize, 2), outputs.len);
        try std.testing.expectEqualStrings("Speakers", outputs[0].name);
        try std.testing.expect(outputs[0].is_default and !outputs[1].is_default);
    }
};

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "an audio output collector keeps each id once, and nothing when an allocation fails" {
    try CollectProbe.collectAndFree(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, CollectProbe.collectAndFree, .{});
}
