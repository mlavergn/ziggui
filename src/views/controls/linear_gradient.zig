//! A linear gradient that fills its frame.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_linear_gradient);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A gradient that fills its frame, interpolating between two colors along the
/// vector from `start` to `end` (unit points in 0..1, like SwiftUI UnitPoint).
///
/// - `start_color`: the color at `start`.
/// - `end_color`: the color at `end`.
/// - `start`: where the gradient starts, in unit points.
/// - `end`: where it ends, in unit points.
/// - Returns: the view.
pub fn LinearGradient(start_color: renderer.Color, end_color: renderer.Color, start: renderer.Point, end: renderer.Point) mod.View {
    return .{ .kind = .{ .shape = .{
        .shape = .rect,
        .fill = .{ .linearGradient = .{ .start_color = start_color, .end_color = end_color, .start = start, .end = end } },
    } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
