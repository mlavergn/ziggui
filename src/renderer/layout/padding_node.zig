//! Padding around a child in the layout tree.

const std = @import("std");
const log = std.log.scoped(.ziggui_padding_node);
const mod = @import("module.zig");

/// A child inset by per-side padding.
pub const PaddingNode = struct {
    const Self = @This();

    /// The space around the child.
    insets: mod.EdgeInsets,
    /// The padded child.
    child: *const mod.Node,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
