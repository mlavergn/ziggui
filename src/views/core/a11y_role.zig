//! The accessibility roles a control maps to.

const std = @import("std");
const log = std.log.scoped(.ziggui_a11y_role);

/// An accessibility role, mirroring the platform a11y roles a control maps to.
pub const A11yRole = enum {
    const Self = @This();

    /// Static text.
    staticText,
    /// A push button.
    button,
    /// An on/off switch.
    toggle,
    /// A slider.
    slider,
    /// An editable text field.
    textField,
    /// An image or glyph.
    image,
    /// A heading.
    header,
    /// A pop-up button: a menu-style picker, its value the chosen option.
    popUpButton,
    /// A set of choices of which one is chosen: a segmented picker, its value
    /// the chosen option, its segments the `radioButton`s after it.
    radioGroup,
    /// One choice of a `radioGroup`: a segment, `selected` while chosen.
    radioButton,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
