//! One line of a `LineChart`: its points in data coordinates and how
//! strongly it is drawn.

const std = @import("std");
const log = std.log.scoped(.ziggui_chart_series);
const renderer = @import("renderer");

/// How strongly a `ChartSeries` is drawn.
pub const ChartEmphasis = enum {
    const Self = @This();

    /// The series the chart is about, drawn in full, over the secondary ones.
    primary,
    /// A series shown for comparison, drawn faintly (at 0.35 of its color's
    /// alpha) under the primary ones.
    secondary,
};

/// One line of a `LineChart`, as Swift Charts' `LineMark`s of one series: its
/// points joined in order, left to right, in the chart's data coordinates. A
/// point with a coordinate that is not finite (NaN, an infinity) is skipped
/// and breaks the line there; a point alone between breaks draws as a dot.
pub const ChartSeries = struct {
    const Self = @This();

    /// The points, in order, in data coordinates (x across, y up). The slice
    /// must last until the frame is drawn (the build arena will do).
    points: []const renderer.Point,
    /// How strongly it is drawn.
    emphasis: ChartEmphasis = .primary,
    /// Its color; null for the theme's accent. A secondary series fades it.
    color: ?renderer.Color = null,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Plain data: nothing here does I/O to trace.
    _ = log;
}
