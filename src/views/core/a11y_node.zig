//! One node of the accessibility tree a frame emits.

const std = @import("std");
const log = std.log.scoped(.ziggui_a11y_node);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One node of the accessibility tree ziggui emits in parallel with drawing
/// (there is no native view hierarchy to introspect). A platform bridge consumes
/// this tree; it is also directly assertable in headless tests.
pub const A11yNode = struct {
    const Self = @This();

    /// The node's frame.
    rect: renderer.Rect,

    /// What it is.
    role: mod.A11yRole,

    /// What it says.
    label: []const u8 = "",

    /// Its value ("on", a slider's number, a field's text).
    value: []const u8 = "",

    /// It is the selected one of a group (a segment, a tab).
    selected: bool = false,

    /// Its stable name for tests and UI automation (`View.accessibilityIdentifier`);
    /// empty for none.
    identifier: []const u8 = "",

    /// The node a frame emitted with an identifier, as a test finds a control.
    ///
    /// - `nodes`: the frame's accessibility tree.
    /// - `identifier`: the identifier looked for; empty finds nothing.
    /// - Returns: the first node with it, or null when none has it.
    pub fn find(nodes: []const Self, identifier: []const u8) ?*const Self {
        if (identifier.len == 0) return null;
        for (nodes) |*node| {
            if (std.mem.eql(u8, node.identifier, identifier)) return node;
        }
        return null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(A11yNode);
    // Nothing here does I/O to trace.
    _ = log;
}

test "an accessibility node is found by its identifier, never by an empty one" {
    const nodes = [_]A11yNode{
        .{ .rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 }, .role = .button, .label = "Save" },
        .{ .rect = .{ .x = 0, .y = 10, .width = 10, .height = 10 }, .role = .button, .label = "Delete", .identifier = "delete-button" },
    };
    try std.testing.expectEqualStrings("Delete", A11yNode.find(&nodes, "delete-button").?.label);
    try std.testing.expectEqual(null, A11yNode.find(&nodes, "missing"));
    try std.testing.expectEqual(null, A11yNode.find(&nodes, ""));
}
