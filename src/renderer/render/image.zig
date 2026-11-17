//! An RGBA8 image.

const std = @import("std");
const log = std.log.scoped(.ziggui_image);

/// An RGBA8 image, row-major, 4 bytes per pixel.
pub const Image = struct {
    const Self = @This();

    /// The image's width, in pixels.
    width: u32,
    /// The image's height, in pixels.
    height: u32,
    /// Four bytes (R, G, B, A) per pixel, rows top-down.
    pixels: []const u8,

    /// The bytes `width` × `height` pixels take, four each.
    ///
    /// - `self`: the image.
    /// - Returns: the size; the largest `u64` for one past it (no image that
    ///   size is ever whole).
    pub fn byteLength(self: *const Self) u64 {
        return @as(u64, self.width) *| self.height *| 4;
    }

    /// Whether `pixels` holds every pixel the size says: an image a platform
    /// handed over may be short, and is then never read.
    ///
    /// - `self`: the image.
    /// - Returns: true when no pixel is missing.
    pub fn isWhole(self: *const Self) bool {
        return self.byteLength() <= self.pixels.len;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "image: whole only with every pixel its size says" {
    const pixels: [16]u8 = @splat(0);
    try std.testing.expect((Image{ .width = 2, .height = 2, .pixels = &pixels }).isWhole());
    try std.testing.expect(!(Image{ .width = 2, .height = 3, .pixels = &pixels }).isWhole());
    const huge = Image{ .width = std.math.maxInt(u32), .height = std.math.maxInt(u32), .pixels = &pixels };
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), huge.byteLength());
    try std.testing.expect(!huge.isWhole());
}
