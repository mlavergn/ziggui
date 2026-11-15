//! A yes-or-no question an app asks, which `ConfirmAlert` draws.

const std = @import("std");
const log = std.log.scoped(.ziggui_confirm);
const mod = @import("module.zig");

/// A question an app asks before something it cannot undo.
pub const Confirm = struct {
    const Self = @This();

    /// The question; in the app's modal memory.
    title: []const u8,
    /// A second line, or empty; in the app's modal memory.
    detail: []const u8 = "",
    /// The button that agrees ("Delete", "Discard").
    yes_label: []const u8,
    /// Whether agreeing destroys something: the agreeing button is drawn
    /// destructive, else prominent (a restart, a retry).
    destructive: bool = true,
    /// What agreeing does. The app closes the question before calling it
    /// (`ConfirmAlert`'s `on_yes`), so it runs once and never under the open question.
    on_yes: mod.Callback,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
