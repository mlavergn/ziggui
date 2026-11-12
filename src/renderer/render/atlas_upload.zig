//! A pending texture-atlas region upload.

const std = @import("std");
const log = std.log.scoped(.ziggui_atlas_upload);

/// A pending region upload: RGBA8 pixels (arena-owned, valid for one frame)
/// destined for (x, y) in the atlas texture.
pub const AtlasUpload = struct {
    const Self = @This();

    /// The region's left edge in the atlas.
    x: u32,
    /// The region's top edge in the atlas.
    y: u32,
    /// The region's width.
    width: u32,
    /// The region's height.
    height: u32,
    /// The RGBA8 pixels, rows top-down.
    pixels: []const u8,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
