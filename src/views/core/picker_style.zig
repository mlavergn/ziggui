//! How a `Picker` draws (SwiftUI's `PickerStyle`), set for a subtree with
//! `.pickerStyle()`.

const std = @import("std");
const log = std.log.scoped(.ziggui_picker_style);

/// How a `Picker` draws, as SwiftUI's `PickerStyle`: inherited by the subtree
/// of the view that sets it (`.pickerStyle()`).
pub const PickerStyle = enum {
    const Self = @This();

    /// A pop-up menu inside a `Form`, as macOS draws settings; segmented elsewhere.
    automatic,

    /// Every option side by side, the chosen one highlighted.
    segmented,

    /// A pop-up button showing the chosen option; a tap shows every option
    /// in a menu, the chosen one checked and laid over the button (macOS's
    /// `NSPopUpButton`).
    menu,

    /// The style an `.automatic` picker takes.
    ///
    /// - `self`: the style asked for.
    /// - `in_form`: whether the picker is inside a `Form`.
    /// - Returns: `.segmented` or `.menu`.
    pub fn resolved(self: *const Self, in_form: bool) Self {
        return switch (self.*) {
            .automatic => if (in_form) .menu else .segmented,
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

test "an automatic picker is a menu in a form and segmented elsewhere" {
    try std.testing.expectEqual(PickerStyle.menu, PickerStyle.automatic.resolved(true));
    try std.testing.expectEqual(PickerStyle.segmented, PickerStyle.automatic.resolved(false));
    try std.testing.expectEqual(PickerStyle.menu, PickerStyle.menu.resolved(false));
    try std.testing.expectEqual(PickerStyle.segmented, PickerStyle.segmented.resolved(true));
}
