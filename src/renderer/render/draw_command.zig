//! One high-level drawing operation in a `DisplayList` command list.

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

/// An RGBA8 image whose pixels change from frame to frame (a video's
/// picture), stretched over a rect. Unlike `ImageCommand` it is never cached
/// in the atlas: the GPU backend keeps a texture of its own per `key` and
/// uploads the pixels again only when `generation` changes.
pub const VideoFrameCommand = struct {
    const Self = @This();

    /// Where the image is drawn.
    rect: mod.Rect,
    /// The pixels, valid until the frame is drawn.
    image: mod.Image,
    /// What the pictures come from (a player), stable while it lives.
    key: usize,
    /// Changes with each new picture from `key`.
    generation: u64,
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

/// Erase what is already drawn inside a (possibly rounded) rect back to
/// transparent (destination-out), so whatever lies behind the window's
/// surface shows through: the hole a native video layer is seen in. Draws
/// after it composite over the hole as usual, so controls stay on top.
pub const EraseRectCommand = struct {
    const Self = @This();

    /// The rect erased.
    rect: mod.Rect,
    /// The corner radius.
    radius: f32 = 0,
};

/// Draw a 3D scene into a rect: the GPU backend draws the scene there (with
/// its own depth buffer, over what is drawn already, under what is drawn
/// after); the software rasterizer, and a GPU that cannot draw it, draw the
/// placeholder (`placeholder`). The renderer cannot see the scene's type
/// (`scenes` imports `renderer`), so it is carried as an opaque pointer.
pub const SceneCommand = struct {
    const Self = @This();

    /// How many commands the placeholder is: a fill and a cube's nine edges.
    pub const placeholder_count = 10;

    /// Where the scene is drawn.
    rect: mod.Rect,
    /// The scene (a `scenes.Scene`), valid until the frame is drawn.
    scene: *const anyopaque,
    /// The placeholder's ground.
    ground: mod.Color,
    /// The placeholder's cube.
    ink: mod.Color,

    /// What stands in for the scene where it cannot be drawn: the rect
    /// filled with `ground` and an isometric cube in `ink` at its center.
    ///
    /// - `self`: the command.
    /// - Returns: the placeholder's commands.
    pub fn placeholder(self: *const Self) [placeholder_count]DrawCommand {
        var commands: [placeholder_count]DrawCommand = undefined;
        commands[0] = .{ .fillRoundedRect = .{ .rect = self.rect, .color = self.ground } };
        const center = mod.Point{ .x = self.rect.x + self.rect.width / 2, .y = self.rect.y + self.rect.height / 2 };
        const radius = @min(self.rect.width, self.rect.height) * 0.18;
        const width = @max(1, radius * 0.08);
        // A pointy-top hexagon (its corners clockwise from the top), then
        // the three edges meeting at its center that make it a cube.
        var corners: [6]mod.Point = undefined;
        for (&corners, 0..) |*corner, index| {
            const angle = std.math.degreesToRadians(-90 + 60 * @as(f32, @floatFromInt(index)));
            corner.* = .{ .x = center.x + radius * @cos(angle), .y = center.y + radius * @sin(angle) };
        }
        for (corners, 0..) |corner, index| {
            commands[1 + index] = .{ .line = .{ .start = corner, .end = corners[(index + 1) % 6], .width = width, .color = self.ink } };
        }
        for ([_]usize{ 1, 3, 5 }, 0..) |corner, index| {
            commands[7 + index] = .{ .line = .{ .start = center, .end = corners[corner], .width = width, .color = self.ink } };
        }
        return commands;
    }
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
    /// Draw a picture that changes every frame, uncached.
    videoFrame: VideoFrameCommand,
    /// Frost what is beneath a rect.
    blurRect: BlurRectCommand,
    /// Erase what is beneath a rect to transparent.
    eraseRect: EraseRectCommand,
    /// Draw a 3D scene.
    scene: SceneCommand,
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

test "a scene's placeholder fills its rect and draws a cube inside it" {
    const command = SceneCommand{ .rect = .{ .x = 10, .y = 20, .width = 200, .height = 100 }, .scene = &command_marker, .ground = mod.Color.black, .ink = mod.Color.white };
    const commands = command.placeholder();
    try std.testing.expectEqual(command.rect, commands[0].fillRoundedRect.rect);
    for (commands[1..]) |edge| {
        for ([_]mod.Point{ edge.line.start, edge.line.end }) |point| {
            try std.testing.expect(command.rect.contains(point));
        }
    }
}

/// Something for a test command's scene pointer to point at.
const command_marker: u8 = 0;
