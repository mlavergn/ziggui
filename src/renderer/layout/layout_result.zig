//! The placement the arrange pass produces for a node.

const std = @import("std");
const log = std.log.scoped(.ziggui_layout_result);
const mod = @import("module.zig");

/// The placement result for a node: its frame plus the placed children.
pub const LayoutResult = struct {
    const Self = @This();

    /// The rect the node was placed in.
    frame: mod.Rect,
    /// The placed children, in the node's order.
    children: []Self = &.{},

    /// Free the children, recursively.
    ///
    /// - `self`: the result.
    /// - `allocator`: the allocator `arrange` was given.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.children) |*child| child.deinit(allocator);
        if (self.children.len > 0) allocator.free(self.children);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
