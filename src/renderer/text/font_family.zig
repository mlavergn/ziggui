//! A font family an app registers: a TrueType face per style it has.

const std = @import("std");
const log = std.log.scoped(.ziggui_font_family);

/// A family's name and the TrueType (`glyf`) bytes of each style it has;
/// borrowed, `FontRegistry.register` copies them. A style it lacks draws in
/// `regular`.
pub const FontFamily = struct {
    const Self = @This();

    /// The name views ask for (`.font(.custom(name, size))`).
    name: []const u8,

    /// The upright, regular-weight face.
    regular: []const u8,

    /// The bold face, or null.
    bold: ?[]const u8 = null,

    /// The italic face, or null.
    italic: ?[]const u8 = null,

    /// The bold italic face, or null.
    bold_italic: ?[]const u8 = null,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
