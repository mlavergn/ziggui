//! The platform media player a `Player` drives, as function pointers: the
//! SDL runtime installs its own (AVFoundation on macOS) as its loop starts,
//! so the views stay free of any platform code, and tests install a fake.

const std = @import("std");
const log = std.log.scoped(.ziggui_player_backend);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One picture a platform player hands to ziggui to draw
/// (`PlayerBackend.frame`).
pub const PlayerFrame = struct {
    const Self = @This();

    /// The picture, RGBA8; its pixels belong to the player and stay valid
    /// until the player's next frame is taken.
    image: renderer.Image,
    /// Changes with each new picture, unique in the process, so the renderer
    /// uploads an unchanged one only once.
    generation: u64,
};

/// One platform player's operations. Every function runs on the UI thread
/// and takes the native handle `create` returned.
pub const PlayerBackend = struct {
    const Self = @This();

    /// The platform player's name, for a system report ("AVFoundation",
    /// "Media Foundation", "GStreamer").
    name: []const u8 = "",

    /// The platform player's version, where it reports one (GStreamer's);
    /// null where it has none to report.
    ///
    /// - `allocator`: owns the text.
    /// - Returns: the version, or null when there is none; propagates allocation failure.
    version: ?*const fn (allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]const u8 = null,

    /// Why this platform cannot play video yet, or null when it can. A
    /// backend that sets it never has `create` called: its players report
    /// `.failed` with this text.
    unsupported: ?[]const u8 = null,

    /// Makes a native player with no item, or returns null when the platform
    /// refuses (the player then reports `.failed`).
    ///
    /// - Returns: the native player, or null when the platform refuses.
    create: *const fn () ?*anyopaque,

    /// Stops the player, takes its picture off screen and frees it.
    ///
    /// - `handle`: the native player.
    destroy: *const fn (handle: *anyopaque) void,

    /// Replaces the current item with the media at `url` (a URL, or a local
    /// path), or with none when null. The new item starts paused at its start
    /// unless the player's rate is above 0.
    ///
    /// - `handle`: the native player.
    /// - `url`: the media's URL or local path, or null for no item.
    load: *const fn (handle: *anyopaque, url: ?[:0]const u8) void,

    /// Plays at the given rate (1 normal speed); 0 pauses.
    ///
    /// - `handle`: the native player.
    /// - `rate`: the playback rate; 0 pauses.
    set_rate: *const fn (handle: *anyopaque, rate: f32) void,

    /// Moves the playhead to `seconds` from the item's start.
    ///
    /// - `handle`: the native player.
    /// - `seconds`: the target, from the item's start.
    seek: *const fn (handle: *anyopaque, seconds: f64) void,

    /// Sets the volume, 0 silent to 1 full.
    ///
    /// - `handle`: the native player.
    /// - `volume`: 0 silent to 1 full.
    set_volume: *const fn (handle: *anyopaque, volume: f32) void,

    /// Mutes or unmutes, keeping the volume.
    ///
    /// - `handle`: the native player.
    /// - `muted`: whether it is muted.
    set_muted: *const fn (handle: *anyopaque, muted: bool) void,

    /// Samples the player's state. `failure` points into the handle and stays
    /// valid until the next call.
    ///
    /// - `handle`: the native player.
    /// - Returns: the sample.
    observe: *const fn (handle: *anyopaque) mod.PlayerObservation,

    /// Lists the current item's tracks of one kind, their names and languages
    /// in `allocator`; empty until the item is ready.
    ///
    /// - `handle`: the native player.
    /// - `allocator`: owns the list, its names and languages.
    /// - `kind`: audio or subtitles.
    /// - Returns: the tracks; propagates allocation failure.
    tracks: *const fn (handle: *anyopaque, allocator: std.mem.Allocator, kind: mod.PlayerTrackKind) std.mem.Allocator.Error![]mod.PlayerTrack,

    /// Selects the track at `index` of the list `tracks` returns, or no
    /// subtitles when null (audio cannot be turned off).
    ///
    /// - `handle`: the native player.
    /// - `kind`: audio or subtitles.
    /// - `index`: the track's index in `tracks`' list, or null for no subtitles.
    select_track: *const fn (handle: *anyopaque, kind: mod.PlayerTrackKind, index: ?usize) void,

    /// The latest decoded picture, for a platform whose player hands its
    /// frames to ziggui to draw (`VideoPlayer` draws it in the window's
    /// surface) rather than drawing them itself behind it; null where the
    /// platform draws its own, or before the first frame. The pixels belong
    /// to the handle and stay valid until the next call. `Player` calls it
    /// once a frame however many views show the player.
    ///
    /// - `handle`: the native player.
    /// - Returns: the newest picture and its generation, or null before the
    ///   first one.
    frame: ?*const fn (handle: *anyopaque) ?mod.PlayerFrame = null,

    /// Routes the player's sound to the output whose `AudioOutput.id` is
    /// `id`, or to the system default when null; null where the platform
    /// cannot route one player's sound (the player keeps the default).
    ///
    /// - `handle`: the native player.
    /// - `id`: the output's id, or null for the system default.
    /// - Returns: false when no output has that id now (the system default
    ///   plays), else true.
    set_audio_output: ?*const fn (handle: *anyopaque, id: ?[:0]const u8) bool = null,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
