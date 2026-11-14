//! What a `View` is: its content, one variant per kind of view, and each
//! variant's payload.

const std = @import("std");
const log = std.log.scoped(.ziggui_kind);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A one-line `Text`.
pub const TextData = struct {
    const Self = @This();

    /// The text.
    string: []const u8,
};

/// A `WrappedText` paragraph.
pub const WrappedTextData = struct {
    const Self = @This();

    /// The text.
    string: []const u8,
};

/// A `RichText` paragraph of styled spans.
pub const RichTextData = struct {
    const Self = @This();

    /// The spans, in the build arena.
    spans: []const mod.Span,

    /// Line height as a multiple of the font size.
    line_multiple: f32 = 1.25,

    /// Preformatted: leading spaces survive and lines do not wrap.
    preformatted: bool = false,
};

/// A `Spacer`.
pub const SpacerData = struct {
    const Self = @This();

    /// The least length it takes along its stack.
    min_length: f32 = 0,
};

/// A filled shape.
pub const ShapeData = struct {
    const Self = @This();

    /// The outline.
    shape: mod.ShapeKind,

    /// A rounded rectangle's corner radius.
    corner_radius: f32 = 0,

    /// What it is filled with.
    fill: mod.Fill,
};

/// A stack of children.
pub const StackData = struct {
    const Self = @This();

    /// Vertical, horizontal or layered.
    direction: renderer.Direction,

    /// Space between children.
    spacing: f32,

    /// Cross-axis alignment.
    alignment: renderer.Alignment,

    /// The children, groups already spliced in.
    children: []const mod.View,
};

/// A push button.
pub const ButtonData = struct {
    const Self = @This();

    /// The title.
    label: []const u8,

    /// What a tap calls.
    action: mod.Callback,

    /// Its semantic appearance.
    role: mod.ButtonRole = .normal,

    /// Optional leading glyph (the native `Label("…", systemImage:)` button).
    icon: ?renderer.Icon = null,

    /// Optional keyboard shortcut drawn as a key cap after the label
    /// (`ButtonKeyed`: "Save ↩", "Cancel esc").
    shortcut: ?[]const u8 = null,
};

/// A switch.
pub const ToggleData = struct {
    const Self = @This();

    /// The state it shows and flips.
    value: mod.Binding(bool),

    /// The label on its leading edge.
    label: []const u8 = "",
};

/// A slider.
pub const SliderData = struct {
    const Self = @This();

    /// The value it shows and sets.
    value: mod.Binding(f32),

    /// The value at the leading end.
    min: f32 = 0,

    /// The value at the trailing end.
    max: f32 = 1,
};

/// A stepper.
pub const StepperData = struct {
    const Self = @This();

    /// The value it steps.
    value: mod.Binding(i64),

    /// The label on its leading edge.
    label: []const u8 = "",

    /// The least value.
    min: i64 = std.math.minInt(i64),

    /// The greatest value.
    max: i64 = std.math.maxInt(i64),

    /// How far one press moves the value.
    step: i64 = 1,
};

/// A progress bar.
pub const ProgressData = struct {
    const Self = @This();

    /// How far along, 0 to 1.
    value: f32 = 0,

    /// An optional label.
    label: []const u8 = "",
};

/// An image.
pub const ImageData = struct {
    const Self = @This();

    /// The pixels.
    image: renderer.Image,
};

/// A title behind a small color swatch.
pub const LabelData = struct {
    const Self = @This();

    /// The title.
    title: []const u8,

    /// The swatch's color.
    symbol_color: renderer.Color,
};

/// A glyph from the bundled icon font, tinted `color` (null = inherit the
/// environment's foreground) and laid out as a `size`×`size` square.
pub const IconData = struct {
    const Self = @This();

    /// The glyph.
    icon: renderer.Icon,

    /// The square's side.
    size: f32,

    /// The tint; null inherits the foreground.
    color: ?renderer.Color = null,
};

/// A tappable icon: the glyph centered in a square control with a tap callback.
pub const IconButtonData = struct {
    const Self = @This();

    /// The glyph.
    icon: renderer.Icon,

    /// The glyph's side.
    size: f32,

    /// What a tap calls.
    action: mod.Callback,
};

/// A scroll view at a fixed offset.
pub const ScrollData = struct {
    const Self = @This();

    /// The direction it scrolls.
    axis: renderer.Direction,

    /// How far the content is scrolled.
    offset: f32,

    /// What scrolls, in the build arena.
    content: *const mod.View,
};

/// A one-line text field.
pub const TextFieldData = struct {
    const Self = @This();

    /// The field's buffer, caret and selection.
    state: *mod.TextFieldState,

    /// The hint shown while it is empty.
    placeholder: []const u8 = "",
};

/// A multi-line, scrollable text editor over a `TextFieldState` (buffer/caret/
/// selection) with vertical scroll in an app-owned `ScrollState`.
pub const TextEditorData = struct {
    const Self = @This();

    /// The editor's buffer, caret and selection.
    state: *mod.TextFieldState,

    /// Its vertical scroll.
    scroll: *mod.ScrollState,

    /// Whether a line-number gutter shows.
    line_numbers: bool = true,
};

/// A scroll view whose offset lives in an app-owned `ScrollState`.
pub const ScrollStateData = struct {
    const Self = @This();

    /// The offsets and extents.
    state: *mod.ScrollState,

    /// What scrolls, in the build arena.
    content: *const mod.View,

    /// The content is laid out at its own width and scrolls sideways too
    /// (`ScrollViewStateBoth`).
    horizontal: bool = false,
};

/// A `GeometryReader`'s content builder and its context.
pub const GeometryData = struct {
    const Self = @This();

    /// What `build` gets back.
    context: *const anyopaque,

    /// Builds the content for the size the reader is laid out at.
    build: *const fn (context: *const anyopaque, size: renderer.Size) mod.View,
};

/// A segmented picker.
pub const PickerData = struct {
    const Self = @This();

    /// The selected segment's index.
    selection: mod.Binding(i64),

    /// The segments' titles.
    options: []const []const u8,
};

/// A view that paints itself through a callback (see `Drawing`).
pub const DrawingData = struct {
    const Self = @This();

    /// What `draw` gets back.
    context: *const anyopaque,

    /// Paints the view into its frame.
    draw: *const fn (context: *const anyopaque, pen: *mod.Pen, rect: renderer.Rect) std.mem.Allocator.Error!void,
};

/// What a view is.
pub const Kind = union(enum) {
    const Self = @This();

    /// Nothing.
    empty,
    /// One line of text.
    text: TextData,
    /// Multi-line text that word-wraps to the proposed width (height grows with
    /// the number of wrapped lines). Lowered to a measured node.
    wrappedText: WrappedTextData,
    /// Inline-styled wrapped paragraph (markdown prose).
    richText: RichTextData,
    /// Flexible space in a stack.
    spacer: SpacerData,
    /// A horizontal hairline.
    divider,
    /// A vertical hairline (rigid narrow width, fills the cross-axis height) —
    /// the HStack counterpart to `divider`, used to separate side-by-side panes.
    verticalDivider,
    /// A filled shape.
    shape: ShapeData,
    /// A stack of children.
    stack: StackData,
    /// A push button.
    button: ButtonData,
    /// A switch.
    toggle: ToggleData,
    /// A slider.
    slider: SliderData,
    /// A stepper.
    stepper: StepperData,
    /// A progress bar.
    progress: ProgressData,
    /// An image.
    image: ImageData,
    /// A glyph from the icon font.
    icon: IconData,
    /// A tappable glyph.
    iconButton: IconButtonData,
    /// A title behind a swatch.
    label: LabelData,
    /// A scroll view at a fixed offset.
    scroll: ScrollData,
    /// A vertical scroll view whose offset lives in an app-owned `ScrollState`
    /// (so it can be wheel-driven and auto-followed), unlike `scroll`'s static
    /// offset.
    scrollState: ScrollStateData,
    /// Content built from the size it is laid out at (see `GeometryReader`);
    /// fills the space it is offered.
    geometry: GeometryData,
    /// A one-line text field.
    textField: TextFieldData,
    /// A multi-line editor (see `TextEditorData`). Reuses `TextFieldState`, so it
    /// shares the focus/keyboard plumbing with `textField`.
    textEditor: TextEditorData,
    /// A segmented picker.
    picker: PickerData,
    /// A view that paints itself through a callback (see `Drawing`).
    drawing: DrawingData,
    /// A transparent container whose children are spliced into the enclosing
    /// stack (used by `ForEach`).
    group: []const mod.View,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
