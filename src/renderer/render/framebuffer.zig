//! A CPU pixel buffer the software rasterizer paints into.

const std = @import("std");
const log = std.log.scoped(.ziggui_framebuffer);
const mod = @import("module.zig");

/// A CPU pixel buffer in straight-alpha `Color` (f32) for accurate compositing.
pub const Framebuffer = struct {
    const Self = @This();

    /// The buffer's width, in pixels.
    width: u32,
    /// The buffer's height, in pixels.
    height: u32,
    /// The pixels, rows top-down.
    pixels: []mod.Color,
    /// The allocator that owns `pixels`.
    allocator: std.mem.Allocator,

    /// A zero-size framebuffer holding no allocation. Pair with `ensureSize` to
    /// grow it lazily and reuse the buffer across frames.
    pub const empty: Self = .{ .width = 0, .height = 0, .pixels = &.{}, .allocator = undefined };

    /// A transparent framebuffer of the given size.
    ///
    /// - `allocator`: allocator for the pixels.
    /// - `width`: the width, in pixels.
    /// - `height`: the height, in pixels.
    /// - Returns: the framebuffer; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !Self {
        const pixels = try allocator.alloc(mod.Color, width * height);
        @memset(pixels, mod.Color.transparent);
        const self = Self{ .width = width, .height = height, .pixels = pixels, .allocator = allocator };
        return self;
    }

    /// Free the pixels and leave the framebuffer `empty`.
    ///
    /// - `self`: the framebuffer.
    pub fn deinit(self: *Self) void {
        if (self.pixels.len > 0) self.allocator.free(self.pixels);
        self.* = .empty;
    }

    /// Resize for reuse: reallocates the pixel buffer only when the pixel count
    /// actually changes, so steady-state frames (same window size) allocate
    /// nothing. The contents are left undefined — call `clear` afterward.
    ///
    /// - `self`: the framebuffer.
    /// - `allocator`: allocator for the pixels (kept for `deinit`).
    /// - `width`: the width, in pixels.
    /// - `height`: the height, in pixels.
    /// - Returns: nothing; propagates allocation failure.
    pub fn ensureSize(self: *Self, allocator: std.mem.Allocator, width: u32, height: u32) !void {
        const need = @as(usize, width) * @as(usize, height);
        if (need != self.pixels.len) {
            if (self.pixels.len > 0) allocator.free(self.pixels);
            self.pixels = try allocator.alloc(mod.Color, need);
        }
        self.width = width;
        self.height = height;
        self.allocator = allocator;
    }

    /// Set every pixel to `color`.
    ///
    /// - `self`: the framebuffer.
    /// - `color`: the color.
    pub fn clear(self: *Self, color: mod.Color) void {
        self.clearRows(color, .all(self.height));
    }

    /// Set every pixel of `rows` to `color`; rows past the bottom are ignored.
    ///
    /// - `self`: the framebuffer.
    /// - `color`: the color.
    /// - `rows`: the rows to set.
    pub fn clearRows(self: *Self, color: mod.Color, rows: mod.RowBand) void {
        @memset(self.clampedRows(rows).slice(mod.Color, self.pixels, self.width), color);
    }

    /// The pixel at (`x`, `y`).
    ///
    /// - `self`: the framebuffer.
    /// - `x`: the column.
    /// - `y`: the row.
    /// - Returns: the pixel.
    pub fn at(self: *const Self, x: u32, y: u32) mod.Color {
        return self.pixels[y * self.width + x];
    }

    /// The pixel at (`x`, `y`) as 8-bit channels.
    ///
    /// - `self`: the framebuffer.
    /// - `x`: the column.
    /// - `y`: the row.
    /// - Returns: the pixel's bytes.
    pub fn rgba8At(self: *const Self, x: u32, y: u32) mod.Rgba8 {
        return self.at(x, y).toRgba8();
    }

    /// Composite `source` over the pixel at (`x`, `y`) at `coverage`.
    ///
    /// - `self`: the framebuffer.
    /// - `x`: the column.
    /// - `y`: the row.
    /// - `source`: the color painted.
    /// - `coverage`: how much of the pixel it covers, 0...1.
    pub fn blend(self: *Self, x: u32, y: u32, source: mod.Color, coverage: f32) void {
        if (coverage <= 0) return;
        const index = y * self.width + x;
        // Opaque pixel at full coverage: plain store, no compositing math.
        if (coverage >= 1 and source.a >= 1) {
            self.pixels[index] = source;
            return;
        }
        const covered = source.withAlpha(source.a * coverage);
        self.pixels[index] = covered.over(self.pixels[index]);
    }

    /// Convert into a caller-provided tightly-packed RGBA8 buffer (reused across
    /// frames). `bytes.len` must be `width * height * 4`.
    ///
    /// - `self`: the framebuffer.
    /// - `bytes`: receives the pixels.
    pub fn toRgba8(self: *const Self, bytes: []u8) void {
        self.toRgba8Rows(bytes, .all(self.height));
    }

    /// Convert only `rows` into the whole image's tightly-packed RGBA8 buffer,
    /// leaving its other rows alone, so bands convert apart. `bytes.len` must
    /// be `width * height * 4`, checked in every build mode (a short buffer
    /// panics rather than being written past); rows past the bottom are ignored.
    ///
    /// - `self`: the framebuffer.
    /// - `bytes`: the whole image's pixels; receives the band's.
    /// - `rows`: the rows to convert.
    pub fn toRgba8Rows(self: *const Self, bytes: []u8, rows: mod.RowBand) void {
        if (bytes.len != @as(usize, self.width) * self.height * 4) @panic("Framebuffer.toRgba8Rows: the buffer is not width * height * 4 bytes");
        const band = self.clampedRows(rows);
        const colors = band.slice(mod.Color, self.pixels, self.width);
        const destination = band.slice(u8, bytes, @as(usize, self.width) * 4);
        for (colors, 0..) |color, index| {
            const pixel = color.toRgba8();
            destination[index * 4 + 0] = pixel.r;
            destination[index * 4 + 1] = pixel.g;
            destination[index * 4 + 2] = pixel.b;
            destination[index * 4 + 3] = pixel.a;
        }
    }

    /// `rows` cut to the framebuffer's height.
    ///
    /// - `self`: the framebuffer.
    /// - `rows`: the rows asked for.
    /// - Returns: the rows that exist, empty when none do.
    fn clampedRows(self: *const Self, rows: mod.RowBand) mod.RowBand {
        const top = @min(rows.top, self.height);
        return .{ .top = top, .bottom = std.math.clamp(rows.bottom, top, self.height) };
    }

    /// Export to a freshly-allocated RGBA8 buffer (caller owns the memory).
    ///
    /// - `self`: the framebuffer.
    /// - `allocator`: allocator for the bytes.
    /// - Returns: the pixels as RGBA8; propagates allocation failure.
    pub fn toRgba8Alloc(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        const bytes = try allocator.alloc(u8, self.width * self.height * 4);
        self.toRgba8(bytes);
        return bytes;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "raster: toRgba8Alloc exports packed bytes" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 2, 1);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.red);
    const bytes = try framebuffer.toRgba8Alloc(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 8), bytes.len);
    try std.testing.expectEqual(@as(u8, 255), bytes[0]); // R
    try std.testing.expectEqual(@as(u8, 0), bytes[1]); // G
    try std.testing.expectEqual(@as(u8, 255), bytes[3]); // A
}

test "raster: clearRows and toRgba8Rows touch only their rows" {
    var framebuffer = try mod.Framebuffer.init(std.testing.allocator, 2, 3);
    defer framebuffer.deinit();
    framebuffer.clear(mod.Color.red);
    framebuffer.clearRows(mod.Color.blue, .{ .top = 1, .bottom = 9 });
    try std.testing.expectEqual(mod.Color.red, framebuffer.at(1, 0));
    try std.testing.expectEqual(mod.Color.blue, framebuffer.at(0, 1));
    try std.testing.expectEqual(mod.Color.blue, framebuffer.at(1, 2));
    var bytes: [2 * 3 * 4]u8 = @splat(7);
    framebuffer.toRgba8Rows(&bytes, .{ .top = 1, .bottom = 2 });
    try std.testing.expectEqual(@as(u8, 7), bytes[0]);
    try std.testing.expectEqual(@as(u8, 0), bytes[8]); // row 1, R
    try std.testing.expectEqual(@as(u8, 255), bytes[10]); // row 1, B
    try std.testing.expectEqual(@as(u8, 7), bytes[16]);
}
