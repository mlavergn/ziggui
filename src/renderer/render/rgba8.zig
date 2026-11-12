//! A color as four 8-bit channels.

const std = @import("std");
const log = std.log.scoped(.ziggui_rgba8);

/// A color as four 8-bit channels (straight alpha).
pub const Rgba8 = struct {
    const Self = @This();

    /// Red, 0...255.
    r: u8,
    /// Green, 0...255.
    g: u8,
    /// Blue, 0...255.
    b: u8,
    /// Alpha, 0...255.
    a: u8,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
