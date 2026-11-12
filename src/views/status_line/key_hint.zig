//! One `key action` pair of a `StatusLine`.

const std = @import("std");
const log = std.log.scoped(.ziggui_key_hint);

/// One `key action` pair of a `StatusLine`: a key, as a terminal UI names
/// it (`enter`, `shift+tab`, `ctrl+N`), and what it does now.
pub const KeyHint = struct {
    const Self = @This();

    /// The key.
    key: []const u8,

    /// What it does.
    action: []const u8,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
