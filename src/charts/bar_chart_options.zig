//! What a `BarChart` shows besides its bars: its scale, a grid, a line
//! through the bars' tops and a caption.

const std = @import("std");
const log = std.log.scoped(.ziggui_bar_chart_options);
const mod = @import("module.zig");

/// What a `BarChart` shows besides its bars. Every field has a default:
/// `.{}` is bars scaled to their values and zero, with no grid, line or
/// caption.
pub const BarChartOptions = struct {
    const Self = @This();

    /// The value axis's range (`.chartYScale(domain:)`); by default the bars'
    /// values and zero, so every bar grows from zero. A bar past a given range
    /// stops at the plot's edge.
    y_domain: mod.ChartDomain = .{},
    /// How many equal bands horizontal grid lines rule the plot into, as Swift
    /// Charts' `AxisMarks` grid: 4 draws a line at the plot's top, its foot and
    /// three between; 0 for none.
    grid_divisions: u8 = 0,
    /// Whether a line runs through the bars' ends with a dot on each, as a
    /// `LineMark` and `PointMark` over the `BarMark`s, in the accent.
    overlay_line: bool = false,
    /// A caption over the plot, at its top-left (`Steps, thousands`); empty
    /// for none, which gives its room to the plot.
    caption: []const u8 = "",
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Plain data: nothing here does I/O to trace.
    _ = log;
}
