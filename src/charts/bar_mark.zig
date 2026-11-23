//! One bar of a `BarChart`: its label, value and color.

const std = @import("std");
const log = std.log.scoped(.ziggui_bar_mark);
const renderer = @import("renderer");

/// One bar of a `BarChart`, as Swift Charts' `BarMark`: a value drawn as a
/// bar from zero in its own slot, its label under it. A value that is not
/// finite draws no bar and breaks the chart's line there.
pub const BarMark = struct {
    const Self = @This();

    /// The label under the bar (a category: "Mon"); empty for none. The slice
    /// must last until the frame is drawn (the build arena will do).
    label: []const u8 = "",
    /// The bar's value, from zero (up when positive, down when negative).
    value: f32,
    /// The bar's color, drawn as given; null for the theme's accent at
    /// `BarChart`'s bar opacity (0.45), so the chart's line reads over it.
    color: ?renderer.Color = null,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Plain data: nothing here does I/O to trace.
    _ = log;
}
