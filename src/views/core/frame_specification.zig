//! A view's `.frame(...)` modifier: fixed, minimum and maximum sizes.

const std = @import("std");
const log = std.log.scoped(.ziggui_frame_specification);
const renderer = @import("renderer");

/// The sizes and alignment a `.frame(...)` modifier sets (null = unset).
pub const FrameSpecification = struct {
    const Self = @This();

    /// A fixed width.
    width: ?f32 = null,

    /// A fixed height.
    height: ?f32 = null,

    /// The least width.
    min_width: ?f32 = null,

    /// The greatest width (`infinity` fills).
    max_width: ?f32 = null,

    /// The least height.
    min_height: ?f32 = null,

    /// The greatest height (`infinity` fills).
    max_height: ?f32 = null,

    /// Where the child sits in the frame.
    alignment: renderer.Alignment = .center,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
