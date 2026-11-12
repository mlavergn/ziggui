//! A stack in the layout tree.

const std = @import("std");
const log = std.log.scoped(.ziggui_stack_node);
const mod = @import("module.zig");

/// A stack of children laid out along a direction.
pub const StackNode = struct {
    const Self = @This();

    /// The direction the children run in.
    direction: mod.Direction,
    /// The gap between neighbouring children.
    spacing: f32 = 0,
    /// Where each child sits on the cross axis (both axes for a depth stack).
    alignment: mod.Alignment = .center,
    /// The children, in order.
    children: []const mod.Node,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
