//! One run of the GPU scene's instance stream, or a blur break in it.

const std = @import("std");
const log = std.log.scoped(.ziggui_step);

/// Draw `count` instances starting at `first` (indices into
/// `GpuScene.instances`).
pub const DrawStep = struct {
    const Self = @This();

    /// The first instance drawn.
    first: u32,
    /// How many instances are drawn.
    count: u32,
};

/// Blur what has been rendered so far beneath `rect`, then composite `tint`
/// masked by the (rounded) rect and the clip state captured at emit time.
pub const BlurStep = struct {
    const Self = @This();

    /// The region blurred (x, y, width, height).
    rect: [4]f32,
    /// The region's corner radius.
    radius: f32,
    /// The blur's extent.
    sigma: f32,
    /// The color laid over the blur (straight alpha).
    tint: [4]f32,
    /// Axis-aligned intersection of every clip rect (x, y, width, height).
    clip: [4]f32,
    /// The innermost rounded clip's rect.
    clip_rounded_rect: [4]f32,
    /// The innermost rounded clip's radius.
    clip_radius: f32,
};

/// The instance stream split into draw runs and blur breaks, in paint order.
pub const Step = union(enum) {
    const Self = @This();

    /// Draw a run of instances.
    draw: DrawStep,
    /// Blur what is drawn so far.
    blur: BlurStep,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
