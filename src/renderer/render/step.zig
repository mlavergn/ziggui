//! One run of the GPU scene's instance stream, or a blur, erase, video-frame
//! or 3D-scene break in it.

const std = @import("std");
const log = std.log.scoped(.ziggui_step);
const mod = @import("module.zig");

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

/// Draw one image instance from a texture of its own, uploaded this frame
/// (`DrawCommand.videoFrame`), rather than from the atlas.
pub const FrameStep = struct {
    const Self = @This();

    /// The instance drawn (its UV rect spans the whole texture).
    first: u32,
    /// The pixels the texture is filled with.
    image: mod.Image,
    /// What the pictures come from (`VideoFrameCommand.key`).
    key: usize,
    /// Which picture this is (`VideoFrameCommand.generation`).
    generation: u64,
};

/// Draw a 3D scene into a rect (`DrawCommand.scene`): the backend breaks the
/// instance stream there, draws the scene with its own depth buffer, then
/// carries on; one that cannot draw it draws `placeholder` instead.
pub const SceneStep = struct {
    const Self = @This();

    /// Where the scene is drawn (x, y, width, height), in pixels.
    rect: [4]f32,
    /// The axis-aligned intersection of every clip rect (x, y, width,
    /// height): the scene is cut to it (rounded clips draw square).
    clip: [4]f32,
    /// The scene (a `scenes.Scene`), valid until the frame is drawn.
    scene: *const anyopaque,
    /// The placeholder's instances, drawn only where the scene cannot be.
    placeholder: DrawStep,
};

/// The instance stream split into draw runs, blur breaks, erase runs and
/// video frames, in paint order.
pub const Step = union(enum) {
    const Self = @This();

    /// Draw a run of instances.
    draw: DrawStep,
    /// Blur what is drawn so far.
    blur: BlurStep,
    /// Draw a run of instances (fills) with the erase blend, cutting their
    /// shapes back to transparent (`DrawCommand.eraseRect`).
    erase: DrawStep,
    /// Draw a picture from a texture of its own (`DrawCommand.videoFrame`).
    frame: FrameStep,
    /// Draw a 3D scene (`DrawCommand.scene`).
    scene: SceneStep,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
