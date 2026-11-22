//! A stable handle to a scene's node.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_node_id);
const mod = @import("module.zig");

/// A handle to a node of a `Scene`: its slot and the slot's generation when
/// the node was added, so a handle to a removed node finds nothing even once
/// its slot holds another node.
pub const SceneNodeId = struct {
    const Self = @This();

    /// The node's slot in the scene.
    slot: u32,
    /// The slot's generation when the node was added.
    generation: u32,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = mod;
}
