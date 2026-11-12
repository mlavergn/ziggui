//! A frame modifier in the layout tree.

const std = @import("std");
const log = std.log.scoped(.ziggui_frame_node);
const mod = @import("module.zig");

/// A frame modifier: fixed dimensions and/or min/max bounds with an alignment
/// for placing the child inside the resulting box.
pub const FrameNode = struct {
    const Self = @This();

    /// A fixed width, or null to follow the child.
    width: ?f32 = null,
    /// A fixed height, or null to follow the child.
    height: ?f32 = null,
    /// The least width, or null for none.
    min_width: ?f32 = null,
    /// The most width (infinity fills the proposal), or null for none.
    max_width: ?f32 = null,
    /// The least height, or null for none.
    min_height: ?f32 = null,
    /// The most height (infinity fills the proposal), or null for none.
    max_height: ?f32 = null,
    /// Where the child sits inside the frame.
    alignment: mod.Alignment = .center,
    /// The framed child.
    child: *const mod.Node,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
