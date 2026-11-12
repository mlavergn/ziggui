//! Pure-Zig software rasterizer. Consumes a `Canvas` command list and paints
//! into a `Framebuffer` of `Color` pixels. Shapes use a signed-distance field
//! for crisp 1px anti-aliasing, so rounded rects, circles, strokes, and lines
//! all share one coverage path. This backend exists so the entire visual layer
//! can be rendered and asserted on in tests and in headless/Docker/CI runs with
//! no GPU or window server.

const std = @import("std");
const log = std.log.scoped(.ziggui_rasterizer);
const mod = @import("module.zig");

/// One clip region on the clip stack.
const Clip = struct {
    const Self = @This();

    /// The clip's rect.
    rect: mod.Rect,
    /// The clip's corner radius.
    radius: f32,
};

/// A linear gradient's endpoints and colors.
const GradientPaint = struct {
    const Self = @This();

    /// Where the gradient is `start_color`.
    start: mod.Point,
    /// Where the gradient is `end_color`.
    end: mod.Point,
    /// The color at `start`.
    start_color: mod.Color,
    /// The color at `end`.
    end_color: mod.Color,
};

/// What a filled shape is painted with.
const Paint = union(enum) {
    const Self = @This();

    /// One color.
    solid: mod.Color,
    /// A linear gradient.
    gradient: GradientPaint,

    /// The paint's color at a pixel center.
    ///
    /// - `self`: the paint.
    /// - `pixel_x`: the pixel center's x.
    /// - `pixel_y`: the pixel center's y.
    /// - Returns: the color.
    fn colorAt(self: *const Self, pixel_x: f32, pixel_y: f32) mod.Color {
        return switch (self.*) {
            .solid => |color| color,
            .gradient => |gradient| blk: {
                const delta_x = gradient.end.x - gradient.start.x;
                const delta_y = gradient.end.y - gradient.start.y;
                const length_squared = delta_x * delta_x + delta_y * delta_y;
                if (length_squared <= 0) break :blk gradient.start_color;
                const progress = ((pixel_x - gradient.start.x) * delta_x + (pixel_y - gradient.start.y) * delta_y) / length_squared;
                break :blk gradient.start_color.lerp(gradient.end_color, std.math.clamp(progress, 0, 1));
            },
        };
    }
};

/// An integer pixel range, half-open on both axes.
const PixelBounds = struct {
    const Self = @This();

    /// The first column.
    left: u32,
    /// The first row.
    top: u32,
    /// One past the last column.
    right: u32,
    /// One past the last row.
    bottom: u32,

    /// Whether the range holds no pixel.
    ///
    /// - `self`: the bounds.
    /// - Returns: true when empty.
    fn empty(self: *const Self) bool {
        return self.right <= self.left or self.bottom <= self.top;
    }
};

/// Per-command clip analysis: the pixel bounds of `rect` (padded for AA)
/// intersected with every clip rect — so fully-clipped pixels (e.g. scrolled-
/// away content) are never visited — plus whether any per-pixel clip coverage
/// is still needed. When the padded shape sits fully inside every clip's safe
/// interior (inset by radius/2 + 1, where coverage is provably 1), the inner
/// loops skip `clipCoverage` entirely.
const ClippedBounds = struct {
    const Self = @This();

    /// The pixels worth visiting.
    bounds: PixelBounds,
    /// Whether per-pixel clip coverage is still needed.
    check_clip: bool,
};

/// Paints draw commands into a framebuffer on the CPU.
pub const Rasterizer = struct {
    const Self = @This();

    /// Allocator for the transient clip stack and blur scratch.
    allocator: std.mem.Allocator,
    /// The framebuffer painted into.
    framebuffer: *mod.Framebuffer,

    /// A rasterizer painting into `framebuffer`.
    ///
    /// - `allocator`: allocator for the transient clip stack and blur scratch.
    /// - `framebuffer`: the framebuffer painted into.
    /// - Returns: the rasterizer.
    pub fn init(allocator: std.mem.Allocator, framebuffer: *mod.Framebuffer) Self {
        const self = Self{ .allocator = allocator, .framebuffer = framebuffer };
        return self;
    }

    /// Render `commands` into the framebuffer, in order.
    ///
    /// - `self`: the rasterizer.
    /// - `commands`: the commands.
    /// - Returns: nothing; propagates allocation failure.
    pub fn render(self: *const Self, commands: []const mod.DrawCommand) !void {
        var clips: std.ArrayList(Clip) = .empty;
        defer clips.deinit(self.allocator);

        for (commands) |command| {
            switch (command) {
                .pushClip => |clip| try clips.append(self.allocator, .{ .rect = clip.rect, .radius = clip.radius }),
                .popClip => {
                    if (clips.items.len > 0) _ = clips.pop();
                },
                .fillRoundedRect => |fill| self.fillShape(clips.items, fill.rect, fill.radius, .{ .solid = fill.color }),
                .strokeRoundedRect => |stroke| self.strokeShape(clips.items, stroke.rect, stroke.radius, stroke.width, stroke.color),
                .linearGradient => |gradient| self.fillShape(clips.items, gradient.rect, gradient.radius, .{ .gradient = .{
                    .start = gradient.start,
                    .end = gradient.end,
                    .start_color = gradient.start_color,
                    .end_color = gradient.end_color,
                } }),
                .line => |segment| self.drawLine(clips.items, segment.start, segment.end, segment.width, segment.color),
                .glyph => |glyph| self.drawGlyph(clips.items, glyph.rect, glyph.color, glyph.coverage, glyph.gamma),
                .image => |image| self.drawImage(clips.items, image.rect, image.image),
                .blurRect => |blur| try self.blurRect(clips.items, blur.rect, blur.radius, blur.sigma, blur.tint),
            }
        }
    }

    /// Frosted "material" effect: separable box blur of the pixels already in
    /// the framebuffer under `rect`, composited with `tint`, written back masked
    /// by the rect shape and the clip stack. The blur reads from a scratch
    /// snapshot (never in place) so neighbouring output pixels don't feed back
    /// into each other.
    ///
    /// - `self`: the rasterizer.
    /// - `clips`: the clip stack.
    /// - `rect`: the region.
    /// - `radius`: the region's corner radius.
    /// - `sigma`: the blur's extent.
    /// - `tint`: the color laid over the blur.
    /// - Returns: nothing; propagates allocation failure.
    fn blurRect(
        self: *const Self,
        clips: []const Clip,
        rect: mod.Rect,
        radius: f32,
        sigma: f32,
        tint: mod.Color,
    ) !void {
        const framebuffer = self.framebuffer;
        // A window wider than the framebuffer already averages every pixel it
        // can reach, so cap it there (and at no less than 32, where the
        // downsampling factor below reaches its cap of 4, so the output is the
        // same as uncapped): a huge or infinite sigma then converts to an
        // integer safely, and a NaN one falls to the minimum, 1.
        const widest: f32 = @floatFromInt(@max(framebuffer.width, framebuffer.height, 32));
        const blur_radius: i64 = @intFromFloat(std.math.clamp(@round(sigma), 1.0, widest));
        const bounds = self.boundsOf(rect, 0);
        if (bounds.right <= bounds.left or bounds.bottom <= bounds.top) return;

        // Snapshot an expanded region (the output region grown by `blur_radius`,
        // clamped to the framebuffer) so every output pixel has a full
        // ±blur_radius window to sample.
        const framebuffer_width: i64 = @intCast(framebuffer.width);
        const framebuffer_height: i64 = @intCast(framebuffer.height);
        const expanded_left: i64 = @max(0, @as(i64, bounds.left) - blur_radius);
        const expanded_top: i64 = @max(0, @as(i64, bounds.top) - blur_radius);
        const expanded_right: i64 = @min(framebuffer_width, @as(i64, bounds.right) + blur_radius);
        const expanded_bottom: i64 = @min(framebuffer_height, @as(i64, bounds.bottom) + blur_radius);
        const expanded_width: usize = @intCast(expanded_right - expanded_left);
        const expanded_height: usize = @intCast(expanded_bottom - expanded_top);

        // A wide blur is smooth, so run it on a copy shrunk by `factor` per axis
        // (≤ 4) and upsample bilinearly; narrow blurs (factor == 1) stay exact.
        const factor: usize = @intCast(std.math.clamp(@divTrunc(blur_radius, 8), 1, 4));
        const small_width = (expanded_width + factor - 1) / factor;
        const small_height = (expanded_height + factor - 1) / factor;
        const source = try self.allocator.alloc(mod.Color, small_width * small_height);
        defer self.allocator.free(source);
        const scratch = try self.allocator.alloc(mod.Color, small_width * small_height);
        defer self.allocator.free(scratch);

        // Snapshot: the mean of each factor×factor block of the framebuffer.
        var small_y: usize = 0;
        while (small_y < small_height) : (small_y += 1) {
            var small_x: usize = 0;
            while (small_x < small_width) : (small_x += 1) {
                var red: f32 = 0;
                var green: f32 = 0;
                var blue: f32 = 0;
                var alpha: f32 = 0;
                var samples: f32 = 0;
                var offset_y: usize = 0;
                while (offset_y < factor and small_y * factor + offset_y < expanded_height) : (offset_y += 1) {
                    const row = (@as(usize, @intCast(expanded_top)) + small_y * factor + offset_y) * framebuffer.width + @as(usize, @intCast(expanded_left));
                    var offset_x: usize = 0;
                    while (offset_x < factor and small_x * factor + offset_x < expanded_width) : (offset_x += 1) {
                        const pixel = framebuffer.pixels[row + small_x * factor + offset_x];
                        red += pixel.r;
                        green += pixel.g;
                        blue += pixel.b;
                        alpha += pixel.a;
                        samples += 1;
                    }
                }
                source[small_y * small_width + small_x] = .{ .r = red / samples, .g = green / samples, .b = blue / samples, .a = alpha / samples };
            }
        }

        // Horizontal box pass: source -> scratch, one running sum per row.
        const small_radius: i64 = @max(1, @divTrunc(blur_radius + @as(i64, @intCast(factor / 2)), @as(i64, @intCast(factor))));
        small_y = 0;
        while (small_y < small_height) : (small_y += 1) Self.boxLine(source, scratch, small_y * small_width, 1, small_width, small_radius);

        // Vertical box pass scratch -> source, only for the columns that get
        // written back (source is free again once the horizontal pass has read it).
        var column: usize = @intCast(@divTrunc(@as(i64, bounds.left) - expanded_left, @as(i64, @intCast(factor))));
        const column_end: usize = @min(small_width, @as(usize, @intCast(@divTrunc(@as(i64, bounds.right) - expanded_left - 1, @as(i64, @intCast(factor))))) + 2);
        while (column < column_end) : (column += 1) Self.boxLine(scratch, source, column, small_width, small_height, small_radius);

        // Composite the tint and write back masked.
        var pixel_y: u32 = bounds.top;
        while (pixel_y < bounds.bottom) : (pixel_y += 1) {
            const local_y: usize = @intCast(@as(i64, pixel_y) - expanded_top);
            var pixel_x: u32 = bounds.left;
            while (pixel_x < bounds.right) : (pixel_x += 1) {
                const local_x: usize = @intCast(@as(i64, pixel_x) - expanded_left);
                const center_x = @as(f32, @floatFromInt(pixel_x)) + 0.5;
                const center_y = @as(f32, @floatFromInt(pixel_y)) + 0.5;
                const coverage = Self.fillCoverage(center_x, center_y, rect, radius) * Self.clipCoverage(clips, center_x, center_y);
                if (coverage <= 0) continue;
                const blurred = if (factor == 1) source[local_y * small_width + local_x] else Self.sampleBilinear(source, small_width, small_height, (@as(f32, @floatFromInt(local_x)) + 0.5) / @as(f32, @floatFromInt(factor)) - 0.5, (@as(f32, @floatFromInt(local_y)) + 0.5) / @as(f32, @floatFromInt(factor)) - 0.5);
                const result = tint.over(blurred);
                const index = pixel_y * framebuffer.width + pixel_x;
                framebuffer.pixels[index] = framebuffer.pixels[index].lerp(result, coverage);
            }
        }
    }

    /// Sample `buffer` bilinearly at (`x`, `y`), clamped to its edges.
    ///
    /// - `buffer`: the pixels, row-major.
    /// - `width`: the buffer's width.
    /// - `height`: the buffer's height.
    /// - `x`: the sample's x, in pixels.
    /// - `y`: the sample's y, in pixels.
    /// - Returns: the interpolated color.
    fn sampleBilinear(buffer: []const mod.Color, width: usize, height: usize, x: f32, y: f32) mod.Color {
        const clamped_x = std.math.clamp(x, 0, @as(f32, @floatFromInt(width - 1)));
        const clamped_y = std.math.clamp(y, 0, @as(f32, @floatFromInt(height - 1)));
        const left: usize = @intFromFloat(clamped_x);
        const top: usize = @intFromFloat(clamped_y);
        const right = @min(left + 1, width - 1);
        const bottom = @min(top + 1, height - 1);
        const progress_x = clamped_x - @as(f32, @floatFromInt(left));
        const progress_y = clamped_y - @as(f32, @floatFromInt(top));
        const upper = buffer[top * width + left].lerp(buffer[top * width + right], progress_x);
        const lower = buffer[bottom * width + left].lerp(buffer[bottom * width + right], progress_x);
        return upper.lerp(lower, progress_y);
    }

    /// Box-average along one line of `count` pixels (`start`, `start+step`,
    /// ...) of `source` into `destination`: each output is the mean of the
    /// `2*window_radius+1` window around it, clamped to the line. A running sum
    /// makes it O(count) however wide the window.
    ///
    /// - `source`: the pixels read.
    /// - `destination`: the pixels written.
    /// - `start`: the line's first index.
    /// - `step`: the distance between the line's pixels.
    /// - `count`: the line's length.
    /// - `window_radius`: the window's half-width.
    fn boxLine(source: []const mod.Color, destination: []mod.Color, start: usize, step: usize, count: usize, window_radius: i64) void {
        var red: f32 = 0;
        var green: f32 = 0;
        var blue: f32 = 0;
        var alpha: f32 = 0;
        var entering: usize = 0; // next pixel to enter the window
        var leaving: usize = 0; // next pixel to leave it
        var index: usize = 0;
        while (index < count) : (index += 1) {
            const last: i64 = @as(i64, @intCast(index)) + window_radius;
            while (entering < count and @as(i64, @intCast(entering)) <= last) : (entering += 1) {
                const pixel = source[start + entering * step];
                red += pixel.r;
                green += pixel.g;
                blue += pixel.b;
                alpha += pixel.a;
            }
            const first: i64 = @as(i64, @intCast(index)) - window_radius;
            while (@as(i64, @intCast(leaving)) < first) : (leaving += 1) {
                const pixel = source[start + leaving * step];
                red -= pixel.r;
                green -= pixel.g;
                blue -= pixel.b;
                alpha -= pixel.a;
            }
            const samples: f32 = @floatFromInt(entering - leaving);
            destination[start + index * step] = .{ .r = red / samples, .g = green / samples, .b = blue / samples, .a = alpha / samples };
        }
    }

    /// Signed distance from point (`pixel_x`, `pixel_y`) to a rounded box.
    /// Negative inside.
    ///
    /// - `pixel_x`: the point's x.
    /// - `pixel_y`: the point's y.
    /// - `rect`: the box.
    /// - `radius`: the box's corner radius.
    /// - Returns: the distance.
    fn roundBoxDistance(pixel_x: f32, pixel_y: f32, rect: mod.Rect, radius: f32) f32 {
        const corner = @min(radius, @min(rect.width, rect.height) / 2);
        const center_x = rect.midX();
        const center_y = rect.midY();
        const half_x = rect.width / 2 - corner;
        const half_y = rect.height / 2 - corner;
        const offset_x = @abs(pixel_x - center_x) - half_x;
        const offset_y = @abs(pixel_y - center_y) - half_y;
        const outside_x = @max(offset_x, 0);
        const outside_y = @max(offset_y, 0);
        const outside = @sqrt(outside_x * outside_x + outside_y * outside_y);
        const inside = @min(@max(offset_x, offset_y), 0);
        return outside + inside - corner;
    }

    /// Coverage 0..1 of a filled rounded box at a pixel center, 1px anti-aliased.
    ///
    /// - `pixel_x`: the pixel center's x.
    /// - `pixel_y`: the pixel center's y.
    /// - `rect`: the box.
    /// - `radius`: the box's corner radius.
    /// - Returns: the coverage.
    fn fillCoverage(pixel_x: f32, pixel_y: f32, rect: mod.Rect, radius: f32) f32 {
        return std.math.clamp(0.5 - Self.roundBoxDistance(pixel_x, pixel_y, rect, radius), 0, 1);
    }

    /// The clip stack's coverage at a pixel center.
    ///
    /// - `clips`: the clip stack.
    /// - `pixel_x`: the pixel center's x.
    /// - `pixel_y`: the pixel center's y.
    /// - Returns: the product of every clip's coverage.
    fn clipCoverage(clips: []const Clip, pixel_x: f32, pixel_y: f32) f32 {
        var coverage: f32 = 1;
        for (clips) |clip| {
            coverage *= Self.fillCoverage(pixel_x, pixel_y, clip.rect, clip.radius);
            if (coverage <= 0) return 0;
        }
        return coverage;
    }

    /// Integer pixel range covering `rect` (expanded by `padding` for AA),
    /// clamped to the framebuffer.
    ///
    /// - `self`: the rasterizer.
    /// - `rect`: the rect.
    /// - `padding`: how far to grow the rect first.
    /// - Returns: the pixel range.
    fn boundsOf(self: *const Self, rect: mod.Rect, padding: f32) PixelBounds {
        const left = std.math.clamp(@floor(rect.minX() - padding), 0, @as(f32, @floatFromInt(self.framebuffer.width)));
        const top = std.math.clamp(@floor(rect.minY() - padding), 0, @as(f32, @floatFromInt(self.framebuffer.height)));
        const right = std.math.clamp(@ceil(rect.maxX() + padding), 0, @as(f32, @floatFromInt(self.framebuffer.width)));
        const bottom = std.math.clamp(@ceil(rect.maxY() + padding), 0, @as(f32, @floatFromInt(self.framebuffer.height)));
        return .{
            .left = @intFromFloat(left),
            .top = @intFromFloat(top),
            .right = @intFromFloat(right),
            .bottom = @intFromFloat(bottom),
        };
    }

    /// The pixels a command over `rect` needs to visit under the clip stack,
    /// and whether they need per-pixel clip coverage (see `ClippedBounds`).
    ///
    /// - `self`: the rasterizer.
    /// - `clips`: the clip stack.
    /// - `rect`: the shape's rect.
    /// - `padding`: the shape's anti-aliasing reach past `rect`.
    /// - Returns: the bounds and the clip check.
    fn clippedBoundsOf(self: *const Self, clips: []const Clip, rect: mod.Rect, padding: f32) ClippedBounds {
        var bounds = self.boundsOf(rect, padding);
        var check = false;
        for (clips) |clip| {
            const clip_bounds = self.boundsOf(clip.rect, 1);
            bounds.left = @max(bounds.left, clip_bounds.left);
            bounds.top = @max(bounds.top, clip_bounds.top);
            bounds.right = @min(bounds.right, clip_bounds.right);
            bounds.bottom = @min(bounds.bottom, clip_bounds.bottom);
            if (!check) {
                const inset = clip.radius / 2 + 1;
                check = rect.minX() - padding < clip.rect.minX() + inset or
                    rect.maxX() + padding > clip.rect.maxX() - inset or
                    rect.minY() - padding < clip.rect.minY() + inset or
                    rect.maxY() + padding > clip.rect.maxY() - inset;
            }
        }
        return .{ .bounds = bounds, .check_clip = check };
    }

    /// For the row of pixel centers at `pixel_y`, the half-width around
    /// `rect.midX()` within which fill coverage is exactly 1 (sd <= -0.5), or
    /// null when no pixel of this row is fully covered.
    ///
    /// - `rect`: the shape.
    /// - `corner`: the corner radius, already clamped to the half-size.
    /// - `pixel_y`: the row's pixel-center y.
    /// - Returns: the half-width, or null.
    fn fullSpanHalfWidth(rect: mod.Rect, corner: f32, pixel_y: f32) ?f32 {
        const offset_y = @abs(pixel_y - rect.midY()) - (rect.height / 2 - corner);
        const inner_corner = corner - 0.5;
        if (offset_y > inner_corner) return null; // top/bottom AA fringe (or outside)
        if (offset_y >= 0) {
            // corner band: the full-coverage span follows the inset corner circle
            return (rect.width / 2 - corner) + @sqrt(inner_corner * inner_corner - offset_y * offset_y);
        }
        return rect.width / 2 - 0.5;
    }

    /// Fill a rounded rect with `paint`.
    ///
    /// - `self`: the rasterizer.
    /// - `clips`: the clip stack.
    /// - `rect`: the shape.
    /// - `radius`: the corner radius.
    /// - `paint`: the color or gradient.
    fn fillShape(self: *const Self, clips: []const Clip, rect: mod.Rect, radius: f32, paint: Paint) void {
        const framebuffer = self.framebuffer;
        const clipped = self.clippedBoundsOf(clips, rect, 1);
        const bounds = clipped.bounds;
        if (bounds.empty()) return;
        const corner = @min(radius, @min(rect.width, rect.height) / 2);
        // Solid paints — and vertical gradients, which all the theme sheens are —
        // have one color per row, computed outside the inner loop.
        const row_constant = switch (paint) {
            .solid => true,
            .gradient => |gradient| gradient.start.x == gradient.end.x,
        };
        var y = bounds.top;
        while (y < bounds.bottom) : (y += 1) {
            const pixel_y = @as(f32, @floatFromInt(y)) + 0.5;
            const row_color = if (row_constant) paint.colorAt(rect.midX(), pixel_y) else mod.Color.transparent;

            // The span of pixels this row where shape coverage is exactly 1: those
            // skip the SDF; an opaque row-constant color becomes a plain @memset.
            var span_start = bounds.right;
            var span_end = bounds.right;
            if (Self.fullSpanHalfWidth(rect, corner, pixel_y)) |half| {
                const full_start = rect.midX() - half;
                const full_end = rect.midX() + half;
                if (full_end > full_start) {
                    // Clamped to the row before converting: a rect far wider
                    // than the framebuffer overflows u32.
                    const right: f32 = @floatFromInt(bounds.right);
                    span_start = std.math.clamp(@as(u32, @intFromFloat(std.math.clamp(@ceil(full_start - 0.5), 0, right))), bounds.left, bounds.right);
                    span_end = std.math.clamp(@as(u32, @intFromFloat(std.math.clamp(@floor(full_end - 0.5) + 1, 0, right))), span_start, bounds.right);
                }
            }

            const row_index = y * framebuffer.width;
            var x = bounds.left;
            while (x < bounds.right) : (x += 1) {
                if (x >= span_start and x < span_end and !clipped.check_clip) {
                    // Fully-covered interior run.
                    if (row_constant and row_color.a >= 1) {
                        @memset(framebuffer.pixels[row_index + span_start .. row_index + span_end], row_color);
                    } else {
                        var run_x = x;
                        while (run_x < span_end) : (run_x += 1) {
                            const color = if (row_constant) row_color else paint.colorAt(@as(f32, @floatFromInt(run_x)) + 0.5, pixel_y);
                            framebuffer.blend(run_x, y, color, 1);
                        }
                    }
                    x = span_end - 1; // resume the AA fringe after the span
                    continue;
                }
                const pixel_x = @as(f32, @floatFromInt(x)) + 0.5;
                var coverage = if (x >= span_start and x < span_end) 1 else Self.fillCoverage(pixel_x, pixel_y, rect, corner);
                if (clipped.check_clip and coverage > 0) coverage *= Self.clipCoverage(clips, pixel_x, pixel_y);
                if (coverage > 0) {
                    const color = if (row_constant) row_color else paint.colorAt(pixel_x, pixel_y);
                    framebuffer.blend(x, y, color, coverage);
                }
            }
        }
    }

    /// Stroke a rounded rect's outline.
    ///
    /// - `self`: the rasterizer.
    /// - `clips`: the clip stack.
    /// - `rect`: the shape.
    /// - `radius`: the corner radius.
    /// - `width`: the stroke's width.
    /// - `color`: the stroke color.
    fn strokeShape(self: *const Self, clips: []const Clip, rect: mod.Rect, radius: f32, width: f32, color: mod.Color) void {
        const framebuffer = self.framebuffer;
        const half = width / 2;
        const clipped = self.clippedBoundsOf(clips, rect, half + 1);
        const bounds = clipped.bounds;
        if (bounds.empty()) return;
        const corner = @min(radius, @min(rect.width, rect.height) / 2);
        // Rows clear of the top/bottom edges and corners only have coverage in two
        // narrow bands around the vertical edges — skip the hollow interior.
        const band = half + 1.5;
        const middle_top = rect.minY() + corner + band;
        const middle_bottom = rect.maxY() - corner - band;
        const left_band_end: u32 = @intFromFloat(std.math.clamp(@ceil(rect.minX() + band), 0, @as(f32, @floatFromInt(framebuffer.width))));
        const right_band_start: u32 = @intFromFloat(std.math.clamp(@floor(rect.maxX() - band), 0, @as(f32, @floatFromInt(framebuffer.width))));
        var y = bounds.top;
        while (y < bounds.bottom) : (y += 1) {
            const pixel_y = @as(f32, @floatFromInt(y)) + 0.5;
            const edge_row = pixel_y <= middle_top or pixel_y >= middle_bottom;
            var x = bounds.left;
            while (x < bounds.right) : (x += 1) {
                if (!edge_row and x >= left_band_end and x < right_band_start) {
                    x = right_band_start - 1; // jump the hollow interior to the right band
                    continue;
                }
                const pixel_x = @as(f32, @floatFromInt(x)) + 0.5;
                const distance = @abs(Self.roundBoxDistance(pixel_x, pixel_y, rect, corner)) - half;
                var coverage = std.math.clamp(0.5 - distance, 0, 1);
                if (clipped.check_clip and coverage > 0) coverage *= Self.clipCoverage(clips, pixel_x, pixel_y);
                if (coverage > 0) framebuffer.blend(x, y, color, coverage);
            }
        }
    }

    /// Distance from a point to a line segment.
    ///
    /// - `pixel_x`: the point's x.
    /// - `pixel_y`: the point's y.
    /// - `start`: one end of the segment.
    /// - `end`: the other end.
    /// - Returns: the distance.
    fn segmentDistance(pixel_x: f32, pixel_y: f32, start: mod.Point, end: mod.Point) f32 {
        const point_x = pixel_x - start.x;
        const point_y = pixel_y - start.y;
        const segment_x = end.x - start.x;
        const segment_y = end.y - start.y;
        const length_squared = segment_x * segment_x + segment_y * segment_y;
        const progress = if (length_squared > 0) std.math.clamp((point_x * segment_x + point_y * segment_y) / length_squared, 0, 1) else 0;
        const delta_x = point_x - segment_x * progress;
        const delta_y = point_y - segment_y * progress;
        return @sqrt(delta_x * delta_x + delta_y * delta_y);
    }

    /// Draw a line segment.
    ///
    /// - `self`: the rasterizer.
    /// - `clips`: the clip stack.
    /// - `start`: one end.
    /// - `end`: the other end.
    /// - `width`: the line's width.
    /// - `color`: the line's color.
    fn drawLine(self: *const Self, clips: []const Clip, start: mod.Point, end: mod.Point, width: f32, color: mod.Color) void {
        const framebuffer = self.framebuffer;
        const half = width / 2;
        const min_x = @min(start.x, end.x);
        const min_y = @min(start.y, end.y);
        const rect = mod.Rect{ .x = min_x, .y = min_y, .width = @abs(end.x - start.x), .height = @abs(end.y - start.y) };
        const clipped = self.clippedBoundsOf(clips, rect, half + 1);
        const bounds = clipped.bounds;
        if (bounds.empty()) return;
        var y = bounds.top;
        while (y < bounds.bottom) : (y += 1) {
            var x = bounds.left;
            while (x < bounds.right) : (x += 1) {
                const pixel_x = @as(f32, @floatFromInt(x)) + 0.5;
                const pixel_y = @as(f32, @floatFromInt(y)) + 0.5;
                const distance = Self.segmentDistance(pixel_x, pixel_y, start, end) - half;
                var coverage = std.math.clamp(0.5 - distance, 0, 1);
                if (clipped.check_clip and coverage > 0) coverage *= Self.clipCoverage(clips, pixel_x, pixel_y);
                if (coverage > 0) framebuffer.blend(x, y, color, coverage);
            }
        }
    }

    /// Draw a tinted coverage mask.
    ///
    /// - `self`: the rasterizer.
    /// - `clips`: the clip stack.
    /// - `rect`: where the mask is drawn.
    /// - `color`: the tint.
    /// - `coverage`: the mask.
    /// - `gamma`: the coverage exponent.
    fn drawGlyph(self: *const Self, clips: []const Clip, rect: mod.Rect, color: mod.Color, coverage: mod.Coverage, gamma: f32) void {
        const framebuffer = self.framebuffer;
        if (coverage.width == 0 or coverage.height == 0) return;
        const clipped = self.clippedBoundsOf(clips, rect, 0);
        const bounds = clipped.bounds;
        if (bounds.empty()) return;
        // pixel -> coverage texel (nearest); divisions hoisted out of the loops
        const texel_x_scale = @as(f32, @floatFromInt(coverage.width)) / rect.width;
        const texel_y_scale = @as(f32, @floatFromInt(coverage.height)) / rect.height;
        var y = bounds.top;
        while (y < bounds.bottom) : (y += 1) {
            const pixel_y = @as(f32, @floatFromInt(y)) + 0.5;
            const texel_y = (pixel_y - rect.y) * texel_y_scale;
            if (texel_y < 0) continue;
            const texel_row: u32 = @intFromFloat(texel_y);
            if (texel_row >= coverage.height) continue;
            const row = coverage.data[texel_row * coverage.width ..];
            var x = bounds.left;
            while (x < bounds.right) : (x += 1) {
                const pixel_x = @as(f32, @floatFromInt(x)) + 0.5;
                const texel_x = (pixel_x - rect.x) * texel_x_scale;
                if (texel_x < 0) continue;
                const texel_column: u32 = @intFromFloat(texel_x);
                if (texel_column >= coverage.width) continue;
                var amount = @as(f32, @floatFromInt(row[texel_column])) / 255.0;
                // Coverage gamma (text contrast): thicken/thin the anti-aliased edge
                // so light text on a dark background isn't rendered too thin. Skipped
                // at gamma == 1 so the default path is byte-identical (no pow). Must
                // precede the clip multiply to match the GPU shader exactly.
                if (gamma != 1 and amount > 0) amount = std.math.pow(f32, amount, gamma);
                if (clipped.check_clip and amount > 0) amount *= Self.clipCoverage(clips, pixel_x, pixel_y);
                if (amount > 0) framebuffer.blend(x, y, color, amount);
            }
        }
    }

    /// Draw an image stretched over a rect.
    ///
    /// - `self`: the rasterizer.
    /// - `clips`: the clip stack.
    /// - `rect`: where the image is drawn.
    /// - `image`: the pixels.
    fn drawImage(self: *const Self, clips: []const Clip, rect: mod.Rect, image: mod.Image) void {
        const framebuffer = self.framebuffer;
        if (image.width == 0 or image.height == 0) return;
        const clipped = self.clippedBoundsOf(clips, rect, 0);
        const bounds = clipped.bounds;
        if (bounds.empty()) return;
        const texel_x_scale = @as(f32, @floatFromInt(image.width)) / rect.width;
        const texel_y_scale = @as(f32, @floatFromInt(image.height)) / rect.height;
        var y = bounds.top;
        while (y < bounds.bottom) : (y += 1) {
            const pixel_y = @as(f32, @floatFromInt(y)) + 0.5;
            const texel_y = (pixel_y - rect.y) * texel_y_scale;
            if (texel_y < 0) continue;
            const texel_row: u32 = @intFromFloat(texel_y);
            if (texel_row >= image.height) continue;
            var x = bounds.left;
            while (x < bounds.right) : (x += 1) {
                const pixel_x = @as(f32, @floatFromInt(x)) + 0.5;
                const texel_x = (pixel_x - rect.x) * texel_x_scale;
                if (texel_x < 0) continue;
                const texel_column: u32 = @intFromFloat(texel_x);
                if (texel_column >= image.width) continue;
                const index = (texel_row * image.width + texel_column) * 4;
                const source = mod.Color.fromRgba8(
                    image.pixels[index + 0],
                    image.pixels[index + 1],
                    image.pixels[index + 2],
                    image.pixels[index + 3],
                );
                const coverage: f32 = if (clipped.check_clip) Self.clipCoverage(clips, pixel_x, pixel_y) else 1;
                framebuffer.blend(x, y, source, coverage);
            }
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// Renders a canvas the way the tests need it.
const TestRender = struct {
    const Self = @This();

    /// Render `canvas` into `framebuffer` with the testing allocator.
    ///
    /// - `framebuffer`: the framebuffer painted into.
    /// - `canvas`: the commands.
    /// - Returns: nothing; propagates allocation failure.
    fn canvasInto(framebuffer: *mod.Framebuffer, canvas: *const mod.Canvas) !void {
        try Rasterizer.init(std.testing.allocator, framebuffer).render(canvas.commands.items);
    }
};

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "raster: fill rect paints interior, leaves outside untouched" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 20, 20);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.white);
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.fillRect(.{ .x = 5, .y = 5, .width = 10, .height = 10 }, mod.Color.red);
    try TestRender.canvasInto(&framebuffer, &canvas);

    try std.testing.expect(framebuffer.at(10, 10).approxEql(mod.Color.red, 0.02)); // inside
    try std.testing.expect(framebuffer.at(0, 0).approxEql(mod.Color.white, 0.02)); // outside
}

test "raster: rounded rect clips its corners" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 40, 40);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.white);
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.fillRoundedRect(.{ .x = 0, .y = 0, .width = 40, .height = 40 }, 12, mod.Color.red);
    try TestRender.canvasInto(&framebuffer, &canvas);

    try std.testing.expect(framebuffer.at(20, 20).approxEql(mod.Color.red, 0.02)); // center filled
    // extreme corner is outside the rounded shape -> still background
    try std.testing.expect(framebuffer.at(0, 0).approxEql(mod.Color.white, 0.05));
}

test "raster: alpha compositing blends translucent over opaque" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 10, 10);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.black);
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.fillRect(.{ .x = 0, .y = 0, .width = 10, .height = 10 }, mod.Color.white.withAlpha(0.5));
    try TestRender.canvasInto(&framebuffer, &canvas);
    try std.testing.expect(framebuffer.at(5, 5).approxEql(mod.Color{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1 }, 0.02));
}

test "raster: clip masks drawing to the clip rect" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 20, 20);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.white);
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.pushClip(.{ .x = 0, .y = 0, .width = 10, .height = 20 }, 0);
    try canvas.fillRect(.{ .x = 0, .y = 0, .width = 20, .height = 20 }, mod.Color.red); // wider than clip
    try canvas.popClip();
    try TestRender.canvasInto(&framebuffer, &canvas);

    try std.testing.expect(framebuffer.at(5, 10).approxEql(mod.Color.red, 0.02)); // inside clip
    try std.testing.expect(framebuffer.at(15, 10).approxEql(mod.Color.white, 0.02)); // clipped away
}

test "raster: linear gradient interpolates left-to-right" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 100, 10);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.black);
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.push(.{ .linearGradient = .{
        .rect = .{ .x = 0, .y = 0, .width = 100, .height = 10 },
        .start = .{ .x = 0, .y = 0 },
        .end = .{ .x = 100, .y = 0 },
        .start_color = mod.Color.red,
        .end_color = mod.Color.blue,
    } });
    try TestRender.canvasInto(&framebuffer, &canvas);

    try std.testing.expect(framebuffer.at(1, 5).r > 0.9); // left ~ red
    try std.testing.expect(framebuffer.at(98, 5).b > 0.9); // right ~ blue
    const middle = framebuffer.at(50, 5);
    try std.testing.expect(middle.r > 0.3 and middle.r < 0.7 and middle.b > 0.3 and middle.b < 0.7);
}

test "raster: stroke paints border but not center" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 40, 40);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.white);
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.strokeRoundedRect(.{ .x = 5, .y = 5, .width = 30, .height = 30 }, 0, 2, mod.Color.black);
    try TestRender.canvasInto(&framebuffer, &canvas);

    try std.testing.expect(framebuffer.at(20, 20).approxEql(mod.Color.white, 0.05)); // hollow center
    try std.testing.expect(framebuffer.at(20, 5).isDark()); // top border drawn
}

test "raster: glyph coverage is tinted and blitted" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 4, 4);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.white);
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    // 2x2 coverage: top-left fully opaque, rest transparent
    const data = [_]u8{ 255, 0, 0, 0 };
    try canvas.drawGlyph(
        .{ .x = 0, .y = 0, .width = 2, .height = 2 },
        mod.Color.red,
        .{ .width = 2, .height = 2, .data = &data },
    );
    try TestRender.canvasInto(&framebuffer, &canvas);
    try std.testing.expect(framebuffer.at(0, 0).approxEql(mod.Color.red, 0.02)); // covered texel
    try std.testing.expect(framebuffer.at(1, 1).approxEql(mod.Color.white, 0.02)); // uncovered
}

test "raster: glyph coverage gamma thickens the anti-aliased edge" {
    // A half-covered texel of light text on a dark background. gamma == 1 blends
    // at raw 0.5 coverage; gamma < 1 raises the coverage, so the edge pixel ends
    // up lighter (more ink) — the gamma-correct fix for thin light-on-dark text.
    const data = [_]u8{128}; // ~0.502 coverage
    const coverage = mod.Coverage{ .width = 1, .height = 1, .data = &data };

    var plain = try mod.Framebuffer.init(std.testing.allocator, 1, 1);
    defer plain.deinit();
    plain.clear(mod.Color.black);
    var plain_canvas = mod.Canvas.init(std.testing.allocator);
    defer plain_canvas.deinit();
    try plain_canvas.drawGlyph(.{ .x = 0, .y = 0, .width = 1, .height = 1 }, mod.Color.white, coverage);
    try TestRender.canvasInto(&plain, &plain_canvas);

    var corrected = try mod.Framebuffer.init(std.testing.allocator, 1, 1);
    defer corrected.deinit();
    corrected.clear(mod.Color.black);
    var corrected_canvas = mod.Canvas.init(std.testing.allocator);
    defer corrected_canvas.deinit();
    try corrected_canvas.drawGlyphGamma(.{ .x = 0, .y = 0, .width = 1, .height = 1 }, mod.Color.white, coverage, 0.5);
    try TestRender.canvasInto(&corrected, &corrected_canvas);

    // gamma 0.5 raises ~0.502 coverage to ~0.709, so the pixel is brighter.
    try std.testing.expect(corrected.at(0, 0).r > plain.at(0, 0).r + 0.15);
    // gamma == 1 leaves the raw coverage untouched.
    try std.testing.expectApproxEqAbs(@as(f32, 0.502), plain.at(0, 0).r, 0.01);
}

test "raster: image blit copies pixels" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 2, 2);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.white);
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    // a single green opaque pixel image, stretched over the 2x2 framebuffer
    const pixels = [_]u8{ 0, 255, 0, 255 };
    try canvas.drawImage(.{ .x = 0, .y = 0, .width = 2, .height = 2 }, .{ .width = 1, .height = 1, .pixels = &pixels });
    try TestRender.canvasInto(&framebuffer, &canvas);
    try std.testing.expect(framebuffer.at(0, 0).approxEql(mod.Color.green, 0.02));
    try std.testing.expect(framebuffer.at(1, 1).approxEql(mod.Color.green, 0.02));
}

test "raster: blurRect averages its region and leaves the outside untouched" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 20, 20);
    defer framebuffer.deinit();
    // high-contrast vertical stripes (even columns black, odd white)
    var y: usize = 0;
    while (y < 20) : (y += 1) {
        var x: usize = 0;
        while (x < 20) : (x += 1) {
            framebuffer.pixels[y * 20 + x] = if (x % 2 == 0) mod.Color.black else mod.Color.white;
        }
    }
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.blurRect(.{ .x = 5, .y = 5, .width = 10, .height = 10 }, 0, 3, mod.Color.transparent);
    try TestRender.canvasInto(&framebuffer, &canvas);

    // inside the blurred region the stripes smear toward the mid grey mean
    const center = framebuffer.at(10, 10);
    try std.testing.expect(center.r > 0.3 and center.r < 0.7);
    // outside the rect the stripes are pristine
    try std.testing.expect(framebuffer.at(0, 0).approxEql(mod.Color.black, 0.02));
    try std.testing.expect(framebuffer.at(1, 0).approxEql(mod.Color.white, 0.02));
}

test "raster: blurRect tint shifts the region toward the tint color" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 20, 20);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.fromRgb8(128, 128, 128)); // mid grey
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.blurRect(.{ .x = 5, .y = 5, .width = 10, .height = 10 }, 0, 2, mod.Color.white.withAlpha(0.5));
    try TestRender.canvasInto(&framebuffer, &canvas);
    // tinted region is clearly lighter than the untouched grey background
    try std.testing.expect(framebuffer.at(10, 10).luminance() > framebuffer.at(0, 0).luminance() + 0.1);
    try std.testing.expect(framebuffer.at(0, 0).approxEql(mod.Color.fromRgb8(128, 128, 128), 0.02));
}

test "raster: boxLine's running sum matches a brute-force clamped window" {
    var source: [11]mod.Color = undefined;
    for (&source, 0..) |*pixel, index| pixel.* = .{ .r = @as(f32, @floatFromInt(index)) / 10, .g = 1 - @as(f32, @floatFromInt(index)) / 10, .b = 0.5, .a = 1 };
    for ([_]i64{ 1, 3, 20 }) |window_radius| {
        var destination: [11]mod.Color = undefined;
        Rasterizer.boxLine(&source, &destination, 0, 1, source.len, window_radius);
        for (destination, 0..) |got, index| {
            var sum: f32 = 0;
            var samples: f32 = 0;
            for (source, 0..) |pixel, other| {
                const distance = @as(i64, @intCast(other)) - @as(i64, @intCast(index));
                if (distance >= -window_radius and distance <= window_radius) {
                    sum += pixel.r;
                    samples += 1;
                }
            }
            try std.testing.expectApproxEqAbs(sum / samples, got.r, 1e-5);
        }
    }
}

test "raster: a rect far larger than the framebuffer fills it without trapping" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 20, 20);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.white);
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try canvas.fillRect(.{ .x = 0, .y = 0, .width = 1e10, .height = 1e10 }, mod.Color.red);
    try canvas.fillRoundedRect(.{ .x = -5e9, .y = -5e9, .width = 1e10, .height = 1e10 }, 1e10, mod.Color.red);
    try canvas.fillRect(.{ .x = 5, .y = 5, .width = 1e10, .height = 10 }, mod.Color.blue.withAlpha(0.5));
    try canvas.strokeRoundedRect(.{ .x = -1e10, .y = -1e10, .width = 3e10, .height = 3e10 }, 0, 1e10, mod.Color.red);
    try canvas.line(.{ .x = -1e10, .y = 10 }, .{ .x = 1e10, .y = 10 }, 2, mod.Color.red);
    try TestRender.canvasInto(&framebuffer, &canvas);

    try std.testing.expect(framebuffer.at(0, 0).approxEql(mod.Color.red, 0.02));
    try std.testing.expect(framebuffer.at(19, 19).approxEql(mod.Color.red, 0.02));
}

test "raster: non-finite rects draw nothing and do not trap" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 20, 20);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.white);
    var canvas = mod.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    const nan = std.math.nan(f32);
    const inf = std.math.inf(f32);
    const rects = [_]mod.Rect{
        .{ .x = nan, .y = nan, .width = nan, .height = nan },
        .{ .x = 0, .y = 0, .width = nan, .height = 10 },
        .{ .x = -inf, .y = -inf, .width = inf, .height = inf },
        .{ .x = inf, .y = inf, .width = 10, .height = 10 },
        .{ .x = 0, .y = 0, .width = 10, .height = -inf },
    };
    const data = [_]u8{255};
    const pixels = [_]u8{ 0, 255, 0, 255 };
    for (rects) |rect| {
        try canvas.fillRect(rect, mod.Color.red);
        try canvas.fillRoundedRect(rect, nan, mod.Color.red);
        try canvas.fillRoundedRect(rect, inf, mod.Color.red);
        try canvas.strokeRoundedRect(rect, inf, nan, mod.Color.red);
        try canvas.drawGlyph(rect, mod.Color.red, .{ .width = 1, .height = 1, .data = &data });
        try canvas.drawImage(rect, .{ .width = 1, .height = 1, .pixels = &pixels });
        try canvas.blurRect(rect, nan, nan, mod.Color.red);
        try canvas.blurRect(rect, inf, inf, mod.Color.red);
        try canvas.line(.{ .x = rect.x, .y = rect.y }, .{ .x = rect.width, .y = rect.height }, nan, mod.Color.red);
    }
    try TestRender.canvasInto(&framebuffer, &canvas);
}

test "raster: a huge or non-finite blur sigma blurs the region without trapping" {
    for ([_]f32{ 1e10, 1e30, std.math.inf(f32), std.math.nan(f32) }) |sigma| {
        var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 20, 20);
        defer framebuffer.deinit();
        var y: usize = 0;
        while (y < 20) : (y += 1) {
            var x: usize = 0;
            while (x < 20) : (x += 1) {
                framebuffer.pixels[y * 20 + x] = if (x % 2 == 0) mod.Color.black else mod.Color.white;
            }
        }
        var canvas = mod.Canvas.init(std.testing.allocator);
        defer canvas.deinit();
        try canvas.blurRect(.{ .x = 5, .y = 5, .width = 10, .height = 10 }, 0, sigma, mod.Color.transparent);
        try canvas.blurRect(.{ .x = 0, .y = 0, .width = 1e10, .height = 1e10 }, 0, sigma, mod.Color.transparent);
        try TestRender.canvasInto(&framebuffer, &canvas);

        const center = framebuffer.at(10, 10);
        try std.testing.expect(center.r > 0.3 and center.r < 0.7);
    }
}
