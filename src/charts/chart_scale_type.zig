//! How an axis of a chart maps its values onto the plot: evenly, or by
//! decades.

const std = @import("std");
const log = std.log.scoped(.ziggui_chart_scale_type);

/// How an axis of a chart maps its values onto the plot, as Swift Charts'
/// `ScaleType` (`.chartYScale(type:)`).
pub const ChartScaleType = enum {
    const Self = @This();

    /// Equal steps of value take equal room: the default.
    linear,
    /// Equal ratios of value take equal room (base 10), so a value that falls
    /// across decades, a training loss, stays readable. Only positive values
    /// draw: a point at or below zero breaks the line, as a NaN does.
    log,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
