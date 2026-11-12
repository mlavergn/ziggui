//! Canvas: a retained 2D draw-command list. Components paint into a `Canvas` by
//! appending high-level commands (filled/stroked rounded rects, gradients,
//! lines, glyph quads, images, clip push/pop). The command list is the single
//! interface consumed by *both* backends:
//!
//!   * the pure-Zig software rasterizer (`Rasterizer`) — used for tests and
//!     headless/CI rendering, and
//!   * the GPU backend (`sdl/gpu/`, through `GpuScene`) — used for on-screen
//!     display.
//!
//! Keeping drawing as data (not immediate GPU calls) is what lets the entire
//! visual layer be unit-tested without a window or GPU.

const std = @import("std");
const log = std.log.scoped(.ziggui_canvas);
const mod = @import("module.zig");

/// A retained list of draw commands.
pub const Canvas = struct {
    const Self = @This();

    /// The commands, in paint order.
    commands: std.ArrayList(mod.DrawCommand) = .empty,
    /// The allocator the command list grows with.
    allocator: std.mem.Allocator,

    /// An empty canvas.
    ///
    /// - `allocator`: allocator for the command list.
    /// - Returns: the canvas.
    pub fn init(allocator: std.mem.Allocator) Self {
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Free the command list.
    ///
    /// - `self`: the canvas.
    pub fn deinit(self: *Self) void {
        self.commands.deinit(self.allocator);
    }

    /// Drop every command, keeping the storage.
    ///
    /// - `self`: the canvas.
    pub fn clearCommands(self: *Self) void {
        self.commands.clearRetainingCapacity();
    }

    /// How many commands the canvas holds.
    ///
    /// - `self`: the canvas.
    /// - Returns: the count.
    pub fn count(self: *const Self) usize {
        return self.commands.items.len;
    }

    /// Append a command.
    ///
    /// - `self`: the canvas.
    /// - `command`: the command.
    /// - Returns: nothing; propagates allocation failure.
    pub fn push(self: *Self, command: mod.DrawCommand) !void {
        try self.commands.append(self.allocator, command);
    }

    // -- convenience builders -------------------------------------------------

    /// Fill a rect with a solid color.
    ///
    /// - `self`: the canvas.
    /// - `rect`: the rect.
    /// - `color`: the fill.
    /// - Returns: nothing; propagates allocation failure.
    pub fn fillRect(self: *Self, rect: mod.Rect, color: mod.Color) !void {
        try self.push(.{ .fillRoundedRect = .{ .rect = rect, .radius = 0, .color = color } });
    }

    /// Fill a rounded rect with a solid color.
    ///
    /// - `self`: the canvas.
    /// - `rect`: the rect.
    /// - `radius`: the corner radius.
    /// - `color`: the fill.
    /// - Returns: nothing; propagates allocation failure.
    pub fn fillRoundedRect(self: *Self, rect: mod.Rect, radius: f32, color: mod.Color) !void {
        try self.push(.{ .fillRoundedRect = .{ .rect = rect, .radius = radius, .color = color } });
    }

    /// Stroke a rounded rect's outline.
    ///
    /// - `self`: the canvas.
    /// - `rect`: the rect.
    /// - `radius`: the corner radius.
    /// - `width`: the stroke's width.
    /// - `color`: the stroke color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn strokeRoundedRect(self: *Self, rect: mod.Rect, radius: f32, width: f32, color: mod.Color) !void {
        try self.push(.{ .strokeRoundedRect = .{ .rect = rect, .radius = radius, .width = width, .color = color } });
    }

    /// Fill a circle.
    ///
    /// - `self`: the canvas.
    /// - `center`: the circle's center.
    /// - `radius`: the circle's radius.
    /// - `color`: the fill.
    /// - Returns: nothing; propagates allocation failure.
    pub fn fillCircle(self: *Self, center: mod.Point, radius: f32, color: mod.Color) !void {
        try self.fillRoundedRect(
            .{ .x = center.x - radius, .y = center.y - radius, .width = 2 * radius, .height = 2 * radius },
            radius,
            color,
        );
    }

    /// Draw a line segment.
    ///
    /// - `self`: the canvas.
    /// - `start`: one end.
    /// - `end`: the other end.
    /// - `width`: the line's width.
    /// - `color`: the line's color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn line(self: *Self, start: mod.Point, end: mod.Point, width: f32, color: mod.Color) !void {
        try self.push(.{ .line = .{ .start = start, .end = end, .width = width, .color = color } });
    }

    /// Draw a tinted coverage mask.
    ///
    /// - `self`: the canvas.
    /// - `rect`: where the mask is drawn.
    /// - `color`: the tint.
    /// - `coverage`: the mask.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawGlyph(self: *Self, rect: mod.Rect, color: mod.Color, coverage: mod.Coverage) !void {
        try self.push(.{ .glyph = .{ .rect = rect, .color = color, .coverage = coverage } });
    }

    /// Like `drawGlyph` but with an explicit coverage `gamma` (see
    /// `GlyphCommand`). The text path uses this to apply the active
    /// `TextPainter.setGamma`.
    ///
    /// - `self`: the canvas.
    /// - `rect`: where the mask is drawn.
    /// - `color`: the tint.
    /// - `coverage`: the mask.
    /// - `gamma`: the coverage exponent.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawGlyphGamma(self: *Self, rect: mod.Rect, color: mod.Color, coverage: mod.Coverage, gamma: f32) !void {
        try self.push(.{ .glyph = .{ .rect = rect, .color = color, .coverage = coverage, .gamma = gamma } });
    }

    /// Draw an image stretched over a rect.
    ///
    /// - `self`: the canvas.
    /// - `rect`: where the image is drawn.
    /// - `image`: the pixels.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawImage(self: *Self, rect: mod.Rect, image: mod.Image) !void {
        try self.push(.{ .image = .{ .rect = rect, .image = image } });
    }

    /// Frost what is already drawn beneath a rect.
    ///
    /// - `self`: the canvas.
    /// - `rect`: the region.
    /// - `radius`: the region's corner radius.
    /// - `sigma`: the blur's extent.
    /// - `tint`: the color laid over the blur.
    /// - Returns: nothing; propagates allocation failure.
    pub fn blurRect(self: *Self, rect: mod.Rect, radius: f32, sigma: f32, tint: mod.Color) !void {
        try self.push(.{ .blurRect = .{ .rect = rect, .radius = radius, .sigma = sigma, .tint = tint } });
    }

    /// Push a clip region.
    ///
    /// - `self`: the canvas.
    /// - `rect`: the clip's rect.
    /// - `radius`: the clip's corner radius.
    /// - Returns: nothing; propagates allocation failure.
    pub fn pushClip(self: *Self, rect: mod.Rect, radius: f32) !void {
        try self.push(.{ .pushClip = .{ .rect = rect, .radius = radius } });
    }

    /// Pop the innermost clip region.
    ///
    /// - `self`: the canvas.
    /// - Returns: nothing; propagates allocation failure.
    pub fn popClip(self: *Self) !void {
        try self.push(.popClip);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Canvas: records commands in order" {
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.fillRect(.{ .x = 0, .y = 0, .width = 10, .height = 10 }, mod.Color.red);
    try canvas.strokeRoundedRect(.{ .x = 0, .y = 0, .width = 10, .height = 10 }, 4, 2, mod.Color.blue);
    try std.testing.expectEqual(@as(usize, 2), canvas.count());
    try std.testing.expect(canvas.commands.items[0] == .fillRoundedRect);
    try std.testing.expect(canvas.commands.items[1] == .strokeRoundedRect);
}

test "Canvas: clip push/pop and clear" {
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.pushClip(.{ .x = 0, .y = 0, .width = 5, .height = 5 }, 0);
    try canvas.popClip();
    try std.testing.expectEqual(@as(usize, 2), canvas.count());
    canvas.clearCommands();
    try std.testing.expectEqual(@as(usize, 0), canvas.count());
}

test "Canvas: fillCircle expands to a rounded rect" {
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.fillCircle(.{ .x = 50, .y = 50 }, 10, mod.Color.green);
    const command = canvas.commands.items[0].fillRoundedRect;
    try std.testing.expectEqual(mod.Rect{ .x = 40, .y = 40, .width = 20, .height = 20 }, command.rect);
    try std.testing.expectEqual(@as(f32, 10), command.radius);
}

test "Canvas: blurRect records a blur command" {
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.blurRect(.{ .x = 0, .y = 0, .width = 10, .height = 10 }, 4, 6, mod.Color.white.withAlpha(0.5));
    try std.testing.expect(canvas.commands.items[0] == .blurRect);
    try std.testing.expectEqual(@as(f32, 6), canvas.commands.items[0].blurRect.sigma);
}
