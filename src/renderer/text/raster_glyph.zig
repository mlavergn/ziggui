//! A rasterized glyph: an 8-bit coverage bitmap and where it sits relative to
//! the pen origin.

const std = @import("std");
const log = std.log.scoped(.ziggui_raster_glyph);

/// A glyph's coverage bitmap and its placement.
pub const RasterGlyph = struct {
    const Self = @This();

    /// The bitmap's width in pixels.
    width: u32,
    /// The bitmap's height in pixels.
    height: u32,
    /// Row-major 8-bit coverage (alpha). Empty for whitespace glyphs.
    data: []u8,
    /// Pixel offset of the bitmap's left edge from the pen origin.
    left: i32,
    /// Pixel offset of the bitmap's top edge above the baseline.
    top: i32,
    /// Horizontal advance in pixels.
    advance: f32,

    /// Free the bitmap.
    ///
    /// - `self`: the glyph.
    /// - `allocator`: the allocator the bitmap came from.
    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        if (self.data.len > 0) allocator.free(self.data);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
