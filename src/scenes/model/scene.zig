//! A 3D scene: a graph of nodes under a root, the light that fills it, and
//! the node it is seen from.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One slot of the graph: a node, its parent's slot, and the slot's
/// generation (bumped as its node goes, so old handles find nothing).
const SceneSlot = struct {
    const Self = @This();

    /// The node, while `live`.
    node: mod.SceneNode,
    /// The parent's slot, null for the root.
    parent: ?u32,
    /// Bumped each time the slot's node is removed.
    generation: u32 = 0,
    /// Whether the slot holds a node.
    live: bool,
};

/// A node the walk has still to visit, with its parent's transform in the
/// scene's space.
const PendingVisit = struct {
    const Self = @This();

    /// The node's slot.
    slot: u32,
    /// Its parent's transform in the scene's space.
    parent_world: mod.Mat4,
    /// Its parent's opacity, its ancestors' multiplied in.
    parent_opacity: f32,
};

/// A node reached by walking the graph, with its transform in the scene's
/// space (its parents' composed with its own).
pub const SceneVisit = struct {
    const Self = @This();

    /// The node's handle.
    id: mod.SceneNodeId,
    /// The node.
    node: *const mod.SceneNode,
    /// Its transform in the scene's space.
    world: mod.Mat4,
    /// Its opacity times its ancestors', 0 to 1.
    opacity: f32,
};

/// A 3D scene the app owns (SceneKit's `SCNScene`): nodes in a tree under a
/// root, each placed in its parent's space, so moving a node moves its
/// children, lights and cameras with it. A `SceneView` draws it seen from
/// `point_of_view`. Nodes are reached by `SceneNodeId` handles, which stay
/// valid until their node is removed.
pub const Scene = struct {
    const Self = @This();

    /// The light that reaches every surface evenly, in sRGB.
    ambient: renderer.Color = renderer.Color.white,
    /// How bright the ambient light is.
    ambient_intensity: f32 = 0.25,
    /// What fills the view behind the nodes (the view paints it before the
    /// scene, as any fill), or null to show what the window drew behind it.
    background: ?renderer.Color = null,
    /// The node carrying the camera the scene is seen through (SceneKit's
    /// `pointOfView`), or null for a default camera 5 units back along +Z,
    /// looking at `camera_target`.
    point_of_view: ?mod.SceneNodeId = null,
    /// The point camera control orbits and zooms about, in the space of the
    /// point-of-view node's parent.
    camera_target: mod.Vec3 = mod.Vec3.zero,
    /// Where a `SceneView` last drew the scene (the view writes it).
    viewport: ?mod.SceneViewport = null,
    /// How shadows and reflections are drawn: `rayTraced` where the GPU can
    /// trace rays, else `rasterized` whatever this asks.
    lighting_technique: mod.SceneLightingTechnique = .rasterized,

    /// What the nodes are kept with.
    allocator: std.mem.Allocator,
    /// The graph's slots; slot 0 is the root.
    slots: std.ArrayList(SceneSlot) = .empty,
    /// The empty slots, reused before the graph grows.
    free_slots: std.ArrayList(u32) = .empty,

    /// An empty scene: a root node and nothing else.
    ///
    /// - `allocator`: what the nodes are kept with.
    /// - Returns: the scene; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        var self = Self{ .allocator = allocator };
        try self.slots.append(allocator, .{ .node = .{ .name = "root" }, .parent = null, .live = true });
        return self;
    }

    /// Frees the nodes. Handles to them find nothing afterwards.
    ///
    /// - `self`: the scene.
    pub fn deinit(self: *Self) void {
        self.slots.deinit(self.allocator);
        self.free_slots.deinit(self.allocator);
    }

    /// The root node, the top of the tree, which is never removed.
    ///
    /// - `self`: the scene.
    /// - Returns: its handle.
    pub fn root(self: *const Self) mod.SceneNodeId {
        _ = self;
        return .{ .slot = 0, .generation = 0 };
    }

    /// Adds a node under a parent.
    ///
    /// - `self`: the scene.
    /// - `parent`: the parent's handle.
    /// - `child`: the node, copied in.
    /// - Returns: the node's handle; `error.NoSuchNode` when the parent is
    ///   gone; propagates allocation failure.
    pub fn addChild(self: *Self, parent: mod.SceneNodeId, child: mod.SceneNode) error{ OutOfMemory, NoSuchNode }!mod.SceneNodeId {
        if (!self.contains(parent)) return error.NoSuchNode;
        if (self.free_slots.pop()) |slot| {
            const reused = &self.slots.items[slot];
            reused.node = child;
            reused.parent = parent.slot;
            reused.live = true;
            return .{ .slot = slot, .generation = reused.generation };
        }
        const slot: u32 = @intCast(self.slots.items.len);
        try self.slots.append(self.allocator, .{ .node = child, .parent = parent.slot, .live = true });
        return .{ .slot = slot, .generation = 0 };
    }

    /// Removes a node and every node under it. The root, or a node already
    /// gone, is left as it is.
    ///
    /// - `self`: the scene.
    /// - `id`: the node's handle.
    pub fn remove(self: *Self, id: mod.SceneNodeId) void {
        if (!self.contains(id) or id.slot == 0) return;
        self.release(id.slot);
        // A live node under a released one goes too, until none is left: the
        // graph keeps only parent links, and a reused slot's parent may come
        // after it.
        var released = true;
        while (released) {
            released = false;
            for (self.slots.items, 0..) |slot, index| {
                if (!slot.live) continue;
                const parent = slot.parent orelse continue;
                if (self.slots.items[parent].live) continue;
                self.release(@intCast(index));
                released = true;
            }
        }
    }

    /// The node a handle names, for reading or changing it.
    ///
    /// - `self`: the scene.
    /// - `id`: the handle.
    /// - Returns: the node, or null when it is gone.
    pub fn node(self: *Self, id: mod.SceneNodeId) ?*mod.SceneNode {
        if (!self.contains(id)) return null;
        return &self.slots.items[id.slot].node;
    }

    /// The parent of a node.
    ///
    /// - `self`: the scene.
    /// - `id`: the node's handle.
    /// - Returns: the parent's handle, or null for the root or a node gone.
    pub fn parentOf(self: *const Self, id: mod.SceneNodeId) ?mod.SceneNodeId {
        if (!self.contains(id)) return null;
        const parent = self.slots.items[id.slot].parent orelse return null;
        return .{ .slot = parent, .generation = self.slots.items[parent].generation };
    }

    /// Whether a handle still names a node.
    ///
    /// - `self`: the scene.
    /// - `id`: the handle.
    /// - Returns: true while its node is in the scene.
    pub fn contains(self: *const Self, id: mod.SceneNodeId) bool {
        if (id.slot >= self.slots.items.len) return false;
        const slot = self.slots.items[id.slot];
        return slot.live and slot.generation == id.generation;
    }

    /// How many nodes the scene holds, the root included.
    ///
    /// - `self`: the scene.
    /// - Returns: the count.
    pub fn count(self: *const Self) usize {
        var live: usize = 0;
        for (self.slots.items) |slot| {
            if (slot.live) live += 1;
        }
        return live;
    }

    /// A node's transform in the scene's space: its parents' composed with
    /// its own, the root's first.
    ///
    /// - `self`: the scene.
    /// - `id`: the node's handle.
    /// - Returns: the transform, or null when the node is gone.
    pub fn worldTransform(self: *const Self, id: mod.SceneNodeId) ?mod.Mat4 {
        if (!self.contains(id)) return null;
        var world = self.slots.items[id.slot].node.transform.matrix();
        var parent = self.slots.items[id.slot].parent;
        while (parent) |slot| : (parent = self.slots.items[slot].parent) {
            world = self.slots.items[slot].node.transform.matrix().multiply(world);
        }
        return world;
    }

    /// Every node not hidden (nor under a hidden one), parents before their
    /// children, siblings in the order of their slots, each with its
    /// transform in the scene's space, composed parent first, and its
    /// opacity multiplied by its ancestors'.
    ///
    /// - `self`: the scene.
    /// - `allocator`: what the visits (and the walk's scratch) are allocated with.
    /// - Returns: the visits; propagates allocation failure.
    pub fn walk(self: *const Self, allocator: std.mem.Allocator) error{OutOfMemory}![]SceneVisit {
        const slot_count = self.slots.items.len;
        // Each slot's children as a linked list through `next_sibling`,
        // threaded so siblings keep slot order.
        const first_child = try allocator.alloc(?u32, slot_count);
        defer allocator.free(first_child);
        const next_sibling = try allocator.alloc(?u32, slot_count);
        defer allocator.free(next_sibling);
        @memset(first_child, null);
        @memset(next_sibling, null);
        var index = slot_count;
        while (index > 0) {
            index -= 1;
            const slot = self.slots.items[index];
            if (!slot.live) continue;
            const parent = slot.parent orelse continue;
            next_sibling[index] = first_child[parent];
            first_child[parent] = @intCast(index);
        }

        var visits: std.ArrayList(SceneVisit) = .empty;
        errdefer visits.deinit(allocator);
        var pending: std.ArrayList(PendingVisit) = .empty;
        defer pending.deinit(allocator);
        try pending.append(allocator, .{ .slot = 0, .parent_world = mod.Mat4.identity, .parent_opacity = 1 });
        while (pending.pop()) |entry| {
            const slot = &self.slots.items[entry.slot];
            if (slot.node.hidden) continue;
            const world = entry.parent_world.multiply(slot.node.transform.matrix());
            const opacity = entry.parent_opacity * std.math.clamp(slot.node.opacity, 0, 1);
            try visits.append(allocator, .{ .id = .{ .slot = entry.slot, .generation = slot.generation }, .node = &slot.node, .world = world, .opacity = opacity });
            // Reversed once pushed, so the first child is popped, so visited, next.
            const children_start = pending.items.len;
            var child = first_child[entry.slot];
            while (child) |child_slot| : (child = next_sibling[child_slot]) {
                try pending.append(allocator, .{ .slot = child_slot, .parent_world = world, .parent_opacity = opacity });
            }
            std.mem.reverse(PendingVisit, pending.items[children_start..]);
        }
        return visits.toOwnedSlice(allocator);
    }

    /// Empties a slot: its node goes, its generation moves on and the slot
    /// waits to be reused.
    ///
    /// - `self`: the scene.
    /// - `slot`: the slot.
    fn release(self: *Self, slot: u32) void {
        const released = &self.slots.items[slot];
        released.live = false;
        released.generation +%= 1;
        released.node = .{};
        self.free_slots.append(self.allocator, slot) catch |err| {
            // The slot stays empty but unused: the scene only grows.
            log.warn("scene slot not kept for reuse: {s}", .{@errorName(err)});
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "a scene starts with its root, adds children under it, and finds them by handle" {
    var scene = try Scene.init(std.testing.allocator);
    defer scene.deinit();
    try std.testing.expectEqual(@as(usize, 1), scene.count());
    const child = try scene.addChild(scene.root(), .{ .name = "child" });
    try std.testing.expectEqualStrings("child", scene.node(child).?.name);
    try std.testing.expectEqual(scene.root(), scene.parentOf(child).?);
    try std.testing.expectEqual(null, scene.parentOf(scene.root()));
    try std.testing.expectError(error.NoSuchNode, scene.addChild(.{ .slot = 9, .generation = 0 }, .{}));
}

test "removing a node removes its subtree; its handle finds nothing once its slot is reused" {
    var scene = try Scene.init(std.testing.allocator);
    defer scene.deinit();
    const parent = try scene.addChild(scene.root(), .{ .name = "parent" });
    const child = try scene.addChild(parent, .{ .name = "child" });
    const grandchild = try scene.addChild(child, .{ .name = "grandchild" });
    const sibling = try scene.addChild(scene.root(), .{ .name = "sibling" });
    scene.remove(parent);
    try std.testing.expect(!scene.contains(parent) and !scene.contains(child) and !scene.contains(grandchild));
    try std.testing.expect(scene.contains(sibling));
    try std.testing.expectEqual(@as(usize, 2), scene.count());

    // The freed slots are reused, but the old handles still find nothing.
    const reused = try scene.addChild(sibling, .{ .name = "reused" });
    try std.testing.expect(reused.slot <= grandchild.slot);
    try std.testing.expectEqual(null, scene.node(parent));
    try std.testing.expectEqual(null, scene.node(child));
    try std.testing.expectEqual(null, scene.node(grandchild));
    try std.testing.expectEqualStrings("reused", scene.node(reused).?.name);
    // The root stays.
    scene.remove(scene.root());
    try std.testing.expect(scene.contains(scene.root()));
}

test "a child moves with its parent, and the walk composes parents first and skips hidden nodes" {
    const allocator = std.testing.allocator;
    var scene = try Scene.init(allocator);
    defer scene.deinit();
    const arm = try scene.addChild(scene.root(), .{ .transform = .{
        .position = mod.Vec3.init(1, 0, 0),
        .rotation = mod.Quaternion.fromAxisAngle(mod.Vec3.up, std.math.pi / 2.0),
    } });
    const hand = try scene.addChild(arm, .{ .transform = .{ .position = mod.Vec3.init(1, 0, 0) } });
    _ = try scene.addChild(scene.root(), .{ .hidden = true });

    // The hand is one unit along the arm's X, which the arm turned to -Z.
    const hand_at = scene.worldTransform(hand).?.transformPoint(mod.Vec3.zero);
    try std.testing.expect(hand_at.approxEql(mod.Vec3.init(1, 0, -1), 1e-5));
    scene.node(arm).?.transform.position = mod.Vec3.init(0, 2, 0);
    try std.testing.expect(scene.worldTransform(hand).?.transformPoint(mod.Vec3.zero).approxEql(mod.Vec3.init(0, 2, -1), 1e-5));

    const visits = try scene.walk(allocator);
    defer allocator.free(visits);
    try std.testing.expectEqual(@as(usize, 3), visits.len);
    try std.testing.expectEqual(scene.root(), visits[0].id);
    try std.testing.expectEqual(arm, visits[1].id);
    try std.testing.expectEqual(hand, visits[2].id);
    try std.testing.expect(visits[2].world.approxEql(scene.worldTransform(hand).?, 1e-5));
}
