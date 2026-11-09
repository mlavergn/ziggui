const std = @import("std");
const log = std.log.scoped(.ziggui_screenshot);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// Renders the gallery to an image with no window: zigui's software
/// rasterizer over the same view tree the window draws.
///
/// For checking a layout without a display (`ziggui-gallery --screenshot`),
/// and for the tests.
pub const Screenshot = struct {
    const Self = @This();

    /// Draws `shown` at `width` × `height` points, one pixel per point.
    ///
    /// - `allocator`: allocator for the frame and the image.
    /// - `shown`: the gallery to draw.
    /// - `width`: the image's width.
    /// - `height`: the image's height.
    /// - Returns: the image as RGBA8, rows top-down, owned by the caller;
    ///   propagates allocation and rendering failure.
    pub fn render(allocator: std.mem.Allocator, shown: *gallery.Gallery, width: u32, height: u32) ![]u8 {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        const theme = shown.theme();
        var font = ziggui.Font.default();
        var emoji_font = ziggui.Font.emoji();
        font.face.fallback = &emoji_font.face;
        var cache = ziggui.GlyphCache.init(allocator, &font.face);
        defer cache.deinit();
        var icon_font = ziggui.Font.icons();
        var icon_cache = ziggui.GlyphCache.init(allocator, &icon_font.face);
        defer icon_cache.deinit();
        const fonts = try ziggui.FontSet.create(allocator);
        defer fonts.destroy();
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();

        // Two frames, as the window would: the first lays out the scroll
        // view, the second draws what it shows.
        var frame: usize = 0;
        while (frame < 2) : (frame += 1) {
            _ = arena.reset(.retain_capacity);
            ziggui.setThemeTokens(theme);
            ziggui.beginBuild(arena.allocator());
            const root = shown.body();
            ziggui.endBuild();

            var hits: std.ArrayList(ziggui.HitRegion) = .empty;
            var overlays: std.ArrayList(ziggui.OverlayReq) = .empty;
            var scrolls: std.ArrayList(ziggui.ScrollRegion) = .empty;
            var ctx = ziggui.Context.init(theme, &cache, arena.allocator(), &hits);
            ctx.icon_cache = &icon_cache;
            ctx.overlays = &overlays;
            ctx.scroll_regions = &scrolls;
            ctx.fonts = fonts;

            var canvas = ziggui.Canvas.init(arena.allocator());
            const full: ziggui.Rect = .{ .x = 0, .y = 0, .width = @floatFromInt(width), .height = @floatFromInt(height) };
            try canvas.fillRect(full, theme.colors.window_background);
            try ziggui.render(&ctx, root, full, &canvas);

            if (frame == 1) {
                var framebuffer = try ziggui.Framebuffer.init(allocator, width, height);
                defer framebuffer.deinit();
                framebuffer.clear(theme.colors.window_background);
                try ziggui.raster.render(allocator, &framebuffer, canvas.commands.items);
                return framebuffer.toRgba8Alloc(allocator);
            }
        }
        unreachable;
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

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Screenshot);
}

test "a screenshot encodes as a BMP of its size" {
    const allocator = std.testing.allocator;

    var shown = try gallery.Gallery.init(allocator);
    defer shown.deinit();

    const rgba = try Screenshot.render(allocator, &shown, gallery.test_width, gallery.test_height);
    defer allocator.free(rgba);
    const image = try Screenshot.bmp(allocator, rgba, gallery.test_width, gallery.test_height);
    defer allocator.free(image);

    try std.testing.expectEqualStrings("BM", image[0..2]);
    try std.testing.expectEqual(@as(u32, @intCast(image.len)), std.mem.readInt(u32, image[2..6], .little));
    // Pixels that are not the size given are refused, not read past.
    try std.testing.expectError(error.SizeMismatch, Screenshot.bmp(allocator, rgba[0..4], gallery.test_width, gallery.test_height));
}
