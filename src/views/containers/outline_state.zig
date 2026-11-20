//! What a list of `OutlineRow`s folds: which nodes are expanded, and the
//! nodes a list of them shows.

const std = @import("std");
const log = std.log.scoped(.ziggui_outline_state);
const mod = @import("module.zig");

/// One node of an outline, as the app lays its tree out: depth first, each
/// node followed by everything under it (pre-order).
pub const OutlineNode = struct {
    const Self = @This();

    /// The node's stable name (a path, say): what `OutlineState` keeps it
    /// expanded or collapsed by, so a fold survives the tree being laid out
    /// again.
    key: []const u8,

    /// How deep it sits: 0 at the top, its children one more.
    depth: u16 = 0,

    /// Whether it can expand: it has children, or may have once they are
    /// read (a folder whose contents load when it is opened).
    has_children: bool = false,
};

/// The app-owned fold state of one outline (SwiftUI's `OutlineGroup`, its
/// expansion kept by the app, like a `ScrollState`). Every node starts
/// `default_expanded`; `flipped` holds the keys toggled away from it, so
/// `expandAll` and `collapseAll` are one assignment and a node never seen
/// costs nothing. Keys are copied in.
pub const OutlineState = struct {
    const Self = @This();

    /// The indent of each level, in points: a child's chevron sits under its
    /// parent's name.
    pub const indent: f32 = 14;

    /// The width of the chevron's column, in points; a row with no chevron
    /// keeps the column empty, so names line up at each depth.
    pub const chevron_width: f32 = 14;

    /// The space between the chevron's column and the row's content, in points.
    pub const chevron_gap: f32 = 4;

    /// Allocates the copied keys.
    allocator: std.mem.Allocator,

    /// What every node starts as, and what `reset` goes back to.
    initial_expanded: bool,

    /// Whether a node not in `flipped` is expanded.
    default_expanded: bool,

    /// The keys toggled away from `default_expanded`, owned.
    flipped: std.StringHashMapUnmanaged(void) = .empty,

    /// Makes the state of an outline whose nodes all start expanded or all
    /// start collapsed.
    ///
    /// - `allocator`: allocates the copied keys.
    /// - `expanded`: whether nodes start expanded.
    /// - Returns: the state.
    pub fn init(allocator: std.mem.Allocator, expanded: bool) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator, .initial_expanded = expanded, .default_expanded = expanded };
        return self;
    }

    /// Frees the copied keys.
    ///
    /// - `self`: the state.
    pub fn deinit(self: *Self) void {
        self.dropFlips();
        self.flipped.deinit(self.allocator);
    }

    /// Reports whether a node is expanded.
    ///
    /// - `self`: the state.
    /// - `key`: the node's key.
    /// - Returns: true when it is expanded.
    pub fn isExpanded(self: *const Self, key: []const u8) bool {
        return self.flipped.contains(key) != self.default_expanded;
    }

    /// Expands or collapses one node.
    ///
    /// - `self`: the state.
    /// - `key`: the node's key; copied.
    /// - `expanded`: whether it is to be expanded.
    /// - Returns: nothing; propagates allocation failure (the node unchanged).
    pub fn setExpanded(self: *Self, key: []const u8, expanded: bool) std.mem.Allocator.Error!void {
        if (expanded == self.default_expanded) {
            const removed = self.flipped.fetchRemove(key) orelse return;
            self.allocator.free(removed.key);
            return;
        }
        if (self.flipped.contains(key)) return;
        const copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(copy);
        try self.flipped.put(self.allocator, copy, {});
    }

    /// Expands a collapsed node, collapses an expanded one.
    ///
    /// - `self`: the state.
    /// - `key`: the node's key; copied.
    /// - Returns: nothing; propagates allocation failure (the node unchanged).
    pub fn toggle(self: *Self, key: []const u8) std.mem.Allocator.Error!void {
        return self.setExpanded(key, !self.isExpanded(key));
    }

    /// Expands every node.
    ///
    /// - `self`: the state.
    pub fn expandAll(self: *Self) void {
        self.dropFlips();
        self.default_expanded = true;
    }

    /// Collapses every node.
    ///
    /// - `self`: the state.
    pub fn collapseAll(self: *Self) void {
        self.dropFlips();
        self.default_expanded = false;
    }

    /// Puts every node back as it started (a new tree: another folder, say).
    ///
    /// - `self`: the state.
    pub fn reset(self: *Self) void {
        self.dropFlips();
        self.default_expanded = self.initial_expanded;
    }

    /// The nodes a list shows: each one whose ancestors are all expanded.
    ///
    /// - `self`: the state.
    /// - `allocator`: allocates the result.
    /// - `nodes`: the outline, in pre-order.
    /// - Returns: the shown nodes' indices into `nodes`, in order; propagates
    ///   allocation failure.
    pub fn visible(self: *const Self, allocator: std.mem.Allocator, nodes: []const OutlineNode) std.mem.Allocator.Error![]usize {
        // Sized for every node up front: in a build arena, growing would leave
        // each outgrown buffer behind for the rest of the frame.
        var shown: std.ArrayList(usize) = try .initCapacity(allocator, nodes.len);
        errdefer shown.deinit(allocator);
        // While set, nodes deeper than this sit under a collapsed one.
        var hidden_below: ?u16 = null;
        for (nodes, 0..) |node, index| {
            if (hidden_below) |depth| {
                if (node.depth > depth) continue;
                hidden_below = null;
            }
            shown.appendAssumeCapacity(index);
            if (node.has_children and !self.isExpanded(node.key)) hidden_below = node.depth;
        }
        return shown.toOwnedSlice(allocator);
    }

    /// The node a list shows for one: itself when every node holding it is
    /// expanded, else the outermost collapsed one holding it. A selection kept
    /// by node shows there while it is folded away, and on itself again once
    /// its folders open (Collapse All, then opening them one by one).
    ///
    /// - `self`: the state.
    /// - `nodes`: the outline, in pre-order.
    /// - `index`: the node; one past the outline is returned as it is.
    /// - Returns: the shown node's index into `nodes`.
    pub fn shownNode(self: *const Self, nodes: []const OutlineNode, index: usize) usize {
        var shown = index;
        var at = index;
        while (Self.parent(nodes, at)) |holder| : (at = holder) {
            if (!self.isExpanded(nodes[holder].key)) shown = holder;
        }
        return shown;
    }

    /// The node a node sits under: the nearest one before it that is less deep.
    ///
    /// - `nodes`: the outline, in pre-order.
    /// - `index`: the node.
    /// - Returns: the parent's index, or null for a node at the top.
    pub fn parent(nodes: []const OutlineNode, index: usize) ?usize {
        if (index >= nodes.len) return null;
        const depth = nodes[index].depth;
        var at = index;
        while (at > 0) {
            at -= 1;
            if (nodes[at].depth < depth) return at;
        }
        return null;
    }

    /// Frees and forgets every flipped key.
    ///
    /// - `self`: the state.
    fn dropFlips(self: *Self) void {
        var keys = self.flipped.keyIterator();
        while (keys.next()) |key| self.allocator.free(key.*);
        self.flipped.clearRetainingCapacity();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    _ = mod;
}

/// A small tree: `src/` holding `views/` (one file) and a file, then a file
/// at the top, then an empty folder.
const test_nodes = [_]OutlineNode{
    .{ .key = "src/", .has_children = true },
    .{ .key = "src/views/", .depth = 1, .has_children = true },
    .{ .key = "src/views/list.zig", .depth = 2 },
    .{ .key = "src/main.zig", .depth = 1 },
    .{ .key = "README.md" },
    .{ .key = "empty/", .has_children = true },
};

test "an outline that starts collapsed shows its top, and opens a node at a time" {
    var state: OutlineState = .init(std.testing.allocator, false);
    defer state.deinit();
    const top = try state.visible(std.testing.allocator, &test_nodes);
    defer std.testing.allocator.free(top);
    try std.testing.expectEqualSlices(usize, &.{ 0, 4, 5 }, top);

    try state.toggle("src/");
    try std.testing.expect(state.isExpanded("src/"));
    const opened = try state.visible(std.testing.allocator, &test_nodes);
    defer std.testing.allocator.free(opened);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 3, 4, 5 }, opened);

    // An inner node kept open stays hidden while its parent is closed.
    try state.setExpanded("src/views/", true);
    try state.setExpanded("src/", false);
    try std.testing.expect(!state.isExpanded("src/"));
    const closed = try state.visible(std.testing.allocator, &test_nodes);
    defer std.testing.allocator.free(closed);
    try std.testing.expectEqualSlices(usize, &.{ 0, 4, 5 }, closed);
    try state.toggle("src/");
    const both = try state.visible(std.testing.allocator, &test_nodes);
    defer std.testing.allocator.free(both);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 4, 5 }, both);
}

test "expand all and collapse all drop the folds, and reset goes back to the start" {
    var state: OutlineState = .init(std.testing.allocator, false);
    defer state.deinit();
    try state.toggle("src/");
    state.expandAll();
    try std.testing.expect(state.isExpanded("src/views/"));
    try std.testing.expectEqual(0, state.flipped.count());
    const all = try state.visible(std.testing.allocator, &test_nodes);
    defer std.testing.allocator.free(all);
    try std.testing.expectEqual(test_nodes.len, all.len);

    // Folded from expanded: one key held, freed when the state goes.
    try state.toggle("src/views/");
    try std.testing.expect(!state.isExpanded("src/views/"));
    const folded = try state.visible(std.testing.allocator, &test_nodes);
    defer std.testing.allocator.free(folded);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 3, 4, 5 }, folded);

    state.collapseAll();
    try std.testing.expect(!state.isExpanded("src/"));
    try state.toggle("src/");
    state.reset();
    try std.testing.expect(!state.isExpanded("src/"));
    try std.testing.expectEqual(0, state.flipped.count());

    var open: OutlineState = .init(std.testing.allocator, true);
    defer open.deinit();
    try std.testing.expect(open.isExpanded("anything"));
}

test "a node folded away shows on the outermost collapsed node holding it" {
    var state: OutlineState = .init(std.testing.allocator, false);
    defer state.deinit();
    try std.testing.expectEqual(0, state.shownNode(&test_nodes, 2));
    try state.toggle("src/");
    try std.testing.expectEqual(1, state.shownNode(&test_nodes, 2));
    try state.toggle("src/views/");
    try std.testing.expectEqual(2, state.shownNode(&test_nodes, 2));
    // An open inner folder under a closed one: the closed one shows it.
    try state.toggle("src/");
    try std.testing.expectEqual(0, state.shownNode(&test_nodes, 2));
    try std.testing.expectEqual(0, state.shownNode(&test_nodes, 0));
    try std.testing.expectEqual(4, state.shownNode(&test_nodes, 4));
    try std.testing.expectEqual(99, state.shownNode(&test_nodes, 99));
}

test "a node's parent is the nearest one before it that is less deep" {
    try std.testing.expectEqual(null, OutlineState.parent(&test_nodes, 0));
    try std.testing.expectEqual(0, OutlineState.parent(&test_nodes, 1));
    try std.testing.expectEqual(1, OutlineState.parent(&test_nodes, 2));
    try std.testing.expectEqual(0, OutlineState.parent(&test_nodes, 3));
    try std.testing.expectEqual(null, OutlineState.parent(&test_nodes, 4));
    try std.testing.expectEqual(null, OutlineState.parent(&test_nodes, 99));
}
