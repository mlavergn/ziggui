//! The charts: an app's data drawn as views, after Swift Charts. A group of
//! its own over the views (each chart is composed on `Canvas`), so more kinds
//! of chart join the line chart here.

const std = @import("std");
const log = std.log.scoped(.ziggui_charts_module);

/// A line chart of series in data coordinates, drawn into its frame.
pub const LineChart = @import("line_chart.zig").LineChart;
/// One line of a `LineChart`: its points, emphasis and color.
pub const ChartSeries = @import("chart_series.zig").ChartSeries;
/// How strongly a `ChartSeries` is drawn: primary or secondary.
pub const ChartEmphasis = @import("chart_series.zig").ChartEmphasis;
/// The range of data values one axis of a chart spans.
pub const ChartDomain = @import("chart_domain.zig").ChartDomain;
/// How an axis of a chart maps its values: linear or log.
pub const ChartScaleType = @import("chart_scale_type.zig").ChartScaleType;
/// What a `LineChart` shows besides its series: scales, baseline and labels.
pub const LineChartOptions = @import("line_chart_options.zig").LineChartOptions;
/// A bar chart of labelled values, drawn into its frame.
pub const BarChart = @import("bar_chart.zig").BarChart;
/// One bar of a `BarChart`: its label, value and color.
pub const BarMark = @import("bar_mark.zig").BarMark;
/// What a `BarChart` shows besides its bars: its scale, grid, line and caption.
pub const BarChartOptions = @import("bar_chart_options.zig").BarChartOptions;
/// One axis's scale, resolved from its `ChartDomain` and a chart's values
/// (the charts' own; `ziggui` does not export it).
pub const ChartAxis = @import("chart_axis.zig").ChartAxis;
/// The look every chart shares: labels, the plot's ground, its bands (the
/// charts' own; `ziggui` does not export it).
pub const ChartStyle = @import("chart_style.zig").ChartStyle;
/// The charts' test fixture: draws a chart headless and checks what it drew.
pub const ChartProbe = @import("chart_probe.zig").ChartProbe;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("line_chart.zig");
    _ = @import("chart_series.zig");
    _ = @import("chart_domain.zig");
    _ = @import("chart_scale_type.zig");
    _ = @import("line_chart_options.zig");
    _ = @import("bar_chart.zig");
    _ = @import("bar_mark.zig");
    _ = @import("bar_chart_options.zig");
    _ = @import("chart_axis.zig");
    _ = @import("chart_style.zig");
    _ = @import("chart_probe.zig");
}
