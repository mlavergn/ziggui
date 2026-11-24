//! How a checkbox `Toggle` draws its box, set for a subtree with
//! `.checkboxStyle()`.

const std = @import("std");
const log = std.log.scoped(.ziggui_checkbox_style);

/// How a checkbox `Toggle` (`.toggleStyle(.checkbox)`) draws its box,
/// inherited by the subtree of the view that sets it (`.checkboxStyle()`).
/// SwiftUI has no counterpart; it reads as `.buttonBorderShape()` does. The
/// explicit styles look the same under every theme family; their color is the
/// toggle's own `.foregroundStyle()`, else the one each names.
pub const CheckboxStyle = enum {
    const Self = @This();

    /// The theme family's own: the accent with a check while on, the control's
    /// ground and border while off, its corners the theme's.
    automatic,

    /// An outlined, rounded box with the check inside it, both in the label
    /// color; never filled.
    rounded,

    /// An outlined square box in the accent, filled with it while on, the check
    /// in the accent's text color.
    square,

    /// An outlined circle in the accent, filled with it while on, the check in
    /// the accent's text color.
    circular,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
