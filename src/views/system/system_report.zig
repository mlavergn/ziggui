//! What `SystemInfo.report` found: how the window draws, the media player
//! behind `Player`, and the audio outputs, for an app's "System Info" sheet
//! (`SystemInfoView`) and for a bug report (`text`).

const std = @import("std");
const log = std.log.scoped(.ziggui_system_report);
const mod = @import("module.zig");

/// How the window's frames are drawn.
pub const GraphicsRenderer = enum {
    const Self = @This();

    /// Not known yet: no window has opened (headless, tests).
    none,
    /// SDL_GPU (Metal, Direct3D 12, Vulkan).
    gpu,
    /// ziggui's software rasterizer, presented through an SDL renderer.
    software,

    /// The renderer as a sheet names it.
    ///
    /// - `self`: the renderer.
    /// - Returns: the label, static.
    pub fn label(self: *const Self) []const u8 {
        return switch (self.*) {
            .none => "No window",
            .gpu => "GPU",
            .software => "Software",
        };
    }
};

/// One reading of the system, its strings in the allocator `report` was
/// given: freed with `deinit`, or with an arena all at once.
pub const SystemReport = struct {
    const Self = @This();

    /// What follows the id of an output `outputName` does not find.
    pub const not_connected = " (not connected)";

    /// How the window draws.
    renderer: GraphicsRenderer = .none,
    /// The GPU backend's driver ("metal", "direct3d12", "vulkan"), or the SDL
    /// renderer presenting the software frames ("direct3d11", "opengl"); empty when unknown.
    graphics_driver: []const u8 = "",
    /// The GPU's name as its driver reports it; empty when unknown.
    gpu: []const u8 = "",
    /// The GPU driver's own version; empty when unknown.
    gpu_driver_version: []const u8 = "",
    /// The media player behind `Player` ("AVFoundation", "Media Foundation",
    /// "GStreamer"); empty with none installed.
    player: []const u8 = "",
    /// That player's version, where it reports one (GStreamer's); empty otherwise.
    player_version: []const u8 = "",
    /// The audio outputs (`AudioOutputs.list`); none where the platform lists none.
    audio_outputs: []const mod.AudioOutput = &.{},

    /// Frees the strings of a report `SystemInfo.report` made.
    ///
    /// - `self`: the report.
    /// - `allocator`: the allocator `report` was given.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        // An empty field may be a literal: freeing an empty slice frees nothing.
        allocator.free(self.graphics_driver);
        allocator.free(self.gpu);
        allocator.free(self.gpu_driver_version);
        allocator.free(self.player);
        allocator.free(self.player_version);
        mod.AudioOutputs.free(allocator, self.audio_outputs);
        self.* = .{};
    }

    /// The report as plain lines, for the clipboard or a bug report.
    ///
    /// - `self`: the report.
    /// - `allocator`: owns the text.
    /// - `audio_output`: the output a player plays through (its id), or null for the system default.
    /// - Returns: the text; propagates allocation failure.
    pub fn text(self: *const Self, allocator: std.mem.Allocator, audio_output: ?[]const u8) std.mem.Allocator.Error![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        self.write(&out.writer, audio_output) catch return error.OutOfMemory;
        return out.toOwnedSlice();
    }

    /// The output a player plays through, by name.
    ///
    /// - `self`: the report.
    /// - `audio_output`: the output's id, or null for the system default.
    /// - Returns: its name, or "System default"; null for an output not
    ///   among `audio_outputs` (unplugged since the player was routed to it),
    ///   which a report names by its id and `not_connected`.
    pub fn outputName(self: *const Self, audio_output: ?[]const u8) ?[]const u8 {
        const id = audio_output orelse return "System default";
        const index = mod.AudioOutputs.indexOf(self.audio_outputs, id) orelse return null;
        return self.audio_outputs[index].name;
    }

    /// The player's name as a report shows it.
    ///
    /// - `self`: the report.
    /// - Returns: the player, or "None" with none installed.
    pub fn playerName(self: *const Self) []const u8 {
        return if (self.player.len > 0) self.player else "None";
    }

    /// A value as a report shows it.
    ///
    /// - `value`: the value.
    /// - Returns: the value, or "Unknown" for an empty one.
    pub fn orUnknown(value: []const u8) []const u8 {
        return if (value.len > 0) value else "Unknown";
    }

    /// Writes the report's lines.
    ///
    /// - `self`: the report.
    /// - `writer`: where to.
    /// - `audio_output`: the output a player plays through, or null for the system default.
    /// - Returns: nothing; propagates the writer's failure.
    fn write(self: *const Self, writer: *std.Io.Writer, audio_output: ?[]const u8) std.Io.Writer.Error!void {
        try writer.print("Renderer: {s}\n", .{self.renderer.label()});
        try writer.print("Graphics driver: {s}\n", .{Self.orUnknown(self.graphics_driver)});
        try writer.print("GPU: {s}\n", .{Self.orUnknown(self.gpu)});
        try writer.print("GPU driver version: {s}\n", .{Self.orUnknown(self.gpu_driver_version)});
        try writer.print("Player: {s}\n", .{self.playerName()});
        try writer.print("Player version: {s}\n", .{Self.orUnknown(self.player_version)});
        if (self.outputName(audio_output)) |name| {
            try writer.print("Audio output: {s}\n", .{name});
        } else {
            try writer.print("Audio output: {s}{s}\n", .{ audio_output.?, not_connected });
        }
        for (self.audio_outputs) |output| {
            try writer.print("Audio device: {s}{s}\n", .{ output.name, output.defaultMark() });
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a system report reads as plain lines, the output in use by name" {
    const outputs = [_]mod.AudioOutput{ .{ .id = "spk", .name = "Speakers", .is_default = true }, .{ .id = "hp", .name = "Headphones" } };
    const report: SystemReport = .{ .renderer = .gpu, .graphics_driver = "direct3d12", .gpu = "Radeon", .player = "Media Foundation", .audio_outputs = &outputs };
    const text = try report.text(std.testing.allocator, "hp");
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.find(u8, text, "Renderer: GPU\n") != null);
    try std.testing.expect(std.mem.find(u8, text, "GPU driver version: Unknown\n") != null);
    try std.testing.expect(std.mem.find(u8, text, "Audio output: Headphones\n") != null);
    try std.testing.expect(std.mem.find(u8, text, "Audio device: Speakers (default)\n") != null);
    try std.testing.expectEqualStrings("System default", report.outputName(null).?);
    try std.testing.expect(report.outputName("gone") == null);
    const gone = try report.text(std.testing.allocator, "gone");
    defer std.testing.allocator.free(gone);
    try std.testing.expect(std.mem.find(u8, gone, "Audio output: gone (not connected)\n") != null);
}
