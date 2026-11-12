//! One high-level drawing operation in a `Canvas` command list.

const std = @import("std");
const log = std.log.scoped(.ziggui_draw_command);
const mod = @import("module.zig");

/// Fill a (possibly rounded) rect with a solid color.
pub const FillRoundedRectCommand = struct {
    const Self = @This();

    /// The rect filled.
    rect: mod.Rect,
    /// The corner radius.
    radius: f32 = 0,
    /// The fill color.
    color: mod.Color,
};

/// Stroke the outline of a (possibly rounded) rect.
pub const StrokeRoundedRectCommand = struct {
    const Self = @This();

    /// The rect outlined.
    rect: mod.Rect,
    /// The corner radius.
    radius: f32 = 0,
    /// The stroke's width, centered on the outline.
    width: f32 = 1,
    /// The stroke color.
    color: mod.Color,
};

/// Linear gradient clipped to a (possibly rounded) rect, interpolating from
/// `start_color` at `start` to `end_color` at `end`.
pub const LinearGradientCommand = struct {
    const Self = @This();

    /// The rect filled.
    rect: mod.Rect,
    /// The corner radius.
    radius: f32 = 0,
    /// Where the gradient is `start_color`.
    start: mod.Point,
    /// Where the gradient is `end_color`.
    end: mod.Point,
    /// The color at `start`.
    start_color: mod.Color,
    /// The color at `end`.
    end_color: mod.Color,
};

/// A straight line segment.
pub const LineCommand = struct {
    const Self = @This();

    /// One end of the segment.
    start: mod.Point,
    /// The other end of the segment.
    end: mod.Point,
    /// The line's width.
    width: f32 = 1,
    /// The line's color.
    color: mod.Color,
};

/// A glyph (or any coverage mask) tinted with `color`, drawn so the mask's
/// top-left lands at `rect` origin and is scaled to `rect` size. `gamma` is
/// the exponent applied to coverage at composite time (`cov' = pow(cov,
/// gamma)`): 1.0 leaves it untouched, < 1 thickens the anti-aliased edge
/// (gamma-correct text on a dark background), > 1 thins it (dark-on-light).
/// Both backends apply it identically, so the paths stay pixel-matched.
pub const GlyphCommand = struct {
    const Self = @This();

    /// Where the mask is drawn.
    rect: mod.Rect,
    /// The tint.
    color: mod.Color,
    /// The mask.
    coverage: mod.Coverage,
    /// The coverage exponent.
    gamma: f32 = 1,
};

/// An RGBA8 image stretched over a rect.
pub const ImageCommand = struct {
    const Self = @This();

    /// Where the image is drawn.
    rect: mod.Rect,
    /// The pixels.
    image: mod.Image,
};

/// Blur the pixels already drawn beneath `rect`, then composite `tint` over
/// the result — the primitive behind frosted "material" backgrounds. `sigma`
/// controls the blur extent. Backend-neutral: the software rasterizer does a
/// separable box blur; the GPU backend samples the framebuffer.
pub const BlurRectCommand = struct {
    const Self = @This();

    /// The region blurred.
    rect: mod.Rect,
    /// The region's corner radius.
    radius: f32 = 0,
    /// The blur's extent.
    sigma: f32 = 0,
    /// The color laid over the blur.
    tint: mod.Color = mod.Color.transparent,
};

/// Push a clip region; subsequent draws are masked to the intersection of
/// all clips on the stack until the matching `popClip`.
pub const PushClipCommand = struct {
    const Self = @This();

    /// The clip's rect.
    rect: mod.Rect,
    /// The clip's corner radius.
    radius: f32 = 0,
};

/// One drawing operation, consumed alike by the software rasterizer and the
/// GPU backend.
pub const DrawCommand = union(enum) {
    const Self = @This();

    /// Fill a rounded rect.
    fillRoundedRect: FillRoundedRectCommand,
    /// Stroke a rounded rect's outline.
    strokeRoundedRect: StrokeRoundedRectCommand,
    /// Fill a rounded rect with a linear gradient.
    linearGradient: LinearGradientCommand,
    /// Draw a line segment.
    line: LineCommand,
    /// Draw a tinted coverage mask.
    glyph: GlyphCommand,
    /// Draw an image.
    image: ImageCommand,
    /// Frost what is beneath a rect.
    blurRect: BlurRectCommand,
    /// Push a clip region.
    pushClip: PushClipCommand,
    /// Pop the innermost clip region.
    popClip,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
