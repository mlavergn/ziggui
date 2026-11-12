//! A named text style: point size + weight (and a line-height multiple used by
//! the text layout pass).

const std = @import("std");
const log = std.log.scoped(.ziggui_text_style);
const mod = @import("module.zig");

/// A point size, weight and line-height multiple.
pub const TextStyle = struct {
    const Self = @This();

    /// The point size.
    size: f32,
    /// The weight.
    weight: mod.FontWeight = .regular,
    /// The line height as a multiple of the size.
    line_height: f32 = 1.2,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
