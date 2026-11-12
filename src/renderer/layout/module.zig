//! The layout tree and the engine that measures and arranges it.

const std = @import("std");
const log = std.log.scoped(.ziggui_layout_module);

/// A size a parent proposes to a child.
pub const Proposal = @import("proposal.zig").Proposal;
/// The intrinsic sizing of a layout leaf.
pub const SizingHints = @import("sizing_hints.zig").SizingHints;
/// The direction a stack runs in.
pub const Direction = @import("direction.zig").Direction;
/// A stack in the layout tree.
pub const StackNode = @import("stack_node.zig").StackNode;
/// Padding around a child in the layout tree.
pub const PaddingNode = @import("padding_node.zig").PaddingNode;
/// A frame modifier in the layout tree.
pub const FrameNode = @import("frame_node.zig").FrameNode;
/// A spacer in the layout tree.
pub const SpacerNode = @import("spacer_node.zig").SpacerNode;
/// A leaf that measures itself against the live proposal.
pub const MeasuredNode = @import("measured_node.zig").MeasuredNode;
/// A node of the layout tree.
pub const Node = @import("node.zig").Node;
/// The placement the arrange pass produces for a node.
pub const LayoutResult = @import("layout_result.zig").LayoutResult;
/// One stack child's main-axis bounds.
pub const FlexItem = @import("flex_item.zig").FlexItem;
/// Per-call scratch storage for a stack's children.
pub const Scratch = @import("scratch.zig").Scratch;
/// Shares a stack's main-axis length among its children.
pub const SpaceDistributor = @import("space_distributor.zig").SpaceDistributor;
/// Measures and arranges layout trees.
pub const LayoutEngine = @import("layout_engine.zig").LayoutEngine;

/// A 2D point (from the renderer).
pub const Point = @import("../module.zig").Point;
/// A 2D extent (from the renderer).
pub const Size = @import("../module.zig").Size;
/// An axis-aligned rectangle (from the renderer).
pub const Rect = @import("../module.zig").Rect;
/// Per-side spacing (from the renderer).
pub const EdgeInsets = @import("../module.zig").EdgeInsets;
/// A 2D alignment (from the renderer).
pub const Alignment = @import("../module.zig").Alignment;
/// The two layout axes (from the renderer).
pub const Axis = @import("../module.zig").Axis;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("proposal.zig");
    _ = @import("sizing_hints.zig");
    _ = @import("direction.zig");
    _ = @import("stack_node.zig");
    _ = @import("padding_node.zig");
    _ = @import("frame_node.zig");
    _ = @import("spacer_node.zig");
    _ = @import("measured_node.zig");
    _ = @import("node.zig");
    _ = @import("layout_result.zig");
    _ = @import("flex_item.zig");
    _ = @import("scratch.zig");
    _ = @import("space_distributor.zig");
    _ = @import("layout_engine.zig");
}
