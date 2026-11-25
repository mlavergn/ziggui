//! One axis's scale: the range of data values it spans, resolved from its
//! `ChartDomain` and the values a chart holds.

const std = @import("std");
const log = std.log.scoped(.ziggui_chart_axis);
const mod = @import("module.zig");

/// One axis's scale: the range of data values it spans, resolved from its
/// `ChartDomain` and the values a chart holds; every chart here shares it.
/// In `f64`, so no finite `f32` value or range overflows on its way to the
/// plot. On a log scale its range is held in decades (`log10` of the values).
pub const ChartAxis = struct {
    const Self = @This();

    /// The value at the axis's start, in the scale's units (a decade on a log scale).
    lower: f64,
    /// The value at the axis's end, always greater than `lower`.
    upper: f64,
    /// How values map onto the axis.
    scale_type: mod.ChartScaleType = .linear,

    /// A linear axis from its domain and what the chart holds along it.
    ///
    /// - `domain`: the bounds given, if any.
    /// - `found_lower`: the least finite value along the axis; NaN for none.
    /// - `found_upper`: the greatest finite value along the axis; NaN for none.
    /// - Returns: the axis, finite and wider than nothing.
    pub fn init(domain: mod.ChartDomain, found_lower: f64, found_upper: f64) Self {
        return Self.initScaled(domain, .linear, found_lower, found_upper);
    }

    /// An axis of either scale from its domain and what the chart holds
    /// along it. On a log scale a bound at or below zero counts as not given,
    /// `symmetric` is ignored, a range of no width widens by a decade either
    /// side, and nothing to chart spans 1 to 10.
    ///
    /// - `domain`: the bounds given, if any.
    /// - `scale_type`: how values map onto the axis.
    /// - `found_lower`: the least value along the axis that can draw on this
    ///   scale (finite, and positive on a log scale); NaN for none.
    /// - `found_upper`: the greatest such value; NaN for none.
    /// - Returns: the axis, finite and wider than nothing.
    pub fn initScaled(domain: mod.ChartDomain, scale_type: mod.ChartScaleType, found_lower: f64, found_upper: f64) Self {
        var lower = Self.scaled(scale_type, Self.finite(domain.lower)) orelse Self.toScale(scale_type, found_lower);
        var upper = Self.scaled(scale_type, Self.finite(domain.upper)) orelse Self.toScale(scale_type, found_upper);
        if (std.math.isNan(lower) and std.math.isNan(upper)) {
            // Nothing to chart and nothing given: the unit range.
            lower = 0;
            upper = 1;
        }
        if (std.math.isNan(lower)) lower = upper;
        if (std.math.isNan(upper)) upper = lower;
        if (upper < lower) std.mem.swap(f64, &lower, &upper);
        if (domain.symmetric and scale_type == .linear) {
            const reach = @max(@abs(lower), @abs(upper));
            lower = -reach;
            upper = reach;
        }
        if (!(upper > lower)) {
            // No width: about the value, out to zero or one unit either side
            // (a decade on a log scale).
            const centre = lower;
            const half = switch (scale_type) {
                .linear => @max(1, @abs(centre)),
                .log => 1,
            };
            lower = centre - half;
            upper = centre + half;
        }
        const self = Self{ .lower = lower, .upper = upper, .scale_type = scale_type };
        return self;
    }

    /// How far along the axis a value lies.
    ///
    /// - `self`: the axis.
    /// - `value`: the data value.
    /// - Returns: 0 at `lower`, 1 at `upper`, beyond either outside them;
    ///   NaN for a value at or below zero on a log scale.
    pub fn fraction(self: *const Self, value: f32) f64 {
        return (Self.toScale(self.scale_type, value) - self.lower) / (self.upper - self.lower);
    }

    /// Reports whether a value lies on the axis, its ends included.
    ///
    /// - `self`: the axis.
    /// - `value`: the data value.
    /// - Returns: true when it lies between `lower` and `upper`.
    pub fn contains(self: *const Self, value: f32) bool {
        const at = Self.toScale(self.scale_type, value);
        return at >= self.lower and at <= self.upper;
    }

    /// A bound that counts as given.
    ///
    /// - `bound`: the bound, if any.
    /// - Returns: the bound, or null when it is absent or not finite.
    fn finite(bound: ?f32) ?f64 {
        const value = bound orelse return null;
        return if (std.math.isFinite(value)) value else null;
    }

    /// A given bound in the scale's units.
    ///
    /// - `scale_type`: the axis's scale.
    /// - `bound`: a finite bound, if any.
    /// - Returns: the bound on the scale, or null when there is none or it
    ///   cannot lie on a log scale (at or below zero).
    fn scaled(scale_type: mod.ChartScaleType, bound: ?f64) ?f64 {
        const value = bound orelse return null;
        const at = Self.toScale(scale_type, value);
        return if (std.math.isNan(at)) null else at;
    }

    /// A value in the scale's units: itself, or its decade (`log10`).
    ///
    /// - `scale_type`: the axis's scale.
    /// - `value`: the data value.
    /// - Returns: the value on the scale; NaN for a NaN, or for a value at
    ///   or below zero on a log scale.
    fn toScale(scale_type: mod.ChartScaleType, value: f64) f64 {
        return switch (scale_type) {
            .linear => value,
            .log => if (value > 0) std.math.log10(value) else std.math.nan(f64),
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

test "a log axis spans decades and refuses what is not positive" {
    const nan = std.math.nan(f64);
    // The data's range, in decades: 1 to 1000 is three of them.
    const data = ChartAxis.initScaled(.{}, .log, 1, 1000);
    try std.testing.expectEqual(0, data.lower);
    try std.testing.expectEqual(3, data.upper);
    try std.testing.expectApproxEqAbs(1.0 / 3.0, data.fraction(10), 1e-12);
    try std.testing.expect(data.contains(1000) and !data.contains(1001));
    // Zero and below cannot lie on it: no place, and not on the axis.
    try std.testing.expect(std.math.isNan(data.fraction(0)));
    try std.testing.expect(std.math.isNan(data.fraction(-5)));
    try std.testing.expect(!data.contains(0));
    // A bound at or below zero counts as not given; symmetric is ignored.
    const bounded = ChartAxis.initScaled(.{ .lower = 0, .upper = 100, .symmetric = true }, .log, 0.1, 10);
    try std.testing.expectEqual(-1, bounded.lower);
    try std.testing.expectEqual(2, bounded.upper);
    // No width: a decade either side; nothing to chart: 1 to 10.
    const flat = ChartAxis.initScaled(.{}, .log, 10, 10);
    try std.testing.expectEqual(0, flat.lower);
    try std.testing.expectEqual(2, flat.upper);
    const empty = ChartAxis.initScaled(.{}, .log, nan, nan);
    try std.testing.expectEqual(0, empty.lower);
    try std.testing.expectEqual(1, empty.upper);
}
