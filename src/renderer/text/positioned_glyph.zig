//! A glyph placed on a line by `TextShaper.layoutLine`.

const std = @import("std");
const log = std.log.scoped(.ziggui_positioned_glyph);
const mod = @import("module.zig");

/// A glyph and its pen position on a line.
pub const PositionedGlyph = struct {
    const Self = @This();

    /// The glyph index within `face`.
    glyph: u16,
    /// Face the glyph belongs to (the primary face or one of its fallbacks).
    /// Glyph indices are per-face, so rasterize from this, not the line's face.
    face: *const mod.TtfFont,
    /// Pen x at the glyph's origin (before its left-side bearing), in pixels.
    x: f32,
    /// Horizontal advance in pixels.
    advance: f32,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
