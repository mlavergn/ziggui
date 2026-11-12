//! A node of the layout tree.

const std = @import("std");
const log = std.log.scoped(.ziggui_node);
const mod = @import("module.zig");

/// A node in the layout tree: the structural vocabulary (leaves, spacers,
/// stacks, padding, frames) the view layer maps its components onto.
pub const Node = union(enum) {
    const Self = @This();

    /// Content with intrinsic sizing.
    leaf: mod.SizingHints,
    /// Flexible space.
    spacer: mod.SpacerNode,
    /// Content that measures itself against the proposal.
    measured: mod.MeasuredNode,
    /// Children along a direction.
    stack: mod.StackNode,
    /// A child inset by padding.
    padding: mod.PaddingNode,
    /// A child inside a frame.
    frame: mod.FrameNode,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
