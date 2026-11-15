//! The platform media player a `Player` drives, as function pointers: the
//! SDL runtime installs its own (AVFoundation on macOS) as its loop starts,
//! so the views stay free of any platform code, and tests install a fake.

const std = @import("std");
const log = std.log.scoped(.ziggui_player_backend);
const mod = @import("module.zig");

/// One platform player's operations. Every function runs on the UI thread
/// and takes the native handle `create` returned.
pub const PlayerBackend = struct {
    const Self = @This();

    /// Why this platform cannot play video yet, or null when it can. A
    /// backend that sets it never has `create` called: its players report
    /// `.failed` with this text.
    unsupported: ?[]const u8 = null,

    /// Makes a native player with no item, or returns null when the platform
    /// refuses (the player then reports `.failed`).
    create: *const fn () ?*anyopaque,

    /// Stops the player, takes its picture off screen and frees it.
    destroy: *const fn (handle: *anyopaque) void,

    /// Replaces the current item with the media at `url` (a URL, or a local
    /// path), or with none when null. The new item starts paused at its start
    /// unless the player's rate is above 0.
    load: *const fn (handle: *anyopaque, url: ?[:0]const u8) void,

    /// Plays at the given rate (1 normal speed); 0 pauses.
    set_rate: *const fn (handle: *anyopaque, rate: f32) void,

    /// Moves the playhead to `seconds` from the item's start.
    seek: *const fn (handle: *anyopaque, seconds: f64) void,

    /// Sets the volume, 0 silent to 1 full.
    set_volume: *const fn (handle: *anyopaque, volume: f32) void,

    /// Mutes or unmutes, keeping the volume.
    set_muted: *const fn (handle: *anyopaque, muted: bool) void,

    /// Samples the player's state. `failure` points into the handle and stays
    /// valid until the next call.
    observe: *const fn (handle: *anyopaque) mod.PlayerObservation,

    /// Lists the current item's tracks of one kind, their names and languages
    /// in `allocator`; empty until the item is ready.
    tracks: *const fn (handle: *anyopaque, allocator: std.mem.Allocator, kind: mod.PlayerTrackKind) std.mem.Allocator.Error![]mod.PlayerTrack,

    /// Selects the track at `index` of the list `tracks` returns, or no
    /// subtitles when null (audio cannot be turned off).
    select_track: *const fn (handle: *anyopaque, kind: mod.PlayerTrackKind, index: ?usize) void,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
