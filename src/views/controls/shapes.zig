//! Filled shapes: rectangles, rounded rectangles, circles, capsules, ellipses.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_shapes);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A rectangle filled with `color`; fills the space it is offered.
///
/// - `color`: the fill.
/// - Returns: the view.
pub fn Rectangle(color: renderer.Color) mod.View {
    return .{ .kind = .{ .shape = .{ .shape = .rect, .fill = .{ .color = color } } } };
}

/// A rounded rectangle filled with `color`.
///
/// - `color`: the fill.
/// - `radius`: the corner radius.
/// - Returns: the view.
pub fn RoundedRectangle(color: renderer.Color, radius: f32) mod.View {
    return .{ .kind = .{ .shape = .{ .shape = .roundedRect, .corner_radius = radius, .fill = .{ .color = color } } } };
}

/// A circle filled with `color`, inscribed in its frame.
///
/// - `color`: the fill.
/// - Returns: the view.
pub fn Circle(color: renderer.Color) mod.View {
    return .{ .kind = .{ .shape = .{ .shape = .circle, .fill = .{ .color = color } } } };
}

/// A capsule (half-circle ends) filled with `color`.
///
/// - `color`: the fill.
/// - Returns: the view.
pub fn Capsule(color: renderer.Color) mod.View {
    return .{ .kind = .{ .shape = .{ .shape = .capsule, .fill = .{ .color = color } } } };
}

/// An ellipse filled with `color`.
///
/// - `color`: the fill.
/// - Returns: the view.
pub fn Ellipse(color: renderer.Color) mod.View {
    return .{ .kind = .{ .shape = .{ .shape = .ellipse, .fill = .{ .color = color } } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
