//! The view engine: the `View` value and its modifiers, lowering to the
//! layout tree, painting, rendering with overlays, and the pointer, focus,
//! selection and build state a frame runs with.

const std = @import("std");
const log = std.log.scoped(.ziggui_core_module);
const renderer = @import("renderer");

// -----------------------------------------------------------------------------
// The view and what it carries

/// A node of the view tree (`kind` plus `modifiers`, with a fluent modifier API).
pub const View = @import("view.zig").View;
/// What a view is: one variant per kind of view.
pub const Kind = @import("kind.zig").Kind;
/// A `Text`'s payload.
pub const TextData = @import("kind.zig").TextData;
/// A `WrappedText`'s payload.
pub const WrappedTextData = @import("kind.zig").WrappedTextData;
/// A `RichText`'s payload.
pub const RichTextData = @import("kind.zig").RichTextData;
/// A `Spacer`'s payload.
pub const SpacerData = @import("kind.zig").SpacerData;
/// A shape's payload.
pub const ShapeData = @import("kind.zig").ShapeData;
/// A stack's payload.
pub const StackData = @import("kind.zig").StackData;
/// A button's payload.
pub const ButtonData = @import("kind.zig").ButtonData;
/// A switch's payload.
pub const ToggleData = @import("kind.zig").ToggleData;
/// A slider's payload.
pub const SliderData = @import("kind.zig").SliderData;
/// A stepper's payload.
pub const StepperData = @import("kind.zig").StepperData;
/// A progress bar's payload.
pub const ProgressData = @import("kind.zig").ProgressData;
/// An image's payload.
pub const ImageData = @import("kind.zig").ImageData;
/// A label's payload.
pub const LabelData = @import("kind.zig").LabelData;
/// An icon's payload.
pub const IconData = @import("kind.zig").IconData;
/// An icon button's payload.
pub const IconButtonData = @import("kind.zig").IconButtonData;
/// A fixed-offset scroll view's payload.
pub const ScrollData = @import("kind.zig").ScrollData;
/// A text field's payload.
pub const TextFieldData = @import("kind.zig").TextFieldData;
/// A text editor's payload.
pub const TextEditorData = @import("kind.zig").TextEditorData;
/// A state-driven scroll view's payload.
pub const ScrollStateData = @import("kind.zig").ScrollStateData;
/// A `GeometryReader`'s payload.
pub const GeometryData = @import("kind.zig").GeometryData;
/// A picker's payload.
pub const PickerData = @import("kind.zig").PickerData;
/// A `Drawing`'s payload.
pub const DrawingData = @import("kind.zig").DrawingData;
/// The modifiers applied around a view's content.
pub const Modifiers = @import("modifiers.zig").Modifiers;
/// A `.sheet`/`.alert`/`.popover` modifier.
pub const OverlayModifier = @import("modifiers.zig").OverlayModifier;
/// A `.frame(...)` modifier's sizes and alignment.
pub const FrameSpecification = @import("frame_specification.zig").FrameSpecification;
/// What a background or shape is filled with.
pub const Fill = @import("fill.zig").Fill;
/// A two-color linear gradient fill.
pub const GradientFill = @import("fill.zig").GradientFill;
/// A translucent, blurred background.
pub const Material = @import("material.zig").Material;
/// A material's tint scale and blur.
pub const MaterialSpecification = @import("material.zig").MaterialSpecification;
/// How a presented overlay is drawn.
pub const OverlayStyle = @import("overlay_style.zig").OverlayStyle;
/// Named typographic styles.
pub const FontToken = @import("font_token.zig").FontToken;
/// The outline a shape view fills.
pub const ShapeKind = @import("shape_kind.zig").ShapeKind;
/// The semantic appearance of a button (the theme layer's role).
pub const ButtonRole = renderer.Role;
/// The icon font's glyph names.
pub const IconName = renderer.Icon;
/// A read/write handle on a `State`.
pub const Binding = renderer.Binding;
/// An app's accent, a setting: the brand's orange or one of macOS's (`theme` applies it, the macOS dark on black).
pub const Accent = @import("accent.zig").Accent;

// -----------------------------------------------------------------------------
// Callbacks

/// A tap handler (`init` wraps a method, `action` a function, `select` a selection).
pub const Callback = @import("callback.zig").Callback;
/// What `View.onHover` calls.
pub const HoverCallback = @import("hover_callback.zig").HoverCallback;
/// What `View.onDrag` calls.
pub const DragCallback = @import("drag_callback.zig").DragCallback;

// -----------------------------------------------------------------------------
// Scrolling

/// A scroll view's app-owned offsets and extents.
pub const ScrollState = @import("scroll_state.zig").ScrollState;
/// A scroll view's frame and state, collected while painting.
pub const ScrollRegion = @import("scroll_region.zig").ScrollRegion;
/// The overlay scrollbars a scroll view draws and drags.
pub const Scrollbar = @import("scrollbar.zig").Scrollbar;
/// A scrollbar thumb along one axis.
pub const Thumb = @import("scrollbar.zig").Thumb;

// -----------------------------------------------------------------------------
// The render context and what painting collects

/// What a frame is laid out and painted with.
pub const Context = @import("context.zig").Context;
/// Where the input sinks stood before clipped content painted.
pub const InputMarks = @import("context.zig").InputMarks;
/// What a tap region does.
pub const HitAction = @import("hit_action.zig").HitAction;
/// A slider track's tap action.
pub const SliderTrack = @import("hit_action.zig").SliderTrack;
/// A stepper half's tap action.
pub const StepAction = @import("hit_action.zig").StepAction;
/// A picker segment's tap action.
pub const SelectValue = @import("hit_action.zig").SelectValue;
/// A text field's or editor's clickable text geometry.
pub const TextClick = @import("text_click.zig").TextClick;
/// A tap region registered while painting.
pub const HitRegion = @import("hit_region.zig").HitRegion;
/// An `onHover` region registered while painting.
pub const HoverRegion = @import("hover_region.zig").HoverRegion;
/// An accessibility role.
pub const A11yRole = @import("a11y_role.zig").A11yRole;
/// One node of the accessibility tree.
pub const A11yNode = @import("a11y_node.zig").A11yNode;
/// A popover, sheet or alert waiting to be drawn.
pub const OverlayRequest = @import("overlay_request.zig").OverlayRequest;
/// A selectable paragraph's geometry for one frame.
pub const SelectHit = @import("select_hit.zig").SelectHit;
/// What a `Drawing` paints with.
pub const Pen = @import("pen.zig").Pen;

// -----------------------------------------------------------------------------
// Building, lowering, painting, rendering

/// The build arena, published theme, tokens, viewport, wrap cache and link handler (`BuildScope.shared()`).
pub const BuildScope = @import("build_scope.zig").BuildScope;
/// The theme colors composed constructors read at build time.
pub const BuildTokens = @import("build_tokens.zig").BuildTokens;
/// A cache of wrapped-text and rich-text layouts.
pub const WrapCache = @import("wrap_cache.zig").WrapCache;
/// Builds stack views from tuples or slices of children.
pub const StackBuilder = @import("stack_builder.zig").StackBuilder;
/// The built-in controls' geometry.
pub const ControlMetrics = @import("control_metrics.zig").ControlMetrics;
/// Lowers views to layout nodes.
pub const ViewLowering = @import("view_lowering.zig").ViewLowering;
/// Paints laid-out views.
pub const ViewPainter = @import("view_painter.zig").ViewPainter;
/// Paints the built-in controls.
pub const ControlPainter = @import("control_painter.zig").ControlPainter;
/// Paints the text views.
pub const TextViewPainter = @import("text_view_painter.zig").TextViewPainter;
/// Measures and renders view trees, drawing their overlays.
pub const ViewRenderer = @import("view_renderer.zig").ViewRenderer;
/// A body drawn to pixels with no window, and the pixels encoded as a BMP.
pub const Screenshot = @import("screenshot.zig").Screenshot;
/// What `Screenshot.render` draws: the size, the theme, the frames built first.
pub const ScreenshotOptions = @import("screenshot_options.zig").ScreenshotOptions;
/// A headless frame: fonts and caches, `build` (a view tree to draw commands, settled as a window would), `rasterize` (software); under `Screenshot.render`, and the gallery's `--gpu`.
pub const ScreenshotFrame = @import("screenshot_frame.zig").ScreenshotFrame;

// -----------------------------------------------------------------------------
// Input, focus, selection and time

/// Routes pointer events to a frame's regions (`PointerInput.shared()`).
pub const PointerInput = @import("pointer_input.zig").PointerInput;
/// The keyboard focus and the caret's blink (`Focus.shared()`).
pub const Focus = @import("focus.zig").Focus;
/// The app's millisecond clock and scrollbar fade timing (`FrameClock.shared()`).
pub const FrameClock = @import("frame_clock.zig").FrameClock;
/// The live selection in selectable rich text (`TextSelection.shared()`).
pub const TextSelection = @import("text_selection.zig").TextSelection;
/// A selection's byte range in a selectable view.
pub const SelectionSpan = @import("text_selection.zig").SelectionSpan;
/// The text-field context menu (`TextContextMenu.shared()`).
pub const TextContextMenu = @import("text_context_menu.zig").TextContextMenu;
/// The clipboard the context menu copies to and pastes from.
pub const ClipboardOperations = @import("text_context_menu.zig").ClipboardOperations;

// -----------------------------------------------------------------------------
// From the views module

/// A text field's buffer, caret and selection (from the views module).
pub const TextFieldState = @import("../module.zig").TextFieldState;
/// One styled run of a `RichText` (from the views module).
pub const Span = @import("../module.zig").Span;
/// A laid-out piece of one span on one line (from the views module).
pub const RichRun = @import("../module.zig").RichRun;
/// One laid-out line of a rich paragraph (from the views module).
pub const RichLine = @import("../module.zig").RichLine;
/// A laid-out rich paragraph (from the views module).
pub const RichLayout = @import("../module.zig").RichLayout;
/// The faces a rich paragraph's spans are measured and drawn in (from the views module).
pub const RichFaces = @import("../module.zig").RichFaces;
/// Line and column geometry over a UTF-8 buffer (from the views module).
pub const TextLines = @import("../module.zig").TextLines;
/// Tab-aware widths of edited text (from the views module).
pub const EditorMetrics = @import("../module.zig").EditorMetrics;
/// One line of text (from the views module).
pub const Text = @import("../module.zig").Text;
/// A one-line text field (from the views module).
pub const TextField = @import("../module.zig").TextField;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;
/// Children stacked vertically (from the views module).
pub const VStack = @import("../module.zig").VStack;
/// Flexible space in a stack (from the views module).
pub const Spacer = @import("../module.zig").Spacer;
/// A hairline across a stack (from the views module).
pub const Divider = @import("../module.zig").Divider;
/// A filled rectangle (from the views module).
pub const Rectangle = @import("../module.zig").Rectangle;

// -----------------------------------------------------------------------------
// Test Fixtures

/// A headless frame for the view engine's unit tests.
pub const TestEnvironment = @import("test_environment.zig").TestEnvironment;
/// A headless frame for the unit tests: draws a view, collects its overlays and `onHover` regions, replays taps and pointer moves.
pub const TestCanvas = @import("test_canvas.zig").TestCanvas;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("view.zig");
    _ = @import("kind.zig");
    _ = @import("modifiers.zig");
    _ = @import("frame_specification.zig");
    _ = @import("fill.zig");
    _ = @import("material.zig");
    _ = @import("overlay_style.zig");
    _ = @import("font_token.zig");
    _ = @import("shape_kind.zig");
    _ = @import("callback.zig");
    _ = @import("hover_callback.zig");
    _ = @import("drag_callback.zig");
    _ = @import("scroll_state.zig");
    _ = @import("scroll_region.zig");
    _ = @import("scrollbar.zig");
    _ = @import("context.zig");
    _ = @import("hit_action.zig");
    _ = @import("text_click.zig");
    _ = @import("hit_region.zig");
    _ = @import("hover_region.zig");
    _ = @import("a11y_role.zig");
    _ = @import("a11y_node.zig");
    _ = @import("overlay_request.zig");
    _ = @import("select_hit.zig");
    _ = @import("pen.zig");
    _ = @import("build_scope.zig");
    _ = @import("build_tokens.zig");
    _ = @import("wrap_cache.zig");
    _ = @import("stack_builder.zig");
    _ = @import("control_metrics.zig");
    _ = @import("view_lowering.zig");
    _ = @import("view_painter.zig");
    _ = @import("control_painter.zig");
    _ = @import("text_view_painter.zig");
    _ = @import("view_renderer.zig");
    _ = @import("screenshot.zig");
    _ = @import("screenshot_options.zig");
    _ = @import("screenshot_frame.zig");
    _ = @import("pointer_input.zig");
    _ = @import("focus.zig");
    _ = @import("frame_clock.zig");
    _ = @import("text_selection.zig");
    _ = @import("text_context_menu.zig");
    _ = @import("test_environment.zig");
    _ = @import("accent.zig");
    _ = @import("test_canvas.zig");
}
