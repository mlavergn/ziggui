//! Timing curves for animations.

const std = @import("std");
const log = std.log.scoped(.ziggui_easing);
const mod = @import("module.zig");

/// A timing curve mapping normalized progress (0..1) to eased progress.
pub const Easing = enum {
    const Self = @This();

    /// Constant speed.
    linear,
    /// Starts slow.
    easeIn,
    /// Ends slow.
    easeOut,
    /// Starts and ends slow.
    easeInOut,

    /// The eased progress for `progress`.
    ///
    /// - `self`: the curve.
    /// - `progress`: the linear progress, clamped to 0...1.
    /// - Returns: the eased progress.
    pub fn apply(self: *const Self, progress: f32) f32 {
        const clamped = std.math.clamp(progress, 0, 1);
        return switch (self.*) {
            .linear => clamped,
            .easeIn => clamped * clamped,
            .easeOut => 1 - (1 - clamped) * (1 - clamped),
            .easeInOut => if (clamped < 0.5) 2 * clamped * clamped else 1 - 2 * (1 - clamped) * (1 - clamped),
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

test "Easing: endpoints pinned, curves monotonic, in/out bowed correctly" {
    inline for (.{ mod.Easing.linear, mod.Easing.easeIn, mod.Easing.easeOut, mod.Easing.easeInOut }) |easing| {
        try std.testing.expectApproxEqAbs(@as(f32, 0), easing.apply(0), 1e-6);
        try std.testing.expectApproxEqAbs(@as(f32, 1), easing.apply(1), 1e-6);
        var previous: f32 = -1;
        var step: usize = 0;
        while (step <= 10) : (step += 1) {
            const progress = @as(f32, @floatFromInt(step)) / 10.0;
            const eased = easing.apply(progress);
            try std.testing.expect(eased >= previous - 1e-6); // non-decreasing
            previous = eased;
        }
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), mod.Easing.linear.apply(0.5), 1e-6);
    try std.testing.expect(mod.Easing.easeIn.apply(0.5) < 0.5); // starts slow
    try std.testing.expect(mod.Easing.easeOut.apply(0.5) > 0.5); // ends slow
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), mod.Easing.easeInOut.apply(0.5), 1e-6);
}
