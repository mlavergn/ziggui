//! The direction a layout stack runs in.

const std = @import("std");
const log = std.log.scoped(.ziggui_direction);

/// The direction a stack lays its children out in.
pub const Direction = enum {
    const Self = @This();

    /// Side by side (HStack).
    horizontal,
    /// Top to bottom (VStack).
    vertical,
    /// Overlaid (ZStack).
    depth,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
