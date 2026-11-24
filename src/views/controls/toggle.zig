//! A switch over a `Binding(bool)`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_toggle);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A switch over a `Binding(bool)`, its label on the leading edge.
///
/// - `label`: the label.
/// - `value`: the state it shows and flips.
/// - Returns: the view.
pub fn Toggle(label: []const u8, value: mod.Binding(bool)) mod.View {
    return .{ .kind = .{ .toggle = .{ .value = value, .label = label } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a checkbox style draws its box: square and circular filled while on, rounded outlined" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var on = renderer.State(bool).init(std.testing.allocator, true);
    defer on.deinit();
    const red = renderer.Color.rgb(1, 0, 0);
    const side: u32 = @intFromFloat(mod.ControlMetrics.checkbox_size);
    const cases = [_]struct { style: mod.CheckboxStyle, corner: renderer.Rgba8, inside: renderer.Rgba8 }{
        // Filled to its square corner; the check leaves the top edge's middle red.
        .{ .style = .square, .corner = red.toRgba8(), .inside = red.toRgba8() },
        // The corner lies outside the circle; the top edge's middle is filled.
        .{ .style = .circular, .corner = renderer.Color.white.toRgba8(), .inside = red.toRgba8() },
        // Never filled: inside the outline the ground shows.
        .{ .style = .rounded, .corner = renderer.Color.white.toRgba8(), .inside = renderer.Color.white.toRgba8() },
    };
    for (cases) |case| {
        window.begin(renderer.MacosTheme.light);
        const view = Toggle("", on.binding()).foregroundStyle(red).toggleStyle(.checkbox).checkboxStyle(case.style);
        window.end();
        var frame = try window.render(view, side, side);
        defer frame.deinit();
        try std.testing.expectEqual(case.corner, frame.rgba8At(0, 0));
        try std.testing.expectEqual(case.inside, frame.rgba8At(side / 2, 3));
    }
    // A tap flips it, whatever its style.
    try std.testing.expect(window.tap(.{ .x = 7, .y = 7 }));
    try std.testing.expect(!on.get());
}

test "a compact checkbox is a small outlined box: the tint and the check while on, untinted and empty while off" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var on = renderer.State(bool).init(std.testing.allocator, true);
    defer on.deinit();
    const red = renderer.Color.rgb(1, 0, 0);
    const white = renderer.Color.white.toRgba8();
    const side: u32 = @intFromFloat(mod.ControlMetrics.compact_checkbox_size);
    for ([_]bool{ true, false }) |value| {
        on.set(value);
        window.begin(renderer.MacosTheme.light);
        const view = Toggle("", on.binding()).foregroundStyle(red).toggleStyle(.checkbox).checkboxStyle(.compact);
        window.end();
        var frame = try window.render(view, side, side);
        defer frame.deinit();
        // Never filled: the rounded corner and the inside above the check show the ground.
        try std.testing.expectEqual(white, frame.rgba8At(0, 0));
        try std.testing.expectEqual(white, frame.rgba8At(side / 2, 3));
        const edge = frame.rgba8At(side / 2, 0);
        const check = frame.rgba8At(side / 2 - 1, 7);
        if (value) {
            // On: the outline and the check in the toggle's tint.
            try std.testing.expectEqual(red.toRgba8(), edge);
            try std.testing.expectEqual(red.toRgba8(), check);
        } else {
            // Off: the outline grey (the secondary label color, not the tint), no check.
            try std.testing.expect(edge.r == edge.g and edge.g == edge.b and edge.r < white.r);
            try std.testing.expectEqual(white, check);
        }
    }
}
