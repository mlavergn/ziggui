//! Everything a painter needs to draw chrome.

const std = @import("std");
const log = std.log.scoped(.ziggui_surface);
const mod = @import("module.zig");

/// Everything a painter needs to draw chrome: the target `canvas`, the active
/// `palette`/`metrics`, the `scheme` (light/dark), and the inherited `opacity`.
/// Convenience methods apply `opacity` so painters read declaratively.
pub const Surface = struct {
    const Self = @This();

    /// The canvas drawn into.
    canvas: *mod.Canvas,
    /// The active palette.
    palette: *const mod.Palette,
    /// The active metrics.
    metrics: *const mod.Metrics,
    /// Light or dark.
    scheme: mod.ColorScheme,
    /// The inherited opacity every color is multiplied by.
    opacity: f32 = 1,

    /// A two-ring 3D bevel from the palette's four edge colors. `raised` lights
    /// the top-left and shadows the bottom-right; sunken swaps them.
    ///
    /// - `self`: the surface.
    /// - `rect`: the bevel's outer rect.
    /// - `raised`: raised, or sunken when false.
    /// - Returns: nothing; propagates allocation failure.
    pub fn bevel(self: *const Self, rect: mod.Rect, raised: bool) std.mem.Allocator.Error!void {
        const palette = self.palette;
        const outer = if (raised) .{ palette.control_highlight, palette.control_dark_shadow } else .{ palette.control_shadow, palette.control_highlight };
        const inner = if (raised) .{ palette.control_light, palette.control_shadow } else .{ palette.control_dark_shadow, palette.control_light };
        try self.ring(rect, outer[0], outer[1]);
        try self.ring(rect.insetBy(1, 1), inner[0], inner[1]);
    }

    /// Fill a rounded rect.
    ///
    /// - `self`: the surface.
    /// - `rect`: the rect.
    /// - `radius`: the corner radius.
    /// - `color`: the fill.
    /// - Returns: nothing; propagates allocation failure.
    pub fn fill(self: *const Self, rect: mod.Rect, radius: f32, color: mod.Color) std.mem.Allocator.Error!void {
        try self.canvas.fillRoundedRect(rect, radius, color.multiplyAlpha(self.opacity));
    }

    /// Stroke a rounded rect's outline.
    ///
    /// - `self`: the surface.
    /// - `rect`: the rect.
    /// - `radius`: the corner radius.
    /// - `width`: the stroke's width.
    /// - `color`: the stroke color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn stroke(self: *const Self, rect: mod.Rect, radius: f32, width: f32, color: mod.Color) std.mem.Allocator.Error!void {
        try self.canvas.strokeRoundedRect(rect, radius, width, color.multiplyAlpha(self.opacity));
    }

    /// A left-to-right (horizontal) gradient filling `rect`.
    ///
    /// - `self`: the surface.
    /// - `rect`: the rect.
    /// - `radius`: the corner radius.
    /// - `left`: the color at the left edge.
    /// - `right`: the color at the right edge.
    /// - Returns: nothing; propagates allocation failure.
    pub fn horizontalGradient(self: *const Self, rect: mod.Rect, radius: f32, left: mod.Color, right: mod.Color) std.mem.Allocator.Error!void {
        try self.canvas.push(.{ .linearGradient = .{
            .rect = rect,
            .radius = radius,
            .start = .{ .x = rect.x, .y = rect.y },
            .end = .{ .x = rect.maxX(), .y = rect.y },
            .start_color = left.multiplyAlpha(self.opacity),
            .end_color = right.multiplyAlpha(self.opacity),
        } });
    }

    /// A hairline along the bottom edge of `rect`, in the separator color.
    ///
    /// - `self`: the surface.
    /// - `rect`: the rect.
    /// - Returns: nothing; propagates allocation failure.
    pub fn bottomHairline(self: *const Self, rect: mod.Rect) std.mem.Allocator.Error!void {
        const hairline = self.metrics.hairline;
        try self.fill(.{ .x = rect.x, .y = rect.maxY() - hairline, .width = rect.width, .height = hairline }, 0, self.palette.separator);
    }

    /// A top-to-bottom (vertical) gradient filling `rect`.
    ///
    /// - `self`: the surface.
    /// - `rect`: the rect.
    /// - `radius`: the corner radius.
    /// - `top`: the color at the top edge.
    /// - `bottom`: the color at the bottom edge.
    /// - Returns: nothing; propagates allocation failure.
    pub fn verticalGradient(self: *const Self, rect: mod.Rect, radius: f32, top: mod.Color, bottom: mod.Color) std.mem.Allocator.Error!void {
        try self.canvas.push(.{ .linearGradient = .{
            .rect = rect,
            .radius = radius,
            .start = .{ .x = rect.x, .y = rect.y },
            .end = .{ .x = rect.x, .y = rect.maxY() },
            .start_color = top.multiplyAlpha(self.opacity),
            .end_color = bottom.multiplyAlpha(self.opacity),
        } });
    }

    /// Draw a line segment.
    ///
    /// - `self`: the surface.
    /// - `start`: one end.
    /// - `end`: the other end.
    /// - `width`: the line's width.
    /// - `color`: the line's color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn lineSegment(self: *const Self, start: mod.Point, end: mod.Point, width: f32, color: mod.Color) std.mem.Allocator.Error!void {
        try self.canvas.line(start, end, width, color.multiplyAlpha(self.opacity));
    }

    /// Fill a circle.
    ///
    /// - `self`: the surface.
    /// - `center`: the circle's center.
    /// - `radius`: the circle's radius.
    /// - `color`: the fill.
    /// - Returns: nothing; propagates allocation failure.
    pub fn fillCircle(self: *const Self, center: mod.Point, radius: f32, color: mod.Color) std.mem.Allocator.Error!void {
        try self.canvas.fillCircle(center, radius, color.multiplyAlpha(self.opacity));
    }

    /// Frost the content already drawn beneath `rect` (a `blurRect`), then lay
    /// `tint` over the result — the backdrop-sampling half of a glass surface.
    /// Pair with a translucent fill and a rim drawn on top.
    ///
    /// - `self`: the surface.
    /// - `rect`: the region.
    /// - `radius`: the region's corner radius.
    /// - `sigma`: the blur's extent.
    /// - `tint`: the color laid over the blur.
    /// - Returns: nothing; propagates allocation failure.
    pub fn backdropBlur(self: *const Self, rect: mod.Rect, radius: f32, sigma: f32, tint: mod.Color) std.mem.Allocator.Error!void {
        try self.canvas.blurRect(rect, radius, sigma, tint.multiplyAlpha(self.opacity));
    }

    /// One 1px ring: top and left edges in `top_left`, bottom and right in
    /// `bottom_right`.
    fn ring(self: *const Self, rect: mod.Rect, top_left: mod.Color, bottom_right: mod.Color) std.mem.Allocator.Error!void {
        try self.fill(.{ .x = rect.x, .y = rect.y, .width = rect.width, .height = 1 }, 0, top_left);
        try self.fill(.{ .x = rect.x, .y = rect.y, .width = 1, .height = rect.height }, 0, top_left);
        try self.fill(.{ .x = rect.x, .y = rect.maxY() - 1, .width = rect.width, .height = 1 }, 0, bottom_right);
        try self.fill(.{ .x = rect.maxX() - 1, .y = rect.y, .width = 1, .height = rect.height }, 0, bottom_right);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
