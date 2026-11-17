//! What a view is and how it stands, beyond its role: SwiftUI's
//! `AccessibilityTraits`, as `View.accessibilityAddTraits` adds them.

const std = @import("std");
const log = std.log.scoped(.ziggui_accessibility_traits);

/// A view's accessibility traits (SwiftUI's `.isButton`, `.isSelected`): a
/// composed control's parts say what they are, though they are drawn from
/// icons and text.
pub const AccessibilityTraits = struct {
    const Self = @This();

    /// It acts as a button when tapped: its node takes the button role.
    is_button: bool = false,
    /// It is the selected one of a group (a segment, a tab).
    is_selected: bool = false,

    /// These traits and `other`'s together.
    ///
    /// - `self`: the traits.
    /// - `other`: the traits to add.
    /// - Returns: both.
    pub fn with(self: *const Self, other: Self) Self {
        return .{
            .is_button = self.is_button or other.is_button,
            .is_selected = self.is_selected or other.is_selected,
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

test "accessibility traits add up" {
    const button = AccessibilityTraits{ .is_button = true };
    const both = button.with(.{ .is_selected = true });
    try std.testing.expect(both.is_button and both.is_selected);
    try std.testing.expect(!button.with(.{}).is_selected);
}
