//! Whether a scroll view draws its scrollbars (SwiftUI's
//! `ScrollIndicatorVisibility`), set for a subtree with `.scrollIndicators()`.

const std = @import("std");
const log = std.log.scoped(.ziggui_scroll_indicator_visibility);

/// Whether a scroll view draws its scrollbars, as SwiftUI's
/// `ScrollIndicatorVisibility`: inherited by the subtree of the view that sets
/// it (`.scrollIndicators()`). A bar shows only while its content overflows.
pub const ScrollIndicatorVisibility = enum {
    const Self = @This();

    /// Overlay bars: shown briefly after a scroll, or while the pointer is
    /// over their edge, then faded out.
    automatic,

    /// Always shown while the content overflows, headless included.
    visible,

    /// Not drawn, and its edge takes no press: the content's own taps reach
    /// the edge. The content still scrolls by wheel and by code.
    hidden,

    /// Whether a bar draws, and its edge strip takes presses.
    ///
    /// - `self`: the visibility.
    /// - Returns: false for `.hidden`.
    pub fn draws(self: *const Self) bool {
        return self.* != .hidden;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "hidden scroll indicators draw nothing" {
    try std.testing.expect(ScrollIndicatorVisibility.automatic.draws());
    try std.testing.expect(ScrollIndicatorVisibility.visible.draws());
    try std.testing.expect(!ScrollIndicatorVisibility.hidden.draws());
}
