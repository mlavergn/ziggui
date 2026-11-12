//! What a `Drawing` paints with.

const std = @import("std");
const log = std.log.scoped(.ziggui_pen);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// What a `Drawing` paints with: a few primitives in the view's own
/// coordinates (points), with the view's opacity applied.
pub const Pen = struct {
    const Self = @This();

    /// The paint context.
    context: *const mod.Context,

    /// Where it draws.
    canvas: *renderer.Canvas,

    /// Draws a line.
    ///
    /// - `self`: the pen.
    /// - `start`: one end.
    /// - `end`: the other end.
    /// - `width`: the stroke width.
    /// - `color`: the color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn line(self: *Self, start: renderer.Point, end: renderer.Point, width: f32, color: renderer.Color) std.mem.Allocator.Error!void {
        try self.canvas.line(start, end, width, self.tint(color));
    }

    /// Fills a rounded rectangle.
    ///
    /// - `self`: the pen.
    /// - `rect`: the rectangle.
    /// - `radius`: its corner radius.
    /// - `color`: the color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn fill(self: *Self, rect: renderer.Rect, radius: f32, color: renderer.Color) std.mem.Allocator.Error!void {
        try self.canvas.fillRoundedRect(rect, radius, self.tint(color));
    }

    /// Fills `rect` with `top` at its top edge fading to `bottom` at its bottom edge.
    ///
    /// - `self`: the pen.
    /// - `rect`: the rectangle.
    /// - `top`: the top color.
    /// - `bottom`: the bottom color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn verticalGradient(self: *Self, rect: renderer.Rect, top: renderer.Color, bottom: renderer.Color) std.mem.Allocator.Error!void {
        try self.canvas.push(.{ .linearGradient = .{ .rect = rect, .start = rect.origin(), .end = .{ .x = rect.x, .y = rect.maxY() }, .start_color = self.tint(top), .end_color = self.tint(bottom) } });
    }

    /// Draws one line of text with its top-left at `origin`.
    ///
    /// - `self`: the pen.
    /// - `string`: the text.
    /// - `pixel_size`: its size.
    /// - `color`: its color.
    /// - `origin`: its top-left.
    /// - Returns: nothing; propagates allocation failure.
    pub fn text(self: *Self, string: []const u8, pixel_size: f32, color: renderer.Color, origin: renderer.Point) std.mem.Allocator.Error!void {
        try self.context.drawText(self.canvas, string, pixel_size, self.tint(color), origin);
    }

    /// Formats text in the frame arena (paint runs after the build arena is gone).
    ///
    /// - `self`: the pen.
    /// - `format`: the format string.
    /// - `args`: its arguments.
    /// - Returns: the text; propagates allocation failure.
    pub fn print(self: *const Self, comptime format: []const u8, args: anytype) std.mem.Allocator.Error![]const u8 {
        return self.context.arena.print(format, args);
    }

    /// The width of one line of text.
    ///
    /// - `self`: the pen.
    /// - `string`: the text.
    /// - `pixel_size`: its size.
    /// - Returns: the width, in points.
    pub fn textWidth(self: *const Self, string: []const u8, pixel_size: f32) f32 {
        return renderer.TextShaper.init(self.context.cache.face).measureLineWidth(string, pixel_size);
    }

    /// The height of one line of text.
    ///
    /// - `self`: the pen.
    /// - `pixel_size`: the text size.
    /// - Returns: the height, in points.
    pub fn lineHeight(self: *const Self, pixel_size: f32) f32 {
        return renderer.TextShaper.init(self.context.cache.face).lineHeight(pixel_size);
    }

    /// A color with the view's opacity applied.
    ///
    /// - `self`: the pen.
    /// - `color`: the color.
    /// - Returns: the faded color.
    fn tint(self: *const Self, color: renderer.Color) renderer.Color {
        return color.multiplyAlpha(self.context.opacity);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
