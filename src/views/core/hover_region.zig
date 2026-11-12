//! An `onHover` region registered while painting.

const std = @import("std");
const log = std.log.scoped(.ziggui_hover_region);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A view's frame and its `onHover` callback, collected at paint (see
/// `Context.hover_regions` and `PointerInput.hover`).
pub const HoverRegion = struct {
    const Self = @This();

    /// The frame.
    rect: renderer.Rect,

    /// Told when the pointer enters or leaves it.
    callback: mod.HoverCallback,

    /// A disabled region is never told.
    disabled: bool,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
