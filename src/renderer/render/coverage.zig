//! An 8-bit coverage mask.

const std = @import("std");
const log = std.log.scoped(.ziggui_coverage);

/// An 8-bit single-channel coverage bitmap (e.g. a rasterized glyph), row-major.
pub const Coverage = struct {
    const Self = @This();

    /// The mask's width, in texels.
    width: u32,
    /// The mask's height, in texels.
    height: u32,
    /// One coverage byte per texel, rows top-down.
    data: []const u8,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
