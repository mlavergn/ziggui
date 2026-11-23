//! One axis's scale: the range of data values it spans, resolved from its
//! `ChartDomain` and the values a chart holds.

const std = @import("std");
const log = std.log.scoped(.ziggui_chart_axis);
const mod = @import("module.zig");

/// One axis's scale: the range of data values it spans, resolved from its
/// `ChartDomain` and the values a chart holds; every chart here shares it.
/// In `f64`, so no finite `f32` value or range overflows on its way to the
/// plot.
pub const ChartAxis = struct {
    const Self = @This();

    /// The value at the axis's start.
    lower: f64,
    /// The value at the axis's end, always greater than `lower`.
    upper: f64,

    /// An axis from its domain and what the chart holds along it.
    ///
    /// - `domain`: the bounds given, if any.
    /// - `found_lower`: the least finite value along the axis; NaN for none.
    /// - `found_upper`: the greatest finite value along the axis; NaN for none.
    /// - Returns: the axis, finite and wider than nothing.
    pub fn init(domain: mod.ChartDomain, found_lower: f64, found_upper: f64) Self {
        var lower = Self.finite(domain.lower) orelse found_lower;
        var upper = Self.finite(domain.upper) orelse found_upper;
        if (std.math.isNan(lower) and std.math.isNan(upper)) {
            // Nothing to chart and nothing given: the unit range.
            lower = 0;
            upper = 1;
        }
        if (std.math.isNan(lower)) lower = upper;
        if (std.math.isNan(upper)) upper = lower;
        if (upper < lower) std.mem.swap(f64, &lower, &upper);
        if (domain.symmetric) {
            const reach = @max(@abs(lower), @abs(upper));
            lower = -reach;
            upper = reach;
        }
        if (!(upper > lower)) {
            // No width: about the value, out to zero or one unit either side.
            const centre = lower;
            const half = @max(1, @abs(centre));
            lower = centre - half;
            upper = centre + half;
        }
        const self = Self{ .lower = lower, .upper = upper };
        return self;
    }

    /// How far along the axis a value lies.
    ///
    /// - `self`: the axis.
    /// - `value`: the data value.
    /// - Returns: 0 at `lower`, 1 at `upper`, beyond either outside them.
    pub fn fraction(self: *const Self, value: f32) f64 {
        return (@as(f64, value) - self.lower) / (self.upper - self.lower);
    }

    /// Reports whether a value lies on the axis, its ends included.
    ///
    /// - `self`: the axis.
    /// - `value`: the data value.
    /// - Returns: true when it lies between `lower` and `upper`.
    pub fn contains(self: *const Self, value: f32) bool {
        return value >= self.lower and value <= self.upper;
    }

    /// A bound that counts as given.
    ///
    /// - `bound`: the bound, if any.
    /// - Returns: the bound, or null when it is absent or not finite.
    fn finite(bound: ?f32) ?f64 {
        const value = bound orelse return null;
        return if (std.math.isFinite(value)) value else null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a chart axis takes its range from its bounds, else the data" {
    const nan = std.math.nan(f64);
    // Nothing given: the data's range.
    const data = ChartAxis.init(.{}, -2, 3);
    try std.testing.expectEqual(-2, data.lower);
    try std.testing.expectEqual(3, data.upper);
    // Symmetric about zero, out to the larger magnitude.
    const symmetric = ChartAxis.init(.{ .symmetric = true }, -0.5, 2);
    try std.testing.expectEqual(-2, symmetric.lower);
    try std.testing.expectEqual(2, symmetric.upper);
    // One bound given: a partial range; a bound that is not finite counts as none.
    const partial = ChartAxis.init(.{ .lower = 0, .upper = std.math.inf(f32) }, 4, 9);
    try std.testing.expectEqual(0, partial.lower);
    try std.testing.expectEqual(9, partial.upper);
    // Bounds given the wrong way round are put right.
    const inverted = ChartAxis.init(.{ .lower = 1, .upper = -1 }, nan, nan);
    try std.testing.expectEqual(-1, inverted.lower);
    try std.testing.expectEqual(1, inverted.upper);
    // Nothing to chart: the unit range, or symmetric about zero.
    const empty = ChartAxis.init(.{}, nan, nan);
    try std.testing.expectEqual(0, empty.lower);
    try std.testing.expectEqual(1, empty.upper);
    const empty_symmetric = ChartAxis.init(.{ .symmetric = true }, nan, nan);
    try std.testing.expectEqual(-1, empty_symmetric.lower);
    try std.testing.expectEqual(1, empty_symmetric.upper);
    // No width: out to zero (or a unit) either side of the value.
    const flat = ChartAxis.init(.{}, 5, 5);
    try std.testing.expectEqual(0, flat.lower);
    try std.testing.expectEqual(10, flat.upper);
    const zero = ChartAxis.init(.{}, 0, 0);
    try std.testing.expectEqual(-1, zero.lower);
    try std.testing.expectEqual(1, zero.upper);
    // The largest finite range stays finite.
    const widest = ChartAxis.init(.{}, -std.math.floatMax(f32), std.math.floatMax(f32));
    try std.testing.expect(std.math.isFinite(widest.fraction(std.math.floatMax(f32))));
}
