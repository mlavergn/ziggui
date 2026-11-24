//! The controls: text, shapes, gradients, buttons, switches, sliders,
//! steppers, progress bars, pickers, segmented controls, text fields and
//! editors, labels, badges, key caps, images, icons and drawings. View
//! constructors over the view engine in `core/`.

const std = @import("std");
const log = std.log.scoped(.ziggui_controls_module);

/// One line of text.
pub const Text = @import("text.zig").Text;
/// Text that wraps to the width it is given.
pub const WrappedText = @import("text.zig").WrappedText;
/// A wrapped paragraph of styled spans.
pub const RichText = @import("text.zig").RichText;
/// Preformatted spans: leading spaces survive and lines do not wrap.
pub const RichTextPreformatted = @import("text.zig").RichTextPreformatted;
/// A wrapped paragraph of styled spans at a given line height.
pub const RichTextSpaced = @import("text.zig").RichTextSpaced;
/// One line of text with runs of it marked, as search results mark a match.
pub const HighlightedText = @import("text.zig").HighlightedText;
/// A filled rectangle.
pub const Rectangle = @import("shapes.zig").Rectangle;
/// A filled rounded rectangle.
pub const RoundedRectangle = @import("shapes.zig").RoundedRectangle;
/// A filled circle.
pub const Circle = @import("shapes.zig").Circle;
/// A filled capsule.
pub const Capsule = @import("shapes.zig").Capsule;
/// A filled ellipse.
pub const Ellipse = @import("shapes.zig").Ellipse;
/// A gradient that fills its frame.
pub const LinearGradient = @import("linear_gradient.zig").LinearGradient;
/// Three bouncing dots.
pub const LoadingDots = @import("loading_dots.zig").LoadingDots;
/// A ring of dots turning: a small indeterminate busy mark.
pub const Spinner = @import("spinner.zig").Spinner;
/// A push button.
pub const Button = @import("button.zig").Button;
/// A push button with a role.
pub const ButtonRoled = @import("button.zig").ButtonRoled;
/// A push button with a leading glyph.
pub const ButtonIcon = @import("button.zig").ButtonIcon;
/// A push button with a leading glyph and a role.
pub const ButtonIconRoled = @import("button.zig").ButtonIconRoled;
/// A switch over a `Binding(bool)`.
pub const Toggle = @import("toggle.zig").Toggle;
/// A slider over a range.
pub const Slider = @import("slider.zig").Slider;
/// A stepper over a range.
pub const Stepper = @import("stepper.zig").Stepper;
/// A progress bar.
pub const ProgressView = @import("progress_view.zig").ProgressView;
/// A picker over a selection binding: segmented or a pop-up menu.
pub const Picker = @import("picker.zig").Picker;
/// A one-line text field.
pub const TextField = @import("text_field.zig").TextField;
/// A one-line field that shows dots instead of its text.
pub const SecureField = @import("text_field.zig").SecureField;
/// A multi-line text editor.
pub const TextEditor = @import("text_editor.zig").TextEditor;
/// A title behind a color swatch.
pub const Label = @import("label.zig").Label;
/// An image of RGBA pixels.
pub const Image = @import("image.zig").Image;
/// A glyph from the icon font.
pub const Icon = @import("icon.zig").Icon;
/// A borderless tappable glyph.
pub const IconButton = @import("icon.zig").IconButton;
/// A view that paints itself through a callback.
pub const Canvas = @import("canvas.zig").Canvas;
/// A picture that zooms and pans, with an overlay drawn through its geometry.
pub const ZoomableImage = @import("zoomable_image.zig").ZoomableImage;
/// The picture a `ZoomableImage` shows.
pub const ZoomPicture = @import("zoomable_image.zig").ZoomPicture;
/// An app-owned 3D scene, drawn on the GPU.
pub const SceneView = @import("scene_view.zig").SceneView;
/// A push button with its keyboard shortcut in a key cap after the label.
pub const ButtonKeyed = @import("button.zig").ButtonKeyed;
/// What a `Badge` says: its soft ground and strong text (`ground`, `text`).
pub const BadgeTone = @import("badge.zig").BadgeTone;
/// A short label on a soft ground in its tone's strong color.
pub const Badge = @import("badge.zig").Badge;
/// A keyboard key's glyph in a small cap.
pub const KeyCap = @import("key_cap.zig").KeyCap;
/// A segmented control of equal segments, a neutral thumb on a track.
pub const SegmentedControl = @import("segmented_control.zig").SegmentedControl;
/// A segmented control of icons, each segment a Lucide icon with a title.
pub const IconSegmentedControl = @import("segmented_control.zig").IconSegmentedControl;
/// One segment of an `IconSegmentedControl`: its icon and title.
pub const IconSegment = @import("icon_segment.zig").IconSegment;
/// An app's appearance setting: follow the system, light or dark.
pub const Appearance = @import("appearance.zig").Appearance;
/// A settings page's appearance choice: Auto, Light and Dark as little windows.
pub const AppearancePicker = @import("appearance_picker.zig").AppearancePicker;
/// A settings page's theme choice: a little window per theme family, then the accent swatches.
pub const ThemePicker = @import("theme_picker.zig").ThemePicker;
/// A color picker: a title and a row of swatches.
pub const ColorPicker = @import("color_picker.zig").ColorPicker;
/// An editor's settings as one plain value an app keeps and saves.
pub const TextEditorSettings = @import("text_editor_settings.zig").TextEditorSettings;
/// The theme families alone, as mini renderings with their names as hover hints.
pub const ThemeFamilyPicker = @import("theme_picker.zig").ThemeFamilyPicker;
/// The frame both settings pickers draw a choice in (internal to the controls).
pub const ThumbnailChoice = @import("thumbnail_choice.zig").ThumbnailChoice;
/// A label renamed in place: a click while it is selected makes it a field.
pub const EditableText = @import("editable_text.zig").EditableText;
/// An `EditableText`'s text, edit and armed click; app-owned.
pub const EditableTextState = @import("editable_text_state.zig").EditableTextState;

/// A node of the view tree (from the views module).
pub const View = @import("../module.zig").View;
/// The build arena and published theme (from the views module).
pub const BuildScope = @import("../module.zig").BuildScope;
/// A tap handler (from the views module).
pub const Callback = @import("../module.zig").Callback;
/// A read/write handle on a `State` (from the views module).
pub const Binding = @import("../module.zig").Binding;
/// A button's semantic appearance (from the views module).
pub const ButtonRole = @import("../module.zig").ButtonRole;
/// A text field's buffer, caret and selection (from the views module).
pub const TextFieldState = @import("../module.zig").TextFieldState;
/// Line and character stepping over UTF-8 text (from the views module).
pub const TextLines = @import("../module.zig").TextLines;
/// A scroll view's app-owned offsets (from the views module).
pub const ScrollState = @import("../module.zig").ScrollState;
/// The colors a `TextEditor` draws its caret, selection, gutter and matches in (from the views module).
pub const TextEditorColors = @import("../module.zig").TextEditorColors;
/// How an editor indents (from the views module).
pub const TextIndentation = @import("../module.zig").TextIndentation;
/// What Tab inserts (from the views module).
pub const IndentationStyle = @import("../module.zig").IndentationStyle;
/// How a document's lines end on disk (from the views module).
pub const LineEnding = @import("../module.zig").LineEnding;
/// A family by name at a size (from the views module).
pub const CustomFont = @import("../module.zig").CustomFont;
/// What a `Canvas` draws with (from the views module).
pub const GraphicsContext = @import("../module.zig").GraphicsContext;
/// A view's text style token (from the views module).
pub const FontToken = @import("../module.zig").FontToken;
/// An app's accent color, a setting (from the views module).
pub const Accent = @import("../module.zig").Accent;
/// Markers a `Canvas` draws over a picture (from the views module).
pub const CanvasMarkers = @import("../module.zig").CanvasMarkers;
/// A `ZoomableImage`'s zoom and pan (from the views module).
pub const ZoomState = @import("../module.zig").ZoomState;
/// How a `SceneView` draws its scene (from the views module).
pub const SceneViewOptions = @import("../module.zig").SceneViewOptions;
/// A zoomed picture's layout (from the views module).
pub const ZoomGeometry = @import("../module.zig").ZoomGeometry;
/// One styled run of a `RichText` (from the views module).
pub const Span = @import("../module.zig").Span;
/// A run of a text's bytes, as `HighlightedText` marks them (from the views module).
pub const TextRange = @import("../module.zig").TextRange;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;
/// Flexible space in a stack (from the views module).
pub const Spacer = @import("../module.zig").Spacer;
/// Builds stack views from tuples or slices (from the views module).
pub const StackBuilder = @import("../module.zig").StackBuilder;
/// The build-time theme colors (from the views module).
pub const BuildTokens = @import("../module.zig").BuildTokens;
/// The built-in controls' geometry (from the views module).
pub const ControlMetrics = @import("../module.zig").ControlMetrics;
/// How a checkbox `Toggle` draws its box (from the views module).
pub const CheckboxStyle = @import("../module.zig").CheckboxStyle;
/// The keyboard focus (from the views module).
pub const Focus = @import("../module.zig").Focus;
/// The frame time and frame requests (from the views module).
pub const FrameClock = @import("../module.zig").FrameClock;
/// Taps, drags and click counts (from the views module).
pub const PointerInput = @import("../module.zig").PointerInput;
/// SDL3 keycodes and modifier bits as named constants (from the views module).
pub const SdlKey = @import("../module.zig").SdlKey;
/// A headless window for the unit tests (from the views module).
pub const TestWindow = @import("../module.zig").TestWindow;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("text.zig");
    _ = @import("shapes.zig");
    _ = @import("linear_gradient.zig");
    _ = @import("loading_dots.zig");
    _ = @import("spinner.zig");
    _ = @import("button.zig");
    _ = @import("toggle.zig");
    _ = @import("slider.zig");
    _ = @import("stepper.zig");
    _ = @import("progress_view.zig");
    _ = @import("picker.zig");
    _ = @import("text_field.zig");
    _ = @import("text_editor.zig");
    _ = @import("label.zig");
    _ = @import("image.zig");
    _ = @import("icon.zig");
    _ = @import("canvas.zig");
    _ = @import("zoomable_image.zig");
    _ = @import("scene_view.zig");
    _ = @import("badge.zig");
    _ = @import("key_cap.zig");
    _ = @import("segmented_control.zig");
    _ = @import("appearance.zig");
    _ = @import("appearance_picker.zig");
    _ = @import("theme_picker.zig");
    _ = @import("color_picker.zig");
    _ = @import("text_editor_settings.zig");
    _ = @import("thumbnail_choice.zig");
    _ = @import("editable_text.zig");
    _ = @import("editable_text_state.zig");
}
