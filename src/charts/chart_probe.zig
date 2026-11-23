//! What every chart's tests share: drawing a chart headless and reading what
//! it drew.

const std = @import("std");
const log = std.log.scoped(.ziggui_chart_probe);
const renderer = @import("renderer");
const views = @import("views");

/// The charts' test fixture: draws a chart into a display list, its
/// accessibility collected, and checks what it drew. Tests only.
pub const ChartProbe = struct {
    const Self = @This();

    /// Draws a chart into a display list at `width` × `height`, accessibility collected.
    ///
    /// - `environment`: the headless frame, set up.
    /// - `display_list`: where it draws.
    /// - `a11y`: where its accessibility nodes go.
    /// - `view`: the chart.
    /// - `width`: the frame's width.
    /// - `height`: the frame's height.
    /// - Returns: nothing; propagates allocation failure.
    pub fn render(environment: *views.TestEnvironment, display_list: *renderer.DisplayList, a11y: *std.ArrayList(views.A11yNode), view: views.View, width: f32, height: f32) !void {
        var context = environment.context();
        context.a11y = a11y;
        try views.ViewRenderer.render(&context, view, .{ .x = 0, .y = 0, .width = width, .height = height }, display_list);
    }

    /// Checks that every line a display list holds has finite ends inside a rectangle.
    ///
    /// - `display_list`: what was drawn.
    /// - `bounds`: where every line must lie.
    /// - Returns: nothing; fails the test otherwise.
    pub fn expectInside(display_list: *const renderer.DisplayList, bounds: renderer.Rect) !void {
        for (display_list.commands.items) |command| {
            if (command != .line) continue;
            for ([_]renderer.Point{ command.line.start, command.line.end }) |end| {
                try std.testing.expect(std.math.isFinite(end.x) and std.math.isFinite(end.y));
                try std.testing.expect(bounds.containsRect(.{ .x = end.x, .y = end.y }, 0.001));
            }
        }
    }

    /// Checks that a rectangle is the one expected, to within float rounding.
    ///
    /// - `expected`: the rectangle expected.
    /// - `actual`: the rectangle drawn.
    /// - Returns: nothing; fails the test otherwise.
    pub fn expectRect(expected: renderer.Rect, actual: renderer.Rect) !void {
        inline for (.{ "x", "y", "width", "height" }) |field| try std.testing.expectApproxEqAbs(@field(expected, field), @field(actual, field), 1e-3);
    }

    /// Collects the filled rectangles a display list holds, in order.
    ///
    /// - `display_list`: what was drawn.
    /// - `out`: where they go; the caller frees it with `std.testing.allocator`.
    /// - Returns: nothing; propagates allocation failure.
    pub fn fills(display_list: *const renderer.DisplayList, out: *std.ArrayList(renderer.FillRoundedRectCommand)) !void {
        for (display_list.commands.items) |command| {
            if (command == .fillRoundedRect) try out.append(std.testing.allocator, command.fillRoundedRect);
        }
    }

    /// Collects the lines a display list holds, in order.
    ///
    /// - `display_list`: what was drawn.
    /// - `out`: where they go; the caller frees it with `std.testing.allocator`.
    /// - Returns: nothing; propagates allocation failure.
    pub fn lines(display_list: *const renderer.DisplayList, out: *std.ArrayList(renderer.LineCommand)) !void {
        for (display_list.commands.items) |command| {
            if (command == .line) try out.append(std.testing.allocator, command.line);
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
