//! One audio or subtitle track of a `Player`'s item: AVFoundation's media
//! selection options, an HLS stream's `EXT-X-MEDIA` renditions.

const std = @import("std");
const log = std.log.scoped(.ziggui_player_track);

/// Which tracks a `Player.tracks` call lists, or `selectTrack` picks among.
pub const PlayerTrackKind = enum {
    const Self = @This();

    /// Spoken or musical audio (`AVMediaCharacteristic.audible`).
    audio,
    /// Subtitles and captions (`AVMediaCharacteristic.legible`).
    subtitle,
};

/// One track the player can switch to.
pub const PlayerTrack = struct {
    const Self = @This();

    /// The name to show ("English", "Français (forced)"), in the allocator
    /// `Player.tracks` was given.
    name: []const u8,

    /// The BCP 47 language tag ("en", "fr-CA"), empty when the track names
    /// none; in the same allocator.
    language: []const u8,

    /// The track plays (audio) or shows (subtitles) now.
    selected: bool = false,

    /// A forced subtitle track: only the lines in another language than the
    /// audio's.
    forced: bool = false,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
