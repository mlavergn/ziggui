//! What the running app can say about the system it draws and plays on:
//! the SDL runtime notes how it draws as the window opens (`noteGraphics`),
//! and `report` adds the media player behind `Player` and the audio outputs.
//! Headless (tests, screenshots) nothing is noted and no backend is
//! installed, so a report says so.

const std = @import("std");
const log = std.log.scoped(.ziggui_system_info);
const mod = @import("module.zig");

/// The system facts the runtime notes, kept in fixed buffers (the strings
/// SDL hands over live only as long as its device).
pub const SystemInfo = struct {
    const Self = @This();

    /// The most bytes kept of each noted string.
    const capacity = 128;

    /// How the window draws, once a window has opened.
    renderer: mod.GraphicsRenderer = .none,
    /// The graphics driver's name.
    driver: [capacity]u8 = undefined,
    /// How many bytes of `driver` are used.
    driver_length: usize = 0,
    /// The GPU's name.
    gpu: [capacity]u8 = undefined,
    /// How many bytes of `gpu` are used.
    gpu_length: usize = 0,
    /// The GPU driver's version.
    driver_version: [capacity]u8 = undefined,
    /// How many bytes of `driver_version` are used.
    driver_version_length: usize = 0,

    /// The one instance.
    var shared_info: Self = .{};

    /// The process's system facts.
    ///
    /// - Returns: the instance.
    pub fn shared() *Self {
        return &shared_info;
    }

    /// Notes how the window draws; the SDL runtime calls it once its renderer
    /// is chosen. Each string is cut on a character to fit.
    ///
    /// - `self`: the facts.
    /// - `renderer`: GPU or software.
    /// - `driver`: the graphics driver's name, or empty.
    /// - `gpu`: the GPU's name, or empty.
    /// - `driver_version`: the GPU driver's version, or empty.
    pub fn noteGraphics(self: *Self, renderer: mod.GraphicsRenderer, driver: []const u8, gpu: []const u8, driver_version: []const u8) void {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        self.renderer = renderer;
        self.driver_length = Self.keep(&self.driver, driver);
        self.gpu_length = Self.keep(&self.gpu, gpu);
        self.driver_version_length = Self.keep(&self.driver_version, driver_version);
    }

    /// Reads the system now: what was noted, the installed player and its
    /// version, and the audio outputs (probed: call it when a sheet opens).
    ///
    /// - `self`: the facts.
    /// - `allocator`: owns the report's strings: free them with
    ///   `SystemReport.deinit`, or with an arena all at once. On failure
    ///   nothing is left allocated.
    /// - Returns: the report; propagates allocation failure.
    pub fn report(self: *const Self, allocator: std.mem.Allocator) std.mem.Allocator.Error!mod.SystemReport {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        var result: mod.SystemReport = .{ .renderer = self.renderer };
        errdefer result.deinit(allocator);
        result.graphics_driver = try allocator.dupe(u8, self.driver[0..self.driver_length]);
        result.gpu = try allocator.dupe(u8, self.gpu[0..self.gpu_length]);
        result.gpu_driver_version = try allocator.dupe(u8, self.driver_version[0..self.driver_version_length]);
        result.player = try allocator.dupe(u8, mod.Player.backendName());
        result.player_version = (try mod.Player.backendVersion(allocator)) orelse "";
        result.audio_outputs = try mod.AudioOutputs.list(allocator);
        return result;
    }

    /// Copies `text` into `buffer`, cut on a character to fit.
    ///
    /// - `buffer`: where to.
    /// - `text`: what.
    /// - Returns: how many bytes were kept.
    fn keep(buffer: *[capacity]u8, text: []const u8) usize {
        const length = mod.DisplayText.fitLength(text, capacity);
        @memcpy(buffer[0..length], text[0..length]);
        return length;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

/// Reads a report with a general-purpose allocator and frees it, for the
/// allocation-failure test.
const ReportProbe = struct {
    const Self = @This();

    /// Reads a report, then frees it.
    ///
    /// - `allocator`: the allocator the report is made with.
    /// - `info`: the facts read.
    /// - Returns: nothing; propagates allocation failure.
    fn readAndFree(allocator: std.mem.Allocator, info: *const SystemInfo) std.mem.Allocator.Error!void {
        var report = try info.report(allocator);
        report.deinit(allocator);
    }
};

test "system info reports what was noted, and nothing before a window opens" {
    var info: SystemInfo = .{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    mod.Player.setBackend(null);
    const empty = try info.report(arena.allocator());
    try std.testing.expectEqual(mod.GraphicsRenderer.none, empty.renderer);
    try std.testing.expectEqualStrings("", empty.player);
    info.noteGraphics(.gpu, "direct3d12", "AMD Radeon R9 M370X", "15.200.1060.0");
    // Freed by `deinit` with any allocator, and nothing left when an allocation fails.
    try std.testing.checkAllAllocationFailures(std.testing.allocator, ReportProbe.readAndFree, .{&info});
    const noted = try info.report(arena.allocator());
    try std.testing.expectEqual(mod.GraphicsRenderer.gpu, noted.renderer);
    try std.testing.expectEqualStrings("direct3d12", noted.graphics_driver);
    try std.testing.expectEqualStrings("AMD Radeon R9 M370X", noted.gpu);
    try std.testing.expectEqualStrings("15.200.1060.0", noted.gpu_driver_version);
}
