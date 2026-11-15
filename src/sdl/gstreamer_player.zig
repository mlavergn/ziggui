//! The Linux `PlayerBackend`: not implemented yet. Its players report
//! `.failed` with `unsupported`, and `VideoPlayer` draws its placeholder.
//!
//! The intended engine is GStreamer's `playbin` (loaded at run time, as SDL
//! loads its own Linux libraries, so nothing links it), which plays HLS, MP4
//! and HEVC with the system's codecs, and reports what `PlayerObservation`
//! needs (state changes, `query_position`/`query_duration`, buffering
//! messages, errors on the bus; `n-audio`/`n-text` and `current-audio`/
//! `current-text` for the tracks). For the picture: on Wayland a video sink
//! on a subsurface placed below ziggui's surface, which already composites
//! with alpha, matching the macOS design; on X11, where a child window cannot
//! show through its parent, the sink rendering into a texture ziggui draws
//! (an `appsink`), which needs an external texture draw command. Either way
//! the `PlayerBackend` and `VideoRegion` contract stays as it is.

const std = @import("std");
const log = std.log.scoped(.ziggui_gstreamer_player);
const views = @import("views");
const sdl_c = @import("sdl_c");

/// The Linux player behind every `Player`: a stub for now.
pub const GstreamerPlayer = struct {
    const Self = @This();

    /// The backend `Player`s are made with: it refuses, saying why.
    pub const backend: views.PlayerBackend = .{
        .unsupported = "Video playback is not implemented on Linux yet.",
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

test "gstreamer player: a player on it fails, saying why, and makes nothing" {
    views.Player.setBackend(&GstreamerPlayer.backend);
    defer views.Player.setBackend(null);
    var player = views.Player.init(std.testing.allocator);
    defer player.deinit();
    try player.replaceCurrentItem("https://example.com/master.m3u8");
    const observation = player.observe();
    try std.testing.expectEqual(views.PlayerStatus.failed, observation.status);
    try std.testing.expect(std.mem.find(u8, observation.failure, "Linux") != null);
    try std.testing.expect(player.nativeHandle() == null);
}
