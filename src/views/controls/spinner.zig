//! A small indeterminate activity indicator: a ring of dots, the lead one
//! solid and the rest fading behind it as it turns, as a status line's busy
//! mark. The determinate counterpart is `ProgressView`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_spinner);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// How many dots the ring holds.
const dot_count: usize = 8;

/// Milliseconds per turn.
const cycle_ms: u64 = 800;

/// The faintest a trailing dot draws, as a fraction of the color's alpha.
const faintest: f32 = 0.15;

/// One frame of a spinner, in the build arena: the `Canvas`'s context.
const SpinnerFrame = struct {
    const Self = @This();

    /// Which dot leads, 0 to `dot_count - 1`.
    lead: usize,
    /// The dots' color.
    color: renderer.Color,

    /// Draws the ring in the largest square that fits `rect`, centred.
    ///
    /// - `self`: the frame.
    /// - `graphics`: what it draws with.
    /// - `rect`: the view's frame.
    /// - Returns: nothing; propagates allocation failure.
    fn draw(self: *const Self, graphics: *mod.GraphicsContext, rect: renderer.Rect) std.mem.Allocator.Error!void {
        const side = @min(rect.width, rect.height);
        if (side <= 0) return;
        const dot = side * 0.24;
        const ring = (side - dot) / 2;
        const centre: renderer.Point = .{ .x = rect.x + rect.width / 2, .y = rect.y + rect.height / 2 };
        for (0..dot_count) |index| {
            // Clockwise from twelve o'clock; the lead dot solid, each one
            // behind it fainter.
            const angle = @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(dot_count)) * std.math.tau;
            const behind = (self.lead + dot_count - index) % dot_count;
            const strength = 1 - (1 - faintest) * @as(f32, @floatFromInt(behind)) / @as(f32, @floatFromInt(dot_count - 1));
            const x = centre.x + ring * @sin(angle);
            const y = centre.y - ring * @cos(angle);
            try graphics.fill(.{ .x = x - dot / 2, .y = y - dot / 2, .width = dot, .height = dot }, dot / 2, self.color.multiplyAlpha(strength));
        }
    }
};

/// A ring of dots turning once per `cycle_ms`, `size` points square. `time_ms`
/// is a monotonic millisecond clock (`FrameClock.shared().time()`); it reads
/// no clock itself, so the app keeps drawing frames while it shows (a busy
/// interval) for it to turn.
///
/// - `time_ms`: the clock.
/// - `size`: its side, in points.
/// - `color`: the dots' color.
/// - Returns: the view.
pub fn Spinner(time_ms: u64, size: f32, color: renderer.Color) mod.View {
    const frame = mod.BuildScope.shared().allocator().create(SpinnerFrame) catch @panic("oom");
    frame.* = .{ .lead = @intCast((time_ms % cycle_ms) * dot_count / cycle_ms), .color = color };
    return mod.Canvas(SpinnerFrame, frame, SpinnerFrame.draw).frame(size, size);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a spinner's lead dot moves round the ring with the clock" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    // Twelve o'clock leads at the start of a turn, three o'clock a quarter
    // through; six o'clock is well behind the lead both times.
    const top: [2]u32 = .{ 20, 3 };
    const right: [2]u32 = .{ 36, 20 };
    const bottom: [2]u32 = .{ 20, 36 };
    for ([_]u64{ 0, cycle_ms / 4 }, [_][2]u32{ top, right }) |time_ms, lead| {
        window.begin(renderer.MacosTheme.light);
        const view = Spinner(time_ms, 40, renderer.Color.black);
        window.end();
        var frame = try window.render(view, 40, 40);
        defer frame.deinit();
        // White behind: the solid dot is near black, a faint one near white.
        try std.testing.expect(frame.at(lead[0], lead[1]).r < 0.2);
        try std.testing.expect(frame.at(bottom[0], bottom[1]).r > 0.3);
    }
}
