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
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
