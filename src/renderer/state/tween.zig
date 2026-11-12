//! One value animation.

const std = @import("std");
const log = std.log.scoped(.ziggui_tween);
const mod = @import("module.zig");

/// A single value animation: drive `target` from `from` to `to` over `duration`
/// seconds following `easing`.
pub const Tween = struct {
    const Self = @This();

    /// The state animated.
    target: *mod.State(f32),
    /// The starting value.
    from: f32,
    /// The ending value.
    to: f32,
    /// Seconds run so far.
    elapsed: f32 = 0,
    /// Seconds the animation lasts.
    duration: f32,
    /// The timing curve.
    easing: mod.Easing,

    /// Whether the animation has run its duration.
    ///
    /// - `self`: the tween.
    /// - Returns: true when done.
    pub fn finished(self: *const Self) bool {
        return self.elapsed >= self.duration;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
