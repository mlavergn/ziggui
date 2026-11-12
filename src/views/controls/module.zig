//! The controls: text, shapes, gradients, buttons, switches, sliders,
//! steppers, progress bars, pickers, text fields and editors, labels, images,
//! icons and drawings. View constructors over the view engine in `core/`.

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
/// A segmented picker over a selection binding.
pub const Picker = @import("picker.zig").Picker;
/// A one-line text field.
pub const TextField = @import("text_field.zig").TextField;
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
pub const Drawing = @import("drawing.zig").Drawing;

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
/// A scroll view's app-owned offsets (from the views module).
pub const ScrollState = @import("../module.zig").ScrollState;
/// What a `Drawing` paints with (from the views module).
pub const Pen = @import("../module.zig").Pen;
/// One styled run of a `RichText` (from the views module).
pub const Span = @import("../module.zig").Span;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;

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
    _ = @import("drawing.zig");
}
