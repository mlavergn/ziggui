//! One instanced quad of the GPU scene.

const std = @import("std");
const log = std.log.scoped(.ziggui_instance);

/// One instanced quad. Layout must match the vertex attributes declared by the
/// GPU backend's pipeline (nine float4 slots, instance step rate).
pub const Instance = extern struct {
    const Self = @This();

    /// The quad actually rasterized: the shape's rect padded for anti-aliasing
    /// (x, y, width, height, device px).
    quad: [4]f32,
    /// The shape rect the fragment SDF evaluates, unpadded (x, y, width, height).
    shape: [4]f32,
    /// Fill / stroke / gradient-start / glyph tint (straight alpha).
    color0: [4]f32,
    /// Gradient end.
    color1: [4]f32,
    /// Gradient start/end points, or line endpoints (start x, start y, end x, end y).
    points: [4]f32,
    /// Normalized atlas UV rect (u0, v0, u1, v1) for glyph/image kinds.
    atlas_rect: [4]f32,
    /// Axis-aligned intersection of every clip rect on the stack (x, y, width, height).
    clip: [4]f32,
    /// The innermost *rounded* clip on the stack (rect; radius in parameters[3]).
    clip_rounded_rect: [4]f32,
    /// Kind, corner radius, half stroke/line width, rounded-clip radius.
    parameters: [4]f32,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
