//! Markers a `Canvas` draws over a picture: crosshairs, rings, halos, a reticle,
//! labels, a chip and a callout, and the hit test that finds one under the pointer.

const std = @import("std");
const log = std.log.scoped(.ziggui_canvas_markers);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Draws marks over a picture through a `GraphicsContext`, for an app that
/// places points on photos or plots: a crosshair open at its centre so the
/// exact spot stays visible, a ring, a halo behind a marker under the pointer,
/// guide lines across the frame (a reticle), a label on a pill, a chip at the
/// foot of the frame and a callout at its head. Each takes its colors, so it
/// follows whatever palette the app draws with. `nearest` finds the marker
/// under a point.
pub const CanvasMarkers = struct {
    const Self = @This();

    /// The text size of a pill and a chip.
    pub const label_size: f32 = 13;

    /// A crosshair: two rings and four ticks crossing them, open at the centre,
    /// outlined so it shows over any picture.
    ///
    /// - `graphics`: what it draws with.
    /// - `at`: its centre.
    /// - `radius`: its outer ring's radius, in points.
    /// - `color`: its strokes.
    /// - `outline`: the wider strokes under them.
    /// - Returns: nothing; propagates allocation failure.
    pub fn crosshair(graphics: *mod.GraphicsContext, at: renderer.Point, radius: f32, color: renderer.Color, outline: renderer.Color) std.mem.Allocator.Error!void {
        try crossStrokes(graphics, at, radius, 3.5, outline.withAlpha(0.75));
        try crossStrokes(graphics, at, radius, 1.75, color);
    }

    /// A circle's outline: one stroke of a rounded square whose corner radius
    /// is half its side.
    ///
    /// - `graphics`: what it draws with.
    /// - `at`: its centre.
    /// - `radius`: its radius, in points.
    /// - `width`: its stroke, in points.
    /// - `color`: its color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn ring(graphics: *mod.GraphicsContext, at: renderer.Point, radius: f32, width: f32, color: renderer.Color) std.mem.Allocator.Error!void {
        try graphics.stroke(.{ .x = at.x - radius, .y = at.y - radius, .width = 2 * radius, .height = 2 * radius }, radius, width, color);
    }

    /// A filled disc behind a marker: the halo of one under the pointer.
    ///
    /// - `graphics`: what it draws with.
    /// - `at`: its centre.
    /// - `radius`: its radius, in points.
    /// - `color`: its fill.
    /// - Returns: nothing; propagates allocation failure.
    pub fn halo(graphics: *mod.GraphicsContext, at: renderer.Point, radius: f32, color: renderer.Color) std.mem.Allocator.Error!void {
        try graphics.fill(.{ .x = at.x - radius, .y = at.y - radius, .width = 2 * radius, .height = 2 * radius }, radius, color);
    }

    /// Guide lines through a point across the whole frame, open by `gap` around
    /// it so the point itself stays clear.
    ///
    /// - `graphics`: what it draws with.
    /// - `frame`: the frame the lines span.
    /// - `at`: the point.
    /// - `gap`: how far from the point the lines stop, in points.
    /// - `color`: their color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn reticle(graphics: *mod.GraphicsContext, frame: renderer.Rect, at: renderer.Point, gap: f32, color: renderer.Color) std.mem.Allocator.Error!void {
        try graphics.line(.{ .x = frame.x, .y = at.y }, .{ .x = at.x - gap, .y = at.y }, 1, color);
        try graphics.line(.{ .x = at.x + gap, .y = at.y }, .{ .x = frame.maxX(), .y = at.y }, 1, color);
        try graphics.line(.{ .x = at.x, .y = frame.y }, .{ .x = at.x, .y = at.y - gap }, 1, color);
        try graphics.line(.{ .x = at.x, .y = at.y + gap }, .{ .x = at.x, .y = frame.maxY() }, 1, color);
    }

    /// A label on a rounded pill, its top-left at a point.
    ///
    /// - `graphics`: what it draws with.
    /// - `at`: its top-left.
    /// - `words`: the label; kept until the frame renders (`graphics.print` copies).
    /// - `fill`: the pill.
    /// - `ink`: the label.
    /// - Returns: where the pill was drawn; propagates allocation failure.
    pub fn pill(graphics: *mod.GraphicsContext, at: renderer.Point, words: []const u8, fill: renderer.Color, ink: renderer.Color) std.mem.Allocator.Error!renderer.Rect {
        const rect = renderer.Rect{ .x = at.x, .y = at.y, .width = graphics.textWidth(words, label_size) + 14, .height = graphics.lineHeight(label_size) + 6 };
        try graphics.fill(rect, 6, fill);
        try graphics.text(words, label_size, ink, .{ .x = at.x + 7, .y = at.y + 3 });
        return rect;
    }

    /// A capsule centered at the foot of a frame (a zoom level that fits the
    /// picture again on a click).
    ///
    /// - `graphics`: what it draws with.
    /// - `frame`: the frame.
    /// - `words`: the chip's words; kept until the frame renders.
    /// - `fill`: the capsule.
    /// - `ink`: the words.
    /// - Returns: where the chip was drawn, for a click; propagates allocation failure.
    pub fn chip(graphics: *mod.GraphicsContext, frame: renderer.Rect, words: []const u8, fill: renderer.Color, ink: renderer.Color) std.mem.Allocator.Error!renderer.Rect {
        const width = graphics.textWidth(words, label_size) + 20;
        const height = graphics.lineHeight(label_size) + 10;
        const rect = renderer.Rect{ .x = frame.x + (frame.width - width) / 2, .y = frame.maxY() - height - 12, .width = width, .height = height };
        try graphics.fill(rect, height / 2, fill);
        try graphics.text(words, label_size, ink, .{ .x = rect.x + 10, .y = rect.y + 5 });
        return rect;
    }

    /// A callout centered at the head of a frame: a title, shrunk from 20 pt to
    /// no less than 13 pt to fit, over a line of detail. A frame with no room
    /// for it (24 pt wide or less) draws nothing.
    ///
    /// - `graphics`: what it draws with.
    /// - `frame`: the frame.
    /// - `title`: the instruction; kept until the frame renders.
    /// - `detail`: the line under it; kept until the frame renders.
    /// - `fill`: the box.
    /// - `ink`: the words.
    /// - Returns: where the callout was drawn, zero-wide at the frame's head
    ///   when there was no room; propagates allocation failure.
    pub fn callout(graphics: *mod.GraphicsContext, frame: renderer.Rect, title: []const u8, detail: []const u8, fill: renderer.Color, ink: renderer.Color) std.mem.Allocator.Error!renderer.Rect {
        var size: f32 = 20;
        const room = @max(0, frame.width - 24);
        if (!(room > 0)) return .{ .x = frame.x + frame.width / 2, .y = frame.y + 12, .width = 0, .height = 0 };
        while (size > 13 and graphics.textWidth(title, size) + 32 > room) size -= 1;
        const width = @min(room, @max(graphics.textWidth(title, size), graphics.textWidth(detail, label_size)) + 32);
        const height = graphics.lineHeight(size) + graphics.lineHeight(label_size) + 22;
        const rect = renderer.Rect{ .x = frame.x + (frame.width - width) / 2, .y = frame.y + 12, .width = width, .height = height };
        try graphics.fill(rect, 12, fill);
        try graphics.text(title, size, ink, .{ .x = rect.x + 16, .y = rect.y + 9 });
        try graphics.text(detail, label_size, ink.withAlpha(0.85), .{ .x = rect.x + 16, .y = rect.y + 13 + graphics.lineHeight(size) });
        return rect;
    }

    /// The marker nearest a point, within reach.
    ///
    /// - `markers`: the markers' points, in any one coordinate space.
    /// - `at`: the point, in the same space.
    /// - `reach`: the farthest a marker may be, in the same units.
    /// - Returns: the nearest marker's index, or null when none is within reach.
    pub fn nearest(markers: []const renderer.Point, at: renderer.Point, reach: f32) ?usize {
        var best: ?usize = null;
        var best_distance = reach;
        for (markers, 0..) |marker, index| {
            const distance = std.math.hypot(marker.x - at.x, marker.y - at.y);
            if (distance <= best_distance) {
                best = index;
                best_distance = distance;
            }
        }
        return best;
    }

    /// One pass of a crosshair's strokes, at a width and a color.
    ///
    /// - `graphics`: what it draws with.
    /// - `at`: its centre.
    /// - `radius`: its outer ring's radius, in points.
    /// - `width`: the strokes' width, in points.
    /// - `color`: their color.
    /// - Returns: nothing; propagates allocation failure.
    fn crossStrokes(graphics: *mod.GraphicsContext, at: renderer.Point, radius: f32, width: f32, color: renderer.Color) std.mem.Allocator.Error!void {
        try ring(graphics, at, radius, width, color);
        try ring(graphics, at, radius * 0.55, width, color);
        const inner = radius * 0.22;
        const outer = radius * 1.3;
        try graphics.line(.{ .x = at.x - outer, .y = at.y }, .{ .x = at.x - inner, .y = at.y }, width, color);
        try graphics.line(.{ .x = at.x + inner, .y = at.y }, .{ .x = at.x + outer, .y = at.y }, width, color);
        try graphics.line(.{ .x = at.x, .y = at.y - outer }, .{ .x = at.x, .y = at.y - inner }, width, color);
        try graphics.line(.{ .x = at.x, .y = at.y + inner }, .{ .x = at.x, .y = at.y + outer }, width, color);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(CanvasMarkers);
    // Nothing here does I/O to trace.
    _ = log;
}

test "canvas markers find the nearest marker within reach" {
    const markers = [_]renderer.Point{ .{ .x = 10, .y = 10 }, .{ .x = 50, .y = 50 }, .{ .x = 52, .y = 49 } };
    try std.testing.expectEqual(@as(?usize, 2), CanvasMarkers.nearest(&markers, .{ .x = 53, .y = 49 }, 12));
    try std.testing.expectEqual(@as(?usize, 0), CanvasMarkers.nearest(&markers, .{ .x = 12, .y = 9 }, 12));
    try std.testing.expectEqual(@as(?usize, null), CanvasMarkers.nearest(&markers, .{ .x = 30, .y = 30 }, 12));
    try std.testing.expectEqual(@as(?usize, null), CanvasMarkers.nearest(&.{}, .{ .x = 0, .y = 0 }, 12));
}

test "canvas markers draw a ring as one stroke, and no callout without room" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const context = environment.context();
    var display_list = renderer.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    var graphics = mod.GraphicsContext{ .context = &context, .display_list = &display_list };

    try CanvasMarkers.ring(&graphics, .{ .x = 50, .y = 40 }, 10, 2, renderer.Color.red);
    try std.testing.expectEqual(@as(usize, 1), display_list.count());
    const stroke = display_list.commands.items[0].strokeRoundedRect;
    try std.testing.expectEqual(@as(f32, 40), stroke.rect.x);
    try std.testing.expectEqual(@as(f32, 20), stroke.rect.width);
    try std.testing.expectEqual(@as(f32, 10), stroke.radius);

    const narrow = try CanvasMarkers.callout(&graphics, .{ .x = 0, .y = 0, .width = 20, .height = 100 }, "Title", "Detail", renderer.Color.black, renderer.Color.white);
    try std.testing.expectEqual(@as(f32, 0), narrow.width);
    try std.testing.expectEqual(@as(usize, 1), display_list.count());
}
