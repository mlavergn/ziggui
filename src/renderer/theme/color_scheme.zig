//! Light or dark appearance.

const std = @import("std");
const log = std.log.scoped(.ziggui_color_scheme);

/// The OS color scheme a theme is resolved for.
pub const ColorScheme = enum {
    const Self = @This();

    /// Light appearance.
    light,
    /// Dark appearance.
    dark,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
