//! A player's latest frame, drawn *under* the hole a `VideoPlayer` erased in
//! the window's surface, for a platform whose player cannot show its picture
//! behind the window itself (Windows: SDL's swapchain is opaque to the
//! desktop compositor). The renderer fills only what the frame left
//! transparent, so the controls and overlays painted over the hole stay on
//! top, as they do over macOS's `AVPlayerLayer`.

const std = @import("std");
const log = std.log.scoped(.ziggui_video_underlay);
const renderer = @import("renderer");

/// One frame to draw under the surface, and where.
pub const VideoUnderlay = struct {
    const Self = @This();

    /// What the frame comes from (its player), stable while it lives: the
    /// GPU keeps one texture per key.
    key: usize,
    /// Bumped with each new frame, so an unchanged one is not uploaded again.
    generation: u64,
    /// The frame's width, in pixels; 0 before the first frame.
    width: u32 = 0,
    /// The frame's height, in pixels.
    height: u32 = 0,
    /// Four bytes (R, G, B, A) per pixel, rows top-down, opaque; owned by the
    /// player and valid until its next frame.
    pixels: []const u8 = &.{},
    /// The `VideoPlayer`'s whole frame, in points: filled black where the
    /// picture does not reach.
    frame: renderer.Rect,
    /// Where the picture goes, aspect-fit inside `frame`, in points.
    picture: renderer.Rect,

    /// Fills what the surface left transparent inside the frame with the
    /// picture (nearest sample) or black: `under` compositing, so a partly
    /// erased edge blends and an opaque pixel is untouched.
    ///
    /// - `self`: the underlay.
    /// - `rgba`: the window's pixels, RGBA8 with premultiplied holes.
    /// - `width`: their width.
    /// - `height`: their height.
    /// - `scale`: pixels per point.
    pub fn composite(self: *const Self, rgba: []u8, width: u32, height: u32, scale: f32) void {
        const left = Self.clampPixel(self.frame.x * scale, width);
        const top = Self.clampPixel(self.frame.y * scale, height);
        const right = Self.clampPixel((self.frame.x + self.frame.width) * scale, width);
        const bottom = Self.clampPixel((self.frame.y + self.frame.height) * scale, height);
        const picture_left = self.picture.x * scale;
        const picture_top = self.picture.y * scale;
        const picture_width = self.picture.width * scale;
        const picture_height = self.picture.height * scale;
        const has_picture = self.width > 0 and self.height > 0 and self.pixels.len >= @as(usize, self.width) * self.height * 4 and picture_width > 0 and picture_height > 0;
        var y = top;
        while (y < bottom) : (y += 1) {
            const row = rgba[@as(usize, y) * width * 4 ..][0 .. @as(usize, width) * 4];
            const source_y: f32 = (@as(f32, @floatFromInt(y)) + 0.5 - picture_top) / picture_height;
            var x = left;
            while (x < right) : (x += 1) {
                const pixel = row[@as(usize, x) * 4 ..][0..4];
                const coverage = pixel[3];
                if (coverage == 255) continue;
                var source = [4]u8{ 0, 0, 0, 255 };
                if (has_picture) {
                    const source_x: f32 = (@as(f32, @floatFromInt(x)) + 0.5 - picture_left) / picture_width;
                    if (source_x >= 0 and source_x < 1 and source_y >= 0 and source_y < 1) {
                        const column: usize = @intFromFloat(source_x * @as(f32, @floatFromInt(self.width)));
                        const line: usize = @intFromFloat(source_y * @as(f32, @floatFromInt(self.height)));
                        const offset = (line * self.width + column) * 4;
                        source = self.pixels[offset..][0..4].*;
                    }
                }
                const uncovered: u32 = 255 - @as(u32, coverage);
                for (0..3) |channel| {
                    pixel[channel] = @intCast(@min(255, @as(u32, pixel[channel]) + (@as(u32, source[channel]) * uncovered + 127) / 255));
                }
                pixel[3] = 255;
            }
        }
    }

    /// The largest centered rect inside `frame` with the picture's aspect ratio.
    ///
    /// - `frame`: the view's frame.
    /// - `width`: the picture's width, in pixels.
    /// - `height`: its height.
    /// - Returns: where the picture goes; `frame` itself while the size is unknown.
    pub fn aspectFit(frame: renderer.Rect, width: u32, height: u32) renderer.Rect {
        if (width == 0 or height == 0 or frame.width <= 0 or frame.height <= 0) return frame;
        const picture_width: f32 = @floatFromInt(width);
        const picture_height: f32 = @floatFromInt(height);
        const scale = @min(frame.width / picture_width, frame.height / picture_height);
        const fitted_width = picture_width * scale;
        const fitted_height = picture_height * scale;
        return .{ .x = frame.x + (frame.width - fitted_width) / 2, .y = frame.y + (frame.height - fitted_height) / 2, .width = fitted_width, .height = fitted_height };
    }

    /// Converts a coordinate to a pixel index clamped to the image.
    ///
    /// - `value`: the coordinate, in pixels.
    /// - `limit`: the image's size along it.
    /// - Returns: the index, from 0 to `limit`.
    fn clampPixel(value: f32, limit: u32) u32 {
        if (!(value > 0)) return 0;
        const rounded: u32 = @intFromFloat(@min(@round(value), @as(f32, @floatFromInt(limit))));
        return rounded;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "video underlay: the picture fills only the hole, black outside the picture" {
    // A 4×2 window, all white, with the right half erased.
    var rgba: [4 * 2 * 4]u8 = @splat(255);
    for (0..2) |y| for (2..4) |x| {
        @memcpy(rgba[(y * 4 + x) * 4 ..][0..4], &[4]u8{ 0, 0, 0, 0 });
    };
    // One red pixel, shown in the hole's top half only (its bottom is letterbox).
    const red = [4]u8{ 255, 0, 0, 255 };
    const underlay = VideoUnderlay{
        .key = 1,
        .generation = 1,
        .width = 1,
        .height = 1,
        .pixels = &red,
        .frame = .{ .x = 0, .y = 0, .width = 4, .height = 2 },
        .picture = .{ .x = 0, .y = 0, .width = 4, .height = 1 },
    };
    underlay.composite(&rgba, 4, 2, 1);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, rgba[0..4]); // opaque: untouched
    try std.testing.expectEqualSlices(u8, &red, rgba[(0 * 4 + 3) * 4 ..][0..4]); // hole, picture
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255 }, rgba[(1 * 4 + 3) * 4 ..][0..4]); // hole, letterbox
}

test "video underlay: aspect fit centers the picture" {
    const fitted = VideoUnderlay.aspectFit(.{ .x = 0, .y = 0, .width = 200, .height = 100 }, 100, 100);
    try std.testing.expectEqual(@as(f32, 50), fitted.x);
    try std.testing.expectEqual(@as(f32, 100), fitted.width);
    try std.testing.expectEqual(@as(f32, 100), fitted.height);
}
