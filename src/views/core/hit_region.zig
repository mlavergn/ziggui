//! A tap region registered while painting.

const std = @import("std");
const log = std.log.scoped(.ziggui_hit_region);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A tappable frame and what a tap there does, collected at paint.
pub const HitRegion = struct {
    const Self = @This();

    /// The frame.
    rect: renderer.Rect,

    /// What a tap does.
    action: mod.HitAction,

    /// A disabled region takes no taps.
    disabled: bool,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
