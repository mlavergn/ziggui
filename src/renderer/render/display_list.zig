//! DisplayList: a retained 2D draw-command list. Components paint into a `DisplayList` by
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
const log = std.log.scoped(.ziggui_display_list);
const mod = @import("module.zig");

/// A retained list of draw commands.
pub const DisplayList = struct {
    const Self = @This();

    /// The commands, in paint order.
    commands: std.ArrayList(mod.DrawCommand) = .empty,
    /// The allocator the command list grows with.
    allocator: std.mem.Allocator,

    /// An empty display list.
    ///
    /// - `allocator`: allocator for the command list.
    /// - Returns: the display list.
    pub fn init(allocator: std.mem.Allocator) Self {
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Free the command list.
    ///
    /// - `self`: the display list.
    pub fn deinit(self: *Self) void {
        self.commands.deinit(self.allocator);
    }

    /// Drop every command, keeping the storage.
    ///
    /// - `self`: the display list.
    pub fn clearCommands(self: *Self) void {
        self.commands.clearRetainingCapacity();
    }

    /// How many commands the display list holds.
    ///
    /// - `self`: the display list.
    /// - Returns: the count.
    pub fn count(self: *const Self) usize {
        return self.commands.items.len;
    }

    /// Append a command.
    ///
    /// - `self`: the display list.
    /// - `command`: the command.
    /// - Returns: nothing; propagates allocation failure.
    pub fn push(self: *Self, command: mod.DrawCommand) !void {
        try self.commands.append(self.allocator, command);
    }

    // -- convenience builders -------------------------------------------------

    /// Fill a rect with a solid color.
    ///
    /// - `self`: the display list.
    /// - `rect`: the rect.
    /// - `color`: the fill.
    /// - Returns: nothing; propagates allocation failure.
    pub fn fillRect(self: *Self, rect: mod.Rect, color: mod.Color) !void {
        try self.push(.{ .fillRoundedRect = .{ .rect = rect, .radius = 0, .color = color } });
    }

    /// Fill a rounded rect with a solid color.
    ///
    /// - `self`: the display list.
    /// - `rect`: the rect.
    /// - `radius`: the corner radius.
    /// - `color`: the fill.
    /// - Returns: nothing; propagates allocation failure.
    pub fn fillRoundedRect(self: *Self, rect: mod.Rect, radius: f32, color: mod.Color) !void {
        try self.push(.{ .fillRoundedRect = .{ .rect = rect, .radius = radius, .color = color } });
    }

    /// Stroke a rounded rect's outline.
    ///
    /// - `self`: the display list.
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
    /// - `self`: the display list.
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
    /// - `self`: the display list.
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
    /// - `self`: the display list.
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
    /// - `self`: the display list.
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
    /// - `self`: the display list.
    /// - `rect`: where the image is drawn.
    /// - `image`: the pixels.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawImage(self: *Self, rect: mod.Rect, image: mod.Image) !void {
        try self.push(.{ .image = .{ .rect = rect, .image = image } });
    }

    /// Draw a picture that changes from frame to frame (a video's) stretched
    /// over a rect; the GPU backend uploads it only when `generation` changes.
    ///
    /// - `self`: the display list.
    /// - `rect`: where the picture is drawn.
    /// - `image`: the pixels, valid until the frame is drawn.
    /// - `key`: what the pictures come from (a player), stable while it lives.
    /// - `generation`: changes with each new picture from `key`.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawVideoFrame(self: *Self, rect: mod.Rect, image: mod.Image, key: usize, generation: u64) !void {
        try self.push(.{ .videoFrame = .{ .rect = rect, .image = image, .key = key, .generation = generation } });
    }

    /// Frost what is already drawn beneath a rect.
    ///
    /// - `self`: the display list.
    /// - `rect`: the region.
    /// - `radius`: the region's corner radius.
    /// - `sigma`: the blur's extent.
    /// - `tint`: the color laid over the blur.
    /// - Returns: nothing; propagates allocation failure.
    pub fn blurRect(self: *Self, rect: mod.Rect, radius: f32, sigma: f32, tint: mod.Color) !void {
        try self.push(.{ .blurRect = .{ .rect = rect, .radius = radius, .sigma = sigma, .tint = tint } });
    }

    /// Erase what is already drawn inside a rect back to transparent, the
    /// window's backdrop (a native video layer) showing through.
    ///
    /// - `self`: the display list.
    /// - `rect`: the region.
    /// - `radius`: the region's corner radius.
    /// - Returns: nothing; propagates allocation failure.
    pub fn eraseRect(self: *Self, rect: mod.Rect, radius: f32) !void {
        try self.push(.{ .eraseRect = .{ .rect = rect, .radius = radius } });
    }

    /// Push a clip region.
    ///
    /// - `self`: the display list.
    /// - `rect`: the clip's rect.
    /// - `radius`: the clip's corner radius.
    /// - Returns: nothing; propagates allocation failure.
    pub fn pushClip(self: *Self, rect: mod.Rect, radius: f32) !void {
        try self.push(.{ .pushClip = .{ .rect = rect, .radius = radius } });
    }

    /// Pop the innermost clip region.
    ///
    /// - `self`: the display list.
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

test "DisplayList: records commands in order" {
    var display_list = mod.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    try display_list.fillRect(.{ .x = 0, .y = 0, .width = 10, .height = 10 }, mod.Color.red);
    try display_list.strokeRoundedRect(.{ .x = 0, .y = 0, .width = 10, .height = 10 }, 4, 2, mod.Color.blue);
    try std.testing.expectEqual(@as(usize, 2), display_list.count());
    try std.testing.expect(display_list.commands.items[0] == .fillRoundedRect);
    try std.testing.expect(display_list.commands.items[1] == .strokeRoundedRect);
}

test "DisplayList: clip push/pop and clear" {
    var display_list = mod.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    try display_list.pushClip(.{ .x = 0, .y = 0, .width = 5, .height = 5 }, 0);
    try display_list.popClip();
    try std.testing.expectEqual(@as(usize, 2), display_list.count());
    display_list.clearCommands();
    try std.testing.expectEqual(@as(usize, 0), display_list.count());
}

test "DisplayList: fillCircle expands to a rounded rect" {
    var display_list = mod.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    try display_list.fillCircle(.{ .x = 50, .y = 50 }, 10, mod.Color.green);
    const command = display_list.commands.items[0].fillRoundedRect;
    try std.testing.expectEqual(mod.Rect{ .x = 40, .y = 40, .width = 20, .height = 20 }, command.rect);
    try std.testing.expectEqual(@as(f32, 10), command.radius);
}

test "DisplayList: blurRect records a blur command" {
    var display_list = mod.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    try display_list.blurRect(.{ .x = 0, .y = 0, .width = 10, .height = 10 }, 4, 6, mod.Color.white.withAlpha(0.5));
    try std.testing.expect(display_list.commands.items[0] == .blurRect);
    try std.testing.expectEqual(@as(f32, 6), display_list.commands.items[0].blurRect.sigma);
}
