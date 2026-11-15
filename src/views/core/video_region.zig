//! A `VideoPlayer`'s frame, registered while painting.

const std = @import("std");
const log = std.log.scoped(.ziggui_video_region);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Where a `VideoPlayer` showed its player this frame, collected at paint
/// (see `Context.video_regions`): the SDL runtime puts the platform player's
/// picture there, behind the hole the view erased in the window's surface.
pub const VideoRegion = struct {
    const Self = @This();

    /// The player shown.
    player: *mod.Player,

    /// The view's whole frame, in points.
    rect: renderer.Rect,

    /// The part of `rect` on screen: a scroll view or `.clipped()` ancestor
    /// cuts the picture to it. Empty when none of it shows.
    visible: renderer.Rect,

    /// The frame's corner radius, in points.
    corner_radius: f32 = 0,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
