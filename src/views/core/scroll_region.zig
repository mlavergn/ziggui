//! A scroll view's frame and state, collected while painting.

const std = @import("std");
const log = std.log.scoped(.ziggui_scroll_region);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A scrollable viewport's frame paired with its `ScrollState`, collected during
/// painting (when `Context.scroll_regions` is set) so the app can route mouse
/// wheel events to the right region via `PointerInput.scroll`.
pub const ScrollRegion = struct {
    const Self = @This();

    /// The viewport.
    rect: renderer.Rect,

    /// The scroll position the wheel moves.
    state: *mod.ScrollState,

    /// A `ScrollViewStateBoth`, which also takes sideways deltas.
    horizontal: bool = false,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
