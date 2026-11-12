//! A view tree drawn to an image with no window, and the image encoded as a
//! BMP: the headless `--screenshot` of the gallery and the apps.

const std = @import("std");
const log = std.log.scoped(.ziggui_screenshot);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Renders a body to pixels with the software rasterizer, over the same view
/// tree a window draws, and encodes them as a BMP.
///
/// For checking a layout without a display (`--screenshot`), and for tests.
/// The rasterizer is deterministic, so a refactor can be checked byte for byte.
pub const Screenshot = struct {
    const Self = @This();

    /// Builds `body` over `state` for `options.frames` frames, as a window
    /// would, and draws the last at `options.width` × `options.height` points,
    /// one pixel per point. Each frame publishes the theme and the size as the
    /// window's (`BuildScope.setTheme`, `setViewport`); the size stays published.
    ///
    /// - `allocator`: allocator for the frames and the image.
    /// - `state`: what `body` builds from, a pointer.
    /// - `body`: builds the tree from `state`.
    /// - `options`: the size, theme and frame count.
    /// - Returns: the image as RGBA8, rows top-down, owned by the caller;
    ///   propagates allocation and rendering failure.
    pub fn render(allocator: std.mem.Allocator, state: anytype, body: *const fn (@TypeOf(state)) mod.View, options: mod.ScreenshotOptions) ![]u8 {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        const frame = try mod.ScreenshotFrame.create(allocator, options);
        defer frame.destroy();
        _ = try frame.build(state, body);
        return frame.rasterize();
    }

    /// Encodes RGBA8 pixels as a 24-bit BMP.
    ///
    /// - `allocator`: allocator for the file's bytes.
    /// - `rgba`: the pixels, rows top-down.
    /// - `width`: the image's width.
    /// - `height`: the image's height.
    /// - Returns: the file's bytes, owned by the caller; `error.SizeMismatch`
    ///   when `rgba` is not `width` × `height` pixels; propagates allocation failure.
    pub fn bmp(allocator: std.mem.Allocator, rgba: []const u8, width: u32, height: u32) ![]u8 {
        if (rgba.len != @as(usize, width) * height * 4) return error.SizeMismatch;
        const stride = width * 3 + (4 - (width * 3) % 4) % 4;
        const size = 54 + stride * height;
        const out = try allocator.alloc(u8, size);
        @memset(out, 0);
        out[0] = 'B';
        out[1] = 'M';
        std.mem.writeInt(u32, out[2..6], size, .little);
        std.mem.writeInt(u32, out[10..14], 54, .little);
        std.mem.writeInt(u32, out[14..18], 40, .little);
        std.mem.writeInt(i32, out[18..22], @intCast(width), .little);
        std.mem.writeInt(i32, out[22..26], @intCast(height), .little);
        std.mem.writeInt(u16, out[26..28], 1, .little);
        std.mem.writeInt(u16, out[28..30], 24, .little);
        std.mem.writeInt(u32, out[34..38], stride * height, .little);
        for (0..height) |row| {
            // BMP rows go bottom-up.
            const line = out[54 + (height - 1 - row) * stride ..];
            for (0..width) |column| {
                const pixel = rgba[(row * width + column) * 4 ..];
                line[column * 3 + 0] = pixel[2];
                line[column * 3 + 1] = pixel[1];
                line[column * 3 + 2] = pixel[0];
            }
        }
        return out;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// A body for the tests: a red top half over the theme's background, counting its builds.
const Probe = struct {
    const Self = @This();

    /// How many times `body` has built.
    builds: u32 = 0,

    /// A red bar across the top half.
    ///
    /// - `self`: the probe.
    /// - Returns: the tree.
    fn body(self: *Self) mod.View {
        self.builds += 1;
        return mod.VStack(.{ mod.Rectangle(renderer.Color.red).frame(6, 2), mod.Spacer() });
    }
};

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Screenshot);
}

test "a screenshot builds each frame and draws the last as RGBA8" {
    const allocator = std.testing.allocator;
    const previous = mod.BuildScope.shared().viewport();
    defer mod.BuildScope.shared().setViewport(previous.width, previous.height);
    const theme = renderer.MacosTheme.light;

    var probe: Probe = .{};
    const rgba = try Screenshot.render(allocator, &probe, Probe.body, .{ .width = 6, .height = 4, .theme = theme, .frames = 3 });
    defer allocator.free(rgba);

    try std.testing.expectEqual(@as(u32, 3), probe.builds);
    try std.testing.expectEqual(@as(usize, 6 * 4 * 4), rgba.len);
    // The red bar on the top rows, the window's background below it.
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, rgba[(1 * 6 + 2) * 4 ..][0..4]);
    const background = theme.colors.window_background.toRgba8();
    try std.testing.expectEqualSlices(u8, &.{ background.r, background.g, background.b }, rgba[(3 * 6 + 2) * 4 ..][0..3]);
    // The size is published as the window's.
    try std.testing.expectEqual(@as(f32, 6), mod.BuildScope.shared().viewport().width);
}

test "a screenshot always draws at least one frame" {
    const allocator = std.testing.allocator;
    const previous = mod.BuildScope.shared().viewport();
    defer mod.BuildScope.shared().setViewport(previous.width, previous.height);

    var probe: Probe = .{};
    const rgba = try Screenshot.render(allocator, &probe, Probe.body, .{ .width = 2, .height = 2, .theme = renderer.MacosTheme.light, .frames = 0 });
    defer allocator.free(rgba);
    try std.testing.expectEqual(@as(u32, 1), probe.builds);
}

test "a BMP holds the pixels bottom-up, BGR, rows padded to four bytes" {
    const allocator = std.testing.allocator;

    // Two rows of three pixels: red, green, blue, then black, white, gray.
    const rgba = [_]u8{
        255, 0, 0, 255, 0,   255, 0,   255, 0,   0,   255, 255,
        0,   0, 0, 255, 255, 255, 255, 255, 128, 128, 128, 255,
    };
    const image = try Screenshot.bmp(allocator, &rgba, 3, 2);
    defer allocator.free(image);

    // A 9-byte row pads to 12.
    try std.testing.expectEqual(@as(usize, 54 + 12 * 2), image.len);
    try std.testing.expectEqualStrings("BM", image[0..2]);
    try std.testing.expectEqual(@as(u32, @intCast(image.len)), std.mem.readInt(u32, image[2..6], .little));
    try std.testing.expectEqual(@as(i32, 3), std.mem.readInt(i32, image[18..22], .little));
    try std.testing.expectEqual(@as(i32, 2), std.mem.readInt(i32, image[22..26], .little));
    try std.testing.expectEqual(@as(u16, 24), std.mem.readInt(u16, image[28..30], .little));
    // The bottom row comes first.
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255, 255, 255, 128, 128, 128, 0, 0, 0 }, image[54..66]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 0, 255, 0, 255, 0, 0, 0, 0, 0 }, image[66..78]);
    // Pixels that are not the size given are refused, not read past.
    try std.testing.expectError(error.SizeMismatch, Screenshot.bmp(allocator, rgba[0..4], 3, 2));
}
