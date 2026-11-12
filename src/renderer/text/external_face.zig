//! A face whose outlines another engine reads (the app layer's system fonts via
//! stb_truetype, which handles CFF and collections): `TtfFont.fromExternal`
//! routes glyph lookup, advances and rasterizing here, so the core stays C-free.

const std = @import("std");
const log = std.log.scoped(.ziggui_external_face);
const mod = @import("module.zig");

/// The callbacks an external font engine supplies.
pub const ExternalFace = struct {
    const Self = @This();

    /// The engine's own face, passed back to every callback.
    context: *const anyopaque,
    /// Map a codepoint to a glyph index (0 = missing).
    glyph_index: *const fn (context: *const anyopaque, codepoint: u21) u16,
    /// Advance in font units.
    advance_width: *const fn (context: *const anyopaque, glyph: u16) u16,
    /// Rasterize a glyph at `scale` (font units to pixels).
    rasterize: *const fn (context: *const anyopaque, allocator: std.mem.Allocator, glyph: u16, scale: f32) std.mem.Allocator.Error!mod.RasterGlyph,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
