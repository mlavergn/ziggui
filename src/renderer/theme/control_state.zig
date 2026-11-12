//! The interaction state of a control.

const std = @import("std");
const log = std.log.scoped(.ziggui_control_state);

/// The interaction state of a control, passed to painter functions so a theme
/// can render pressed/hovered/focused/disabled variants.
pub const ControlState = struct {
    const Self = @This();

    /// The pointer is down on the control.
    pressed: bool = false,
    /// The pointer rests over the control.
    hovered: bool = false,
    /// The control has keyboard focus.
    focused: bool = false,
    /// The control is inert.
    disabled: bool = false,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
