//! Spacing, sizing, and radius metrics.

const std = @import("std");
const log = std.log.scoped(.ziggui_metrics);

/// A theme's spacing, sizing, and radius metrics.
pub const Metrics = struct {
    const Self = @This();

    /// Default spacing between elements in a stack.
    spacing: f32 = 8,
    /// Tight spacing.
    spacing_small: f32 = 4,
    /// Loose spacing.
    spacing_large: f32 = 16,
    /// Default content padding.
    padding: f32 = 8,
    /// Corner radius for cards / grouped containers.
    corner_radius: f32 = 12,
    /// Corner radius for push buttons and controls.
    control_corner_radius: f32 = 7,
    /// Corner radius for large panels (sidebars, sheets, popovers).
    panel_corner_radius: f32 = 16,
    /// Standard control (button/field) height.
    control_height: f32 = 28,
    /// Rounded selection-highlight radius for sidebar / list rows.
    selection_corner_radius: f32 = 8,
    /// Window corner radius.
    window_corner_radius: f32 = 10,
    /// Hairline thickness for separators/borders at 1x.
    hairline: f32 = 1,
    /// The chiseled look (Windows 2000): a view's own `.cornerRadius(r)` squares
    /// off and its `.border(...)` becomes a sunken bevel, so an app's cards,
    /// wells and pills match the painter's controls.
    chiseled: bool = false,

    /// A view's requested corner radius, squared off in a chiseled theme.
    ///
    /// - `self`: the metrics.
    /// - `requested`: the radius the view asks for.
    /// - Returns: the radius to draw.
    pub fn radius(self: *const Self, requested: f32) f32 {
        return if (self.chiseled) 0 else requested;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Metrics: sensible defaults" {
    const metrics = Metrics{};
    try std.testing.expectEqual(@as(f32, 8), metrics.spacing);
    try std.testing.expectEqual(@as(f32, 7), metrics.control_corner_radius);
    // Liquid Glass rounds panels more than controls.
    try std.testing.expect(metrics.panel_corner_radius > metrics.corner_radius);
}
