//! Media playback: a `Player` modeled on AVFoundation's `AVPlayer`, the
//! `PlayerBackend` the SDL runtime plugs a platform player into, and the
//! `VideoPlayer` view that shows a player's picture.

const std = @import("std");
const log = std.log.scoped(.ziggui_media_module);

/// Whether a player's item can play.
pub const PlayerStatus = @import("player_observation.zig").PlayerStatus;
/// What a player is doing with time: paused, waiting, playing.
pub const PlayerTimeControl = @import("player_observation.zig").PlayerTimeControl;
/// One sample of a player's state (`Player.observe`).
pub const PlayerObservation = @import("player_observation.zig").PlayerObservation;
/// Audio or subtitles, for `Player.tracks` and `selectTrack`.
pub const PlayerTrackKind = @import("player_track.zig").PlayerTrackKind;
/// One audio or subtitle track of a player's item.
pub const PlayerTrack = @import("player_track.zig").PlayerTrack;
/// A platform media player's operations, installed by the SDL runtime.
pub const PlayerBackend = @import("player_backend.zig").PlayerBackend;
/// A media player modeled on `AVPlayer` (`replaceCurrentItem`, `play`, `seek`, `observe`, `tracks`).
pub const Player = @import("player.zig").Player;
/// A player's picture in the view tree.
pub const VideoPlayer = @import("video_player.zig").VideoPlayer;

// -----------------------------------------------------------------------------
// From the views module

/// A node of the view tree, from the views module.
pub const View = @import("../module.zig").View;

/// The frame clock a player keys its per-frame sample to, from the views module.
pub const FrameClock = @import("../module.zig").FrameClock;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("player_observation.zig");
    _ = @import("player_track.zig");
    _ = @import("player_backend.zig");
    _ = @import("player.zig");
    _ = @import("video_player.zig");
}
