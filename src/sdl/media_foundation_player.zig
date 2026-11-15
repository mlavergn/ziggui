//! The Windows `PlayerBackend`: not implemented yet. Its players report
//! `.failed` with `unsupported`, and `VideoPlayer` draws its placeholder.
//!
//! The intended engine is Media Foundation's `IMFMediaEngine` (COM, created
//! through `IMFMediaEngineClassFactory`), which plays HLS, MP4 and HEVC, and
//! reports what `PlayerObservation` needs (`GetReadyState`, `IsPaused`,
//! `GetCurrentTime`, `GetDuration`, `GetBuffered`, `GetError`, the audio
//! and text tracks through `IMFMediaEngineEx`). Showing its picture behind
//! ziggui's surface, as macOS does, needs that surface composited with
//! per-pixel alpha: SDL_GPU's D3D12 swapchain is a plain HWND one, so the
//! choices are a DirectComposition tree (the engine's swapchain visual below
//! a premultiplied-alpha swapchain for ziggui) or the engine rendering into
//! a texture ziggui draws (`TransferVideoFrame`), which needs an external
//! texture draw command. Either way the `PlayerBackend` and `VideoRegion`
//! contract stays as it is.

const std = @import("std");
const log = std.log.scoped(.ziggui_media_foundation_player);
const views = @import("views");
const sdl_c = @import("sdl_c");

/// The Windows player behind every `Player`: a stub for now.
pub const MediaFoundationPlayer = struct {
    const Self = @This();

    /// The backend `Player`s are made with: it refuses, saying why.
    pub const backend: views.PlayerBackend = .{
        .unsupported = "Video playback is not implemented on Windows yet.",
        .create = Self.create,
        .destroy = Self.destroy,
        .load = Self.load,
        .set_rate = Self.setRate,
        .seek = Self.seek,
        .set_volume = Self.setVolume,
        .set_muted = Self.setMuted,
        .observe = Self.observe,
        .tracks = Self.tracks,
        .select_track = Self.selectTrack,
    };

    /// It cannot show pictures behind the window's surface yet.
    pub const presents = false;

    /// Shows nothing yet.
    ///
    /// - `window`: the main window.
    /// - `regions`: the frame's `VideoPlayer` regions.
    pub fn present(window: *sdl_c.SDL_Window, regions: []const views.VideoRegion) void {
        _ = window;
        _ = regions;
    }

    /// Nothing to take out of the window yet.
    pub fn detachAll() void {}

    /// Never called while `unsupported` is set.
    ///
    /// - Returns: null.
    fn create() ?*anyopaque {
        return null;
    }

    /// Never called: no handle exists.
    fn destroy(_: *anyopaque) void {}

    /// Never called: no handle exists.
    fn load(_: *anyopaque, _: ?[:0]const u8) void {}

    /// Never called: no handle exists.
    fn setRate(_: *anyopaque, _: f32) void {}

    /// Never called: no handle exists.
    fn seek(_: *anyopaque, _: f64) void {}

    /// Never called: no handle exists.
    fn setVolume(_: *anyopaque, _: f32) void {}

    /// Never called: no handle exists.
    fn setMuted(_: *anyopaque, _: bool) void {}

    /// Never called: no handle exists.
    ///
    /// - Returns: an empty sample.
    fn observe(_: *anyopaque) views.PlayerObservation {
        return .{};
    }

    /// Never called: no handle exists.
    ///
    /// - Returns: no tracks.
    fn tracks(_: *anyopaque, _: std.mem.Allocator, _: views.PlayerTrackKind) std.mem.Allocator.Error![]views.PlayerTrack {
        return &.{};
    }

    /// Never called: no handle exists.
    fn selectTrack(_: *anyopaque, _: views.PlayerTrackKind, _: ?usize) void {}
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "media foundation player: a player on it fails, saying why, and makes nothing" {
    views.Player.setBackend(&MediaFoundationPlayer.backend);
    defer views.Player.setBackend(null);
    var player = views.Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("https://example.com/master.m3u8");
    player.play();
    const observation = player.observe();
    try std.testing.expectEqual(views.PlayerStatus.failed, observation.status);
    try std.testing.expect(std.mem.find(u8, observation.failure, "Windows") != null);
    try std.testing.expect(player.nativeHandle() == null);
}
