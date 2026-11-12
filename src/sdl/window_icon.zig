//! A window or tray icon as RGBA8 pixels, and the SDL surface made from it.

const std = @import("std");
const log = std.log.scoped(.ziggui_window_icon);
const sdl_c = @import("sdl_c");

/// Row-major RGBA8 icon pixels (`rgba` is `width * height * 4` bytes). See
/// `AppConfig.icon`.
pub const WindowIcon = struct {
    const Self = @This();

    /// The pixels, row-major RGBA8.
    rgba: []const u8,

    /// The width, in pixels.
    width: c_int,

    /// The height, in pixels.
    height: c_int,

    /// Reports whether `rgba` is exactly `width * height` RGBA8 pixels, the
    /// size every icon consumer reads or writes, logging when it is not (a
    /// short buffer would be read past, a long one written past a bitmap).
    ///
    /// - `rgba`: the pixels, row-major RGBA8.
    /// - `width`: the width, in pixels.
    /// - `height`: the height, in pixels.
    /// - Returns: true when the sizes agree and are positive.
    pub fn pixelsMatch(rgba: []const u8, width: c_int, height: c_int) bool {
        if (width <= 0 or height <= 0) {
            log.warn("icon refused: its size is {d}x{d}", .{ width, height });
            return false;
        }
        const pixel_count = std.math.mul(usize, @intCast(width), @intCast(height)) catch return Self.logMismatch(rgba, width, height);
        const byte_count = std.math.mul(usize, pixel_count, 4) catch return Self.logMismatch(rgba, width, height);
        if (rgba.len != byte_count) return Self.logMismatch(rgba, width, height);
        return true;
    }

    /// Builds an `SDL_Surface` from the pixels (the format ziggui's
    /// `Framebuffer.toRgba8Alloc` produces).
    ///
    /// - `self`: the icon.
    /// - Returns: the surface, which the caller destroys, or null on failure
    ///   (including pixels that are not `width * height * 4` bytes).
    pub fn surface(self: *const Self) ?*sdl_c.SDL_Surface {
        if (!Self.pixelsMatch(self.rgba, self.width, self.height)) return null;
        const created = sdl_c.SDL_CreateSurface(self.width, self.height, sdl_c.SDL_PIXELFORMAT_ABGR8888) orelse return null;
        const width: usize = @intCast(self.width);
        const height: usize = @intCast(self.height);
        const pitch: usize = @intCast(created.*.pitch);
        const destination: [*]u8 = @ptrCast(created.*.pixels orelse return created);
        var y: usize = 0;
        while (y < height) : (y += 1) {
            @memcpy(destination[y * pitch ..][0 .. width * 4], self.rgba[y * width * 4 ..][0 .. width * 4]);
        }
        return created;
    }

    /// Logs pixels whose length is not `width * height * 4`.
    ///
    /// - `rgba`: the pixels.
    /// - `width`: the width, in pixels.
    /// - `height`: the height, in pixels.
    /// - Returns: false, for the caller to return.
    fn logMismatch(rgba: []const u8, width: c_int, height: c_int) bool {
        log.warn("icon refused: {d} bytes of pixels for {d}x{d} RGBA8", .{ rgba.len, width, height });
        return false;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "window icon: pixels match only at exactly width * height * 4 bytes" {
    const pixels: [16]u8 = @splat(0);
    try std.testing.expect(WindowIcon.pixelsMatch(&pixels, 2, 2));
    try std.testing.expect(WindowIcon.pixelsMatch(pixels[0..8], 2, 1));
    try std.testing.expect(!WindowIcon.pixelsMatch(pixels[0..15], 2, 2)); // short: read past
    try std.testing.expect(!WindowIcon.pixelsMatch(&pixels, 1, 1)); // long: written past
    try std.testing.expect(!WindowIcon.pixelsMatch(&pixels, 0, 4));
    try std.testing.expect(!WindowIcon.pixelsMatch(&pixels, -2, -2));
    try std.testing.expect(!WindowIcon.pixelsMatch(&pixels, std.math.maxInt(c_int), std.math.maxInt(c_int)));
}
