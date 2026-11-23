//! The range of data values one axis of a chart (`LineChart`, `BarChart`) spans.

const std = @import("std");
const log = std.log.scoped(.ziggui_chart_domain);

/// The range of data values one axis of a chart spans, as Swift Charts'
/// `.chartXScale(domain:)` / `.chartYScale(domain:)`: each bound given, or
/// taken from the chart's finite values, a `BarChart`'s with zero (a partial
/// range when only one is given, `.{ .lower = 0 }` reading as `0...`). A bound
/// that is not finite counts as not given. A range of no width (one value, or
/// nothing to chart) is widened about its value, out to zero or one unit
/// either side, so a flat series draws across the middle.
pub const ChartDomain = struct {
    const Self = @This();

    /// The least value, at the axis's start (left, or foot); null takes the
    /// series' least.
    lower: ?f32 = null,
    /// The greatest value, at the axis's end (right, or top); null takes the
    /// series' greatest.
    upper: ?f32 = null,
    /// Whether the range is widened to be symmetric about zero (from minus to
    /// plus the larger bound's magnitude), so a positive and a negative series
    /// mirror on one scale.
    symmetric: bool = false,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Plain data: nothing here does I/O to trace.
    _ = log;
}
