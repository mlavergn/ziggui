//! Three dots bouncing in a phase-shifted wave: an inline "thinking…" indicator.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_loading_dots);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A dot's diameter.
const diameter: f32 = 16;

/// How high a dot bounces.
const amplitude: f32 = 10;

/// Milliseconds per wave.
const cycle_ms: u64 = 1000;

/// One bouncing dot.
const LoadingDot = struct {
    const Self = @This();

    /// The dot at `phase` of the wave.
    ///
    /// - `phase`: how far through the wave, 0 to 1.
    /// - `index`: which dot (0, 1, 2).
    /// - `color`: its color.
    /// - Returns: the dot, padded to its lift.
    fn view(phase: f32, index: f32, color: renderer.Color) mod.View {
        // Phase-shift each dot so they bounce in sequence; lift ∈ [0, amplitude].
        const angle = (phase - index * 0.18) * std.math.tau;
        const lift = amplitude * 0.5 * (1.0 + @sin(angle));
        // Frame is `diameter + amplitude` tall so the top/bottom padding (which sums
        // to `amplitude`) leaves a full `diameter`-sized circle — padding shares the
        // frame with the shape, so a `diameter`-tall frame would shrink the dot instead.
        return mod.Circle(color)
            .frameWidth(diameter)
            .frameHeight(diameter + amplitude)
            .paddingInsets(.{ .top = amplitude - lift, .bottom = lift });
    }
};

/// Three dots bouncing in a phase-shifted wave — an inline "thinking…" indicator
/// (e.g. a streaming chat reply). `time_ms` is a monotonic millisecond clock (such
/// as `SDL_GetTicks`); this never reads a wall clock, so the caller must keep
/// redrawing (the app's busy-check does this during generation) for it to move.
///
/// - `time_ms`: the clock.
/// - `color`: the dots' color.
/// - Returns: the view.
pub fn LoadingDots(time_ms: u64, color: renderer.Color) mod.View {
    const phase = @as(f32, @floatFromInt(time_ms % cycle_ms)) / @as(f32, @floatFromInt(cycle_ms));
    return mod.HStack(.{ LoadingDot.view(phase, 0, color), LoadingDot.view(phase, 1, color), LoadingDot.view(phase, 2, color) }).spacing(7);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
