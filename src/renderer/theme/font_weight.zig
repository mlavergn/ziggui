//! SF-style font weights.

const std = @import("std");
const log = std.log.scoped(.ziggui_font_weight);

/// A font weight, lightest to heaviest.
pub const FontWeight = enum {
    const Self = @This();

    /// Ultra light (100).
    ultraLight,
    /// Thin (200).
    thin,
    /// Light (300).
    light,
    /// Regular (400).
    regular,
    /// Medium (500).
    medium,
    /// Semibold (600).
    semibold,
    /// Bold (700).
    bold,
    /// Heavy (800).
    heavy,
    /// Black (900).
    black,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
