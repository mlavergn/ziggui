//! A spacer in the layout tree.

const std = @import("std");
const log = std.log.scoped(.ziggui_spacer_node);

/// Flexible space along a stack's main axis.
pub const SpacerNode = struct {
    const Self = @This();

    /// The least length the spacer takes.
    min_length: f32 = 0,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
