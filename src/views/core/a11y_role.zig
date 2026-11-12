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
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
