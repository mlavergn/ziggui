//! A popover, sheet or alert waiting to be drawn over the frame.

const std = @import("std");
const log = std.log.scoped(.ziggui_overlay_request);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A request, collected during painting, to draw an overlay on top of the whole
/// frame. The `ViewRenderer.render` drain pass turns each into a scrim plus
/// positioned content.
pub const OverlayRequest = struct {
    const Self = @This();

    /// What the overlay shows.
    content: mod.View,

    /// How it is drawn.
    style: mod.OverlayStyle,

    /// The presenting view's frame, used to position popovers/menus.
    anchor: renderer.Rect,

    /// Binding flipped to false when the scrim is tapped (tap-to-dismiss).
    dismiss: ?mod.Binding(bool) = null,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
