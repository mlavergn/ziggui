//! Paints text and icon glyphs into a `Canvas` as tinted glyph-coverage quads,
//! with the coverage gamma the app sets per frame.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_painter);
const mod = @import("module.zig");

/// Emits glyph commands for strings and icons.
pub const TextPainter = struct {
    const Self = @This();

    /// Coverage gamma applied to every glyph the text path emits (see the `glyph`
    /// `DrawCommand`). 1.0 is a no-op — the default — so headless tests and callers
    /// that never set it render exactly as before. The app sets it per frame from
    /// the theme background (dark → < 1 to gamma-correct light text; light → 1.0).
    coverage_gamma: f32 = 1,

    /// The painter of the current thread. Thread-local so a render thread never
    /// races the main loop, mirroring the `BuildScope`
    /// pattern.
    threadlocal var shared_painter: Self = .{};

    /// The current thread's painter.
    ///
    /// - Returns: the shared painter.
    pub fn shared() *Self {
        return &shared_painter;
    }

    /// Set the coverage gamma for subsequently emitted glyphs. See `coverage_gamma`.
    ///
    /// - `self`: the painter.
    /// - `coverage_gamma`: the exponent (1.0 = untouched).
    pub fn setGamma(self: *Self, coverage_gamma: f32) void {
        self.coverage_gamma = coverage_gamma;
    }

    /// The gamma currently applied to emitted glyphs (1.0 = untouched).
    ///
    /// - `self`: the painter.
    /// - Returns: the exponent.
    pub fn gamma(self: *const Self) f32 {
        return self.coverage_gamma;
    }

    /// Paint `text` into `canvas` with its top-left at `origin`, at `pixel_size`,
    /// tinted `color`, using `cache` for glyph bitmaps.
    ///
    /// - `self`: the painter.
    /// - `canvas`: the canvas painted into.
    /// - `cache`: the glyph cache of the text's face.
    /// - `text`: the UTF-8 line.
    /// - `pixel_size`: the em size in pixels.
    /// - `color`: the tint.
    /// - `origin`: the line's top-left.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawText(
        self: *const Self,
        canvas: *mod.Canvas,
        cache: *mod.GlyphCache,
        text: []const u8,
        pixel_size: f32,
        color: mod.Color,
        origin: mod.Point,
    ) !void {
        const face = cache.face;
        const shaper = mod.TextShaper.init(face);
        const baseline = origin.y + shaper.ascentPixels(pixel_size);
        const glyphs = try shaper.layoutLine(canvas.allocator, text, pixel_size, origin.x);
        defer canvas.allocator.free(glyphs);
        for (glyphs) |placed| {
            const raster = try cache.getFace(placed.face, placed.glyph, pixel_size);
            if (raster.width == 0 or raster.height == 0) continue; // whitespace
            const rect = mod.Rect{
                .x = placed.x + @as(f32, @floatFromInt(raster.left)),
                .y = baseline - @as(f32, @floatFromInt(raster.top)),
                .width = @floatFromInt(raster.width),
                .height = @floatFromInt(raster.height),
            };
            try canvas.drawGlyphGamma(rect, color, .{
                .width = raster.width,
                .height = raster.height,
                .data = raster.data,
            }, self.coverage_gamma);
        }
    }

    /// Like `drawText`, but rasterizes glyph coverage at `pixel_size * scale`
    /// (device resolution) while emitting the glyph quad in *point* space (sizes and
    /// bearings divided by `scale`). A later uniform ×`scale` of the command list
    /// then lands the quad on device pixels with a 1:1 coverage mapping — crisp
    /// HiDPI text instead of a stretched low-res glyph. See `view.renderScaled`.
    ///
    /// - `self`: the painter.
    /// - `canvas`: the canvas painted into.
    /// - `cache`: the glyph cache of the text's face.
    /// - `text`: the UTF-8 line.
    /// - `pixel_size`: the em size in points.
    /// - `scale`: device pixels per point.
    /// - `color`: the tint.
    /// - `origin`: the line's top-left.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawTextScaled(
        self: *const Self,
        canvas: *mod.Canvas,
        cache: *mod.GlyphCache,
        text: []const u8,
        pixel_size: f32,
        scale: f32,
        color: mod.Color,
        origin: mod.Point,
    ) !void {
        const face = cache.face;
        const device_pixel_size = pixel_size * scale;
        const shaper = mod.TextShaper.init(face);
        const baseline = origin.y + shaper.ascentPixels(pixel_size);
        const glyphs = try shaper.layoutLine(canvas.allocator, text, pixel_size, origin.x);
        defer canvas.allocator.free(glyphs);
        for (glyphs) |placed| {
            const raster = try cache.getFace(placed.face, placed.glyph, device_pixel_size);
            if (raster.width == 0 or raster.height == 0) continue; // whitespace
            const rect = mod.Rect{
                .x = placed.x + @as(f32, @floatFromInt(raster.left)) / scale,
                .y = baseline - @as(f32, @floatFromInt(raster.top)) / scale,
                .width = @as(f32, @floatFromInt(raster.width)) / scale,
                .height = @as(f32, @floatFromInt(raster.height)) / scale,
            };
            try canvas.drawGlyphGamma(rect, color, .{
                .width = raster.width,
                .height = raster.height,
                .data = raster.data,
            }, self.coverage_gamma);
        }
    }

    /// Draw a single icon glyph (`codepoint` in the icon font's PUA) centered in
    /// `box`, sized to `box`'s smaller side, tinted `color`. Coverage is rasterized
    /// at device resolution (`box side * scale`) but the quad is emitted in point
    /// space, so the later ×`scale` in `view.renderScaled` lands it crisply — the
    /// same HiDPI trick as `drawTextScaled`. No-op for a blank glyph, and for a
    /// box or scale that leaves no positive size.
    ///
    /// - `self`: the painter.
    /// - `canvas`: the canvas painted into.
    /// - `cache`: the icon font's glyph cache.
    /// - `codepoint`: the icon's codepoint.
    /// - `box`: the rect the icon is centered in.
    /// - `scale`: device pixels per point.
    /// - `color`: the tint.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawIcon(
        self: *const Self,
        canvas: *mod.Canvas,
        cache: *mod.GlyphCache,
        codepoint: u21,
        box: mod.Rect,
        scale: f32,
        color: mod.Color,
    ) !void {
        const face = cache.face;
        const side = @min(box.width, box.height);
        // An empty or inverted box, or a scale that is not positive, draws nothing.
        if (!(side * scale > 0)) return;
        // Icon glyphs are designed on the em square, so rasterize the glyph at the
        // box side (em == side) and center the inked bitmap within the box.
        const raster = try cache.get(face.glyphIndex(codepoint), side * scale);
        if (raster.width == 0 or raster.height == 0) return; // blank / missing glyph
        const width = @as(f32, @floatFromInt(raster.width)) / scale;
        const height = @as(f32, @floatFromInt(raster.height)) / scale;
        const rect = mod.Rect{
            .x = box.x + (box.width - width) / 2,
            .y = box.y + (box.height - height) / 2,
            .width = width,
            .height = height,
        };
        try canvas.drawGlyphGamma(rect, color, .{
            .width = raster.width,
            .height = raster.height,
            .data = raster.data,
        }, self.coverage_gamma);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "drawIcon: inks pixels for a real icon and is a no-op for a blank slot" {
    const font = mod.Font.icons();
    var cache = mod.GlyphCache.init(std.testing.allocator, &font.face);
    defer cache.deinit();
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const box = mod.Rect{ .x = 0, .y = 0, .width = 24, .height = 24 };
    try TextPainter.shared().drawIcon(&canvas, &cache, 0xE0F2, box, 1, mod.Color.black); // heart
    try std.testing.expect(canvas.count() == 1);
    canvas.clearCommands();
    // A codepoint not in the subset maps to .notdef/blank → no command.
    try TextPainter.shared().drawIcon(&canvas, &cache, 0x0041, box, 1, mod.Color.black); // 'A'
    try std.testing.expect(canvas.count() == 0);
}

test "drawText: emits one glyph command per visible character" {
    const font = mod.Font.default();
    var cache = mod.GlyphCache.init(std.testing.allocator, &font.face);
    defer cache.deinit();
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try TextPainter.shared().drawText(&canvas, &cache, "AB", 32, mod.Color.black, .{ .x = 0, .y = 0 });
    // two visible glyphs -> two glyph commands
    try std.testing.expectEqual(@as(usize, 2), canvas.count());
    try std.testing.expect(canvas.commands.items[0] == .glyph);
}

test "drawText: actually inks pixels when rasterized" {
    const font = mod.Font.default();
    var cache = mod.GlyphCache.init(std.testing.allocator, &font.face);
    defer cache.deinit();
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try TextPainter.shared().drawText(&canvas, &cache, "A", 48, mod.Color.black, .{ .x = 2, .y = 2 });

    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 64, 64);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.white);
    try mod.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);

    // count dark pixels — the letter 'A' should ink a meaningful number
    var dark: u32 = 0;
    for (framebuffer.pixels) |pixel| {
        if (pixel.luminance() < 0.5) dark += 1;
    }
    try std.testing.expect(dark > 20);
}

test "drawText: renders an emoji through the fallback face" {
    var font = mod.Font.default();
    var emoji_font = mod.Font.emoji();
    font.face.fallback = &emoji_font.face;
    var cache = mod.GlyphCache.init(std.testing.allocator, &font.face);
    defer cache.deinit();
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    // "A😀" — one Latin glyph from Inter, one emoji from the fallback face.
    try TextPainter.shared().drawText(&canvas, &cache, "A\u{1F600}", 48, mod.Color.black, .{ .x = 0, .y = 0 });
    try std.testing.expectEqual(@as(usize, 2), canvas.count());

    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 128, 64);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.white);
    try mod.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);
    // The emoji must ink real pixels (right half of the canvas, past 'A').
    var dark: u32 = 0;
    for (0..framebuffer.height) |row| {
        for (64..framebuffer.width) |column| {
            if (framebuffer.at(@intCast(column), @intCast(row)).luminance() < 0.5) dark += 1;
        }
    }
    try std.testing.expect(dark > 20);
}

test "drawText: whitespace produces no glyph commands" {
    const font = mod.Font.default();
    var cache = mod.GlyphCache.init(std.testing.allocator, &font.face);
    defer cache.deinit();
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try TextPainter.shared().drawText(&canvas, &cache, "   ", 32, mod.Color.black, .{ .x = 0, .y = 0 });
    try std.testing.expectEqual(@as(usize, 0), canvas.count());
}

test "drawIcon and drawText: a negative, zero or NaN size draws nothing and does not panic" {
    const font = mod.Font.icons();
    var cache = mod.GlyphCache.init(std.testing.allocator, &font.face);
    defer cache.deinit();
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const painter = TextPainter.shared();
    try painter.drawIcon(&canvas, &cache, 0xE0F2, .{ .x = 0, .y = 0, .width = -4, .height = 10 }, 1, mod.Color.black);
    try painter.drawIcon(&canvas, &cache, 0xE0F2, .{ .x = 0, .y = 0, .width = 24, .height = 24 }, std.math.nan(f32), mod.Color.black);
    try painter.drawIcon(&canvas, &cache, 0xE0F2, .{ .x = 0, .y = 0, .width = 24, .height = 24 }, 0, mod.Color.black);
    const text_font = mod.Font.default();
    var text_cache = mod.GlyphCache.init(std.testing.allocator, &text_font.face);
    defer text_cache.deinit();
    try painter.drawText(&canvas, &text_cache, "Hi", -12, mod.Color.black, .{ .x = 0, .y = 0 });
    try painter.drawTextScaled(&canvas, &text_cache, "Hi", 12, std.math.nan(f32), mod.Color.black, .{ .x = 0, .y = 0 });
    try std.testing.expectEqual(@as(usize, 0), canvas.count());
}
