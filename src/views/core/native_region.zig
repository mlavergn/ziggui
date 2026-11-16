//! A `NativeView`'s frame, registered while painting.

const std = @import("std");
const log = std.log.scoped(.ziggui_native_region);
const renderer = @import("renderer");

/// Where a `NativeView` showed its platform view this frame, collected at
/// paint (see `Context.native_regions`): the SDL runtime places the view
/// there, over the window's surface.
pub const NativeRegion = struct {
    const Self = @This();

    /// The platform view shown (an `NSView` on macOS); the app owns it.
    handle: *anyopaque,

    /// The view's whole frame, in points.
    rect: renderer.Rect,

    /// The part of `rect` on screen: a scroll view or `.clipped()` ancestor
    /// cuts the view to it. Empty when none of it shows.
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
