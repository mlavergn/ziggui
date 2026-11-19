//! An app's own controls among the standard ones (`VideoPlayerControlsWith`),
//! as AVKit lets an app add to its player's controls: a back button and
//! title, a record button, a track or output menu. Build them with
//! `VideoPlayerControlButton` and `VideoPlayerControlMenu` so they look like
//! the standard ones.

const std = @import("std");
const log = std.log.scoped(.ziggui_video_player_controls_accessories);
const mod = @import("module.zig");

/// The app's views the standard controls place among their own; each is
/// built for the frame (in the build arena).
pub const VideoPlayerControlsAccessories = struct {
    const Self = @This();

    /// After the full-screen pill, at the top leading corner, on a pill of
    /// its own (a back button and the title), or null for none.
    top_leading: ?mod.View = null,

    /// Before the volume, at the top trailing corner, on one pill (a track
    /// menu, an output menu); empty for none.
    top_trailing: []const mod.View = &.{},

    /// In the transport bar, after the scrubber and before the subtitles and
    /// speed (a record button); empty for none.
    transport: []const mod.View = &.{},
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
