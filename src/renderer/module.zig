//! The renderer: geometry, layout, color, the canvas and its rasterizers,
//! text, themes, state and animation. Pure Zig, no C, no views.

const std = @import("std");
const log = std.log.scoped(.ziggui_renderer_module);

// -----------------------------------------------------------------------------
// Geometry

/// A 2D point in logical coordinates.
pub const Point = @import("geometry/module.zig").Point;
/// A 2D extent in logical coordinates.
pub const Size = @import("geometry/module.zig").Size;
/// An axis-aligned, half-open rectangle.
pub const Rect = @import("geometry/module.zig").Rect;
/// Per-side spacing (top, leading, bottom, trailing).
pub const EdgeInsets = @import("geometry/module.zig").EdgeInsets;
/// A horizontal and a vertical alignment guide together.
pub const Alignment = @import("geometry/module.zig").Alignment;
/// A horizontal alignment guide.
pub const HorizontalAlignment = @import("geometry/module.zig").HorizontalAlignment;
/// A vertical alignment guide.
pub const VerticalAlignment = @import("geometry/module.zig").VerticalAlignment;
/// The two layout axes.
pub const Axis = @import("geometry/module.zig").Axis;

// -----------------------------------------------------------------------------
// Drawing

/// An RGBA color with f32 channels.
pub const Color = @import("render/module.zig").Color;
/// A color as four 8-bit channels.
pub const Rgba8 = @import("render/module.zig").Rgba8;
/// An 8-bit coverage mask.
pub const Coverage = @import("render/module.zig").Coverage;
/// An RGBA8 image.
pub const Image = @import("render/module.zig").Image;
/// One drawing operation.
pub const DrawCommand = @import("render/module.zig").DrawCommand;
/// A `DrawCommand.fillRoundedRect` payload.
pub const FillRoundedRectCommand = @import("render/module.zig").FillRoundedRectCommand;
/// A `DrawCommand.strokeRoundedRect` payload.
pub const StrokeRoundedRectCommand = @import("render/module.zig").StrokeRoundedRectCommand;
/// A `DrawCommand.linearGradient` payload.
pub const LinearGradientCommand = @import("render/module.zig").LinearGradientCommand;
/// A `DrawCommand.line` payload.
pub const LineCommand = @import("render/module.zig").LineCommand;
/// A `DrawCommand.glyph` payload.
pub const GlyphCommand = @import("render/module.zig").GlyphCommand;
/// A `DrawCommand.image` payload.
pub const ImageCommand = @import("render/module.zig").ImageCommand;
/// A `DrawCommand.blurRect` payload.
pub const BlurRectCommand = @import("render/module.zig").BlurRectCommand;
/// A `DrawCommand.pushClip` payload.
pub const PushClipCommand = @import("render/module.zig").PushClipCommand;
/// A retained list of draw commands.
pub const Canvas = @import("render/module.zig").Canvas;
/// A CPU pixel buffer.
pub const Framebuffer = @import("render/module.zig").Framebuffer;
/// Paints draw commands into a framebuffer on the CPU.
pub const Rasterizer = @import("render/module.zig").Rasterizer;
/// One instanced quad of the GPU scene.
pub const Instance = @import("render/module.zig").Instance;
/// A run of the GPU scene's instances, or a blur break.
pub const Step = @import("render/module.zig").Step;
/// A `Step.draw` payload.
pub const DrawStep = @import("render/module.zig").DrawStep;
/// A `Step.blur` payload.
pub const BlurStep = @import("render/module.zig").BlurStep;
/// A pending texture-atlas region upload.
pub const AtlasUpload = @import("render/module.zig").AtlasUpload;
/// The GPU scene's texture atlas bookkeeping.
pub const TextureAtlas = @import("render/module.zig").TextureAtlas;
/// A canvas translated for the GPU.
pub const GpuScene = @import("render/module.zig").GpuScene;

// -----------------------------------------------------------------------------
// State and animation

/// Something notified when state it depends on changes.
pub const Observer = @import("state/module.zig").Observer;
/// An observable value (`State(T)`).
pub const State = @import("state/module.zig").State;
/// A type-erased two-way handle into a value (`Binding(T)`).
pub const Binding = @import("state/module.zig").Binding;
/// A timing curve.
pub const Easing = @import("state/module.zig").Easing;
/// One value animation.
pub const Tween = @import("state/module.zig").Tween;
/// The in-flight tweens of an app.
pub const Animator = @import("state/module.zig").Animator;

// -----------------------------------------------------------------------------
// Layout

/// A size a parent proposes to a child.
pub const Proposal = @import("layout/module.zig").Proposal;
/// The intrinsic sizing of a layout leaf.
pub const SizingHints = @import("layout/module.zig").SizingHints;
/// The direction a stack runs in.
pub const Direction = @import("layout/module.zig").Direction;
/// A stack in the layout tree.
pub const StackNode = @import("layout/module.zig").StackNode;
/// Padding around a child in the layout tree.
pub const PaddingNode = @import("layout/module.zig").PaddingNode;
/// A frame modifier in the layout tree.
pub const FrameNode = @import("layout/module.zig").FrameNode;
/// A spacer in the layout tree.
pub const SpacerNode = @import("layout/module.zig").SpacerNode;
/// A leaf that measures itself against the live proposal.
pub const MeasuredNode = @import("layout/module.zig").MeasuredNode;
/// A node of the layout tree.
pub const Node = @import("layout/module.zig").Node;
/// The placement the arrange pass produces for a node.
pub const LayoutResult = @import("layout/module.zig").LayoutResult;
/// One stack child's main-axis bounds.
pub const FlexItem = @import("layout/module.zig").FlexItem;
/// Per-call scratch storage for a stack's children.
pub const Scratch = @import("layout/module.zig").Scratch;
/// Shares a stack's main-axis length among its children.
pub const SpaceDistributor = @import("layout/module.zig").SpaceDistributor;
/// Measures and arranges layout trees.
pub const LayoutEngine = @import("layout/module.zig").LayoutEngine;

// -----------------------------------------------------------------------------
// Text

/// A parsed TrueType face.
pub const TtfFont = @import("text/module.zig").TtfFont;
/// Why a blob failed to parse as a TrueType font.
pub const TtfParseError = @import("text/module.zig").TtfParseError;
/// A codepoint resolved to the face that carries its glyph.
pub const ResolvedGlyph = @import("text/module.zig").ResolvedGlyph;
/// A glyph's coverage bitmap and its placement.
pub const RasterGlyph = @import("text/module.zig").RasterGlyph;
/// The callbacks of a face another engine reads.
pub const ExternalFace = @import("text/module.zig").ExternalFace;
/// Rasterized glyphs of a face, by glyph and pixel size.
pub const GlyphCache = @import("text/module.zig").GlyphCache;
/// A glyph and its pen position on a line.
pub const PositionedGlyph = @import("text/module.zig").PositionedGlyph;
/// One line of word-wrapped text.
pub const WrappedLine = @import("text/module.zig").WrappedLine;
/// Measures, lays out and wraps text in one face.
pub const TextShaper = @import("text/module.zig").TextShaper;
/// A font face and its metrics.
pub const Font = @import("text/module.zig").Font;
/// Paints text and icon glyphs into a canvas (`TextPainter.shared()`).
pub const TextPainter = @import("text/module.zig").TextPainter;
/// A text style's face selection (weight, italic, monospace).
pub const FontStyle = @import("text/module.zig").FontStyle;
/// The bundled faces and a glyph cache for each.
pub const FontSet = @import("text/module.zig").FontSet;
/// A Lucide icon, valued by its codepoint in the icon font.
pub const Icon = @import("text/module.zig").Icon;

// -----------------------------------------------------------------------------
// Themes

/// Light or dark.
pub const ColorScheme = @import("theme/module.zig").ColorScheme;
/// A font weight.
pub const FontWeight = @import("theme/module.zig").FontWeight;
/// A point size, weight and line-height multiple.
pub const TextStyle = @import("theme/module.zig").TextStyle;
/// The semantic appearance of a control.
pub const Role = @import("theme/module.zig").Role;
/// What a floating panel is for.
pub const PanelKind = @import("theme/module.zig").PanelKind;
/// The interaction state of a control.
pub const ControlState = @import("theme/module.zig").ControlState;
/// Semantic color roles for one color scheme.
pub const Palette = @import("theme/module.zig").Palette;
/// A theme's text styles.
pub const Typography = @import("theme/module.zig").Typography;
/// A theme's spacing, sizing, and radius metrics.
pub const Metrics = @import("theme/module.zig").Metrics;
/// Everything a painter needs to draw chrome.
pub const Surface = @import("theme/module.zig").Surface;
/// A theme's vtable of chrome-drawing functions.
pub const Painter = @import("theme/module.zig").Painter;
/// The named text styles `Theme.font` takes.
pub const TextStyleName = @import("theme/module.zig").TextStyleName;
/// A fully-resolved theme for one color scheme (`Theme.default` is macOS light).
pub const Theme = @import("theme/module.zig").Theme;
/// The built-in theme families (`ThemeFamily.all`, `forScheme`).
pub const ThemeFamily = @import("theme/module.zig").ThemeFamily;
/// The macOS Liquid Glass themes.
pub const MacosTheme = @import("theme/module.zig").MacosTheme;
/// The Windows 2000 chiseled themes.
pub const Win2000Theme = @import("theme/module.zig").Win2000Theme;
/// The Windows 10 flat themes.
pub const Windows10Theme = @import("theme/module.zig").Windows10Theme;
/// The KDE Plasma Breeze themes.
pub const KdeTheme = @import("theme/module.zig").KdeTheme;
/// The Material themes.
pub const MuiTheme = @import("theme/module.zig").MuiTheme;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("geometry/module.zig");
    _ = @import("layout/module.zig");
    _ = @import("render/module.zig");
    _ = @import("state/module.zig");
    _ = @import("text/module.zig");
    _ = @import("theme/module.zig");
}
