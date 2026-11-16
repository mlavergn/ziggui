//! How a `Toggle` draws (SwiftUI's `ToggleStyle`), set for a subtree with
//! `.toggleStyle()`.

const std = @import("std");
const log = std.log.scoped(.ziggui_toggle_style);

/// How a `Toggle` draws, as SwiftUI's `ToggleStyle`: inherited by the subtree
/// of the view that sets it (`.toggleStyle()`).
pub const ToggleStyle = enum {
    const Self = @This();

    /// A checkbox inside a `Form`, as macOS draws settings; a switch elsewhere.
    automatic,

    /// A switch on the trailing edge, the label on the leading one.
    @"switch",

    /// A box before the label, a check mark in it while on.
    checkbox,

    /// The style an `.automatic` toggle takes.
    ///
    /// - `self`: the style asked for.
    /// - `in_form`: whether the toggle is inside a `Form`.
    /// - Returns: `.switch` or `.checkbox`.
    pub fn resolved(self: *const Self, in_form: bool) Self {
        return switch (self.*) {
            .automatic => if (in_form) .checkbox else .@"switch",
            else => self.*,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "an automatic toggle is a checkbox in a form and a switch elsewhere" {
    try std.testing.expectEqual(ToggleStyle.checkbox, ToggleStyle.automatic.resolved(true));
    try std.testing.expectEqual(ToggleStyle.@"switch", ToggleStyle.automatic.resolved(false));
    try std.testing.expectEqual(ToggleStyle.checkbox, ToggleStyle.checkbox.resolved(false));
}
