//! What a `Player` reports when sampled: its item's status, what it is doing
//! with time, where it is, how much is buffered, and why it failed.

const std = @import("std");
const log = std.log.scoped(.ziggui_player_observation);

/// Whether the current item can play (AVFoundation's `AVPlayerItem.Status`).
pub const PlayerStatus = enum {
    const Self = @This();

    /// Still loading, or there is no item.
    unknown,
    /// The item can play.
    readyToPlay,
    /// The item cannot play; `PlayerObservation.failure` says why.
    failed,
};

/// What the player is doing with time (AVFoundation's
/// `AVPlayer.TimeControlStatus`).
pub const PlayerTimeControl = enum {
    const Self = @This();

    /// Paused, or never asked to play.
    paused,
    /// Asked to play but waiting, usually for media to buffer
    /// (`waitingToPlayAtSpecifiedRate`).
    waitingToPlay,
    /// Playing.
    playing,
};

/// One sample of a player's state. A host polls it (`Player.observe`) as it
/// draws: there are no callbacks, so it never runs on a platform thread.
pub const PlayerObservation = struct {
    const Self = @This();

    /// Whether the current item can play.
    status: PlayerStatus = .unknown,

    /// What the player is doing with time.
    time_control: PlayerTimeControl = .paused,

    /// The player has an item (`Player.replaceCurrentItem` named one).
    has_item: bool = false,

    /// The playback rate: 0 paused, 1 normal speed.
    rate: f32 = 0,

    /// The playhead, in seconds from the item's start.
    current_seconds: f64 = 0,

    /// The item's length in seconds, or null while unknown and for a live
    /// stream, which has no end.
    duration_seconds: ?f64 = null,

    /// How many seconds past the playhead are loaded.
    buffered_seconds: f64 = 0,

    /// The player expects to keep playing without stalling
    /// (`isPlaybackLikelyToKeepUp`).
    likely_to_keep_up: bool = false,

    /// Playback has used up what it loaded (`isPlaybackBufferEmpty`).
    buffer_empty: bool = true,

    /// A seek has been asked for and has not landed yet.
    seeking: bool = false,

    /// The video's display size in pixels, or 0 before it is known (and for
    /// audio).
    presentation_width: f32 = 0,

    /// The video's display height in pixels, or 0 before it is known.
    presentation_height: f32 = 0,

    /// Why the item failed, empty otherwise. It lives in the player and stays
    /// valid until the player is observed again or deinitialized.
    failure: []const u8 = "",

    /// Reports whether the player is actually showing frames: ready, and
    /// playing rather than paused or waiting.
    ///
    /// - `self`: the observation.
    /// - Returns: true while playing.
    pub fn isPlaying(self: *const Self) bool {
        return self.status == .readyToPlay and self.time_control == .playing;
    }

    /// Reports whether the item is live: one with no end (a live stream),
    /// which the controls show without skips, speed or a scrubber.
    ///
    /// - `self`: the observation.
    /// - Returns: true for an item with no length.
    pub fn isLive(self: *const Self) bool {
        return self.has_item and self.duration_seconds == null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "player observation: playing needs both a ready item and the playing time control" {
    try std.testing.expect(!(PlayerObservation{}).isPlaying());
    try std.testing.expect(!(PlayerObservation{ .status = .readyToPlay, .time_control = .waitingToPlay }).isPlaying());
    try std.testing.expect((PlayerObservation{ .status = .readyToPlay, .time_control = .playing }).isPlaying());
}

test "player observation: an item with no length is live, and no item is not" {
    try std.testing.expect(!(PlayerObservation{}).isLive());
    try std.testing.expect((PlayerObservation{ .has_item = true }).isLive());
    try std.testing.expect(!(PlayerObservation{ .has_item = true, .duration_seconds = 60 }).isLive());
}
