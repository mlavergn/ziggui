//! Drawing: colors, the canvas command list, and the two backends' CPU sides
//! (the software rasterizer and the GPU scene translation).

const std = @import("std");
const log = std.log.scoped(.ziggui_render_module);

/// An RGBA color with f32 channels.
pub const Color = @import("color.zig").Color;
/// A color as four 8-bit channels.
pub const Rgba8 = @import("rgba8.zig").Rgba8;
/// An 8-bit coverage mask.
pub const Coverage = @import("coverage.zig").Coverage;
/// An RGBA8 image.
pub const Image = @import("image.zig").Image;
/// One drawing operation.
pub const DrawCommand = @import("draw_command.zig").DrawCommand;
/// A `DrawCommand.fillRoundedRect` payload.
pub const FillRoundedRectCommand = @import("draw_command.zig").FillRoundedRectCommand;
/// A `DrawCommand.strokeRoundedRect` payload.
pub const StrokeRoundedRectCommand = @import("draw_command.zig").StrokeRoundedRectCommand;
/// A `DrawCommand.linearGradient` payload.
pub const LinearGradientCommand = @import("draw_command.zig").LinearGradientCommand;
/// A `DrawCommand.line` payload.
pub const LineCommand = @import("draw_command.zig").LineCommand;
/// A `DrawCommand.glyph` payload.
pub const GlyphCommand = @import("draw_command.zig").GlyphCommand;
/// A `DrawCommand.image` payload.
pub const ImageCommand = @import("draw_command.zig").ImageCommand;
/// A `DrawCommand.blurRect` payload.
pub const BlurRectCommand = @import("draw_command.zig").BlurRectCommand;
/// A `DrawCommand.pushClip` payload.
pub const PushClipCommand = @import("draw_command.zig").PushClipCommand;
/// A retained list of draw commands.
pub const Canvas = @import("canvas.zig").Canvas;
/// A CPU pixel buffer.
pub const Framebuffer = @import("framebuffer.zig").Framebuffer;
/// Paints draw commands into a framebuffer on the CPU.
pub const Rasterizer = @import("rasterizer.zig").Rasterizer;
/// One instanced quad of the GPU scene.
pub const Instance = @import("instance.zig").Instance;
/// A run of the GPU scene's instances, or a blur break.
pub const Step = @import("step.zig").Step;
/// A `Step.draw` payload.
pub const DrawStep = @import("step.zig").DrawStep;
/// A `Step.blur` payload.
pub const BlurStep = @import("step.zig").BlurStep;
/// A pending texture-atlas region upload.
pub const AtlasUpload = @import("atlas_upload.zig").AtlasUpload;
/// The GPU scene's texture atlas bookkeeping.
pub const TextureAtlas = @import("texture_atlas.zig").TextureAtlas;
/// A canvas translated for the GPU.
pub const GpuScene = @import("gpu_scene.zig").GpuScene;

/// A 2D point (from the renderer).
pub const Point = @import("../module.zig").Point;
/// An axis-aligned rectangle (from the renderer).
pub const Rect = @import("../module.zig").Rect;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("color.zig");
    _ = @import("rgba8.zig");
    _ = @import("coverage.zig");
    _ = @import("image.zig");
    _ = @import("draw_command.zig");
    _ = @import("canvas.zig");
    _ = @import("framebuffer.zig");
    _ = @import("rasterizer.zig");
    _ = @import("instance.zig");
    _ = @import("step.zig");
    _ = @import("atlas_upload.zig");
    _ = @import("texture_atlas.zig");
    _ = @import("gpu_scene.zig");
}
