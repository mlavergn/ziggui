//! What a `LineChart` shows besides its series: its scales (linear or log), a
//! baseline and its labels.

const std = @import("std");
const log = std.log.scoped(.ziggui_line_chart_options);
const mod = @import("module.zig");

/// What a `LineChart` shows besides its series. Every field has a default:
/// `.{}` is a chart scaled to its data with no baseline and no labels.
pub const LineChartOptions = struct {
    const Self = @This();

    /// The x axis's range (`.chartXScale(domain:)`); by default the series'.
    x_domain: mod.ChartDomain = .{},
    /// The y axis's range (`.chartYScale(domain:)`); by default the series'
    /// and the baseline's.
    y_domain: mod.ChartDomain = .{},
    /// How the y axis maps values (`.chartYScale(type:)`): linear, or a log
    /// scale on which only positive values draw (and a baseline at or below
    /// zero is not drawn).
    y_scale_type: mod.ChartScaleType = .linear,
    /// Where a horizontal reference line crosses the y axis, as Swift Charts'
    /// `RuleMark(y:)`, drawn in the separator color under the series; null for
    /// none. A baseline outside the y range is not drawn.
    baseline: ?f32 = null,
    /// A caption over the plot, at its top-left, giving its scale (`±2.14 %`);
    /// empty for none, which gives its room to the plot.
    caption: []const u8 = "",
    /// The label under the plot at the x axis's start (left); empty for none.
    x_start_label: []const u8 = "",
    /// The label under the plot at the x axis's end (right); empty for none.
    /// With neither end labelled, the plot takes their room.
    x_end_label: []const u8 = "",
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Plain data: nothing here does I/O to trace.
    _ = log;
}
