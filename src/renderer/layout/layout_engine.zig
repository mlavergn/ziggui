//! Layout engine: a two-pass measure/arrange protocol over a tree of layout
//! `Node`s, mirroring SwiftUI's parent-proposes / child-responds model.
//!
//!   measure(node, proposal) -> Size      "given this proposed size, how big?"
//!   arrange(node, rect)      -> Frames    "you got this rect; place yourself"
//!
//! The `Node` union is the structural vocabulary (leaves, spacers, stacks,
//! padding, frames). The view layer maps real components onto these nodes; the
//! engine itself is pure and GPU-free so it is fully unit-testable.

const std = @import("std");
const log = std.log.scoped(.ziggui_layout_engine);
const mod = @import("module.zig");

/// A key into the measure memo: the pointer that makes a node unique and the
/// proposal's two dimensions (each tagged so a missing dimension differs from
/// any value, and the node kind is part of the key).
const MeasureKey = struct {
    const Self = @This();

    /// The node's identifying pointer.
    pointer: usize,
    /// The proposed width with the node kind's tag.
    width_key: u64,
    /// The proposed height.
    height_key: u64,
};

/// The pointer that identifies a node within a frame, and a tag for its kind.
const NodeIdentity = struct {
    const Self = @This();

    /// The identifying pointer.
    pointer: usize,
    /// The node kind's tag.
    tag: u64,
};

/// Measures and arranges layout trees, memoizing measurement within a frame.
pub const LayoutEngine = struct {
    const Self = @This();

    /// An unbounded dimension (`.frame(maxWidth: .infinity)`).
    pub const infinity = std.math.inf(f32);

    /// The proposal a stack measures a child's largest main length at.
    const unbounded: f32 = 1_000_000;

    /// Per-frame memo for `measure`. A stack measures each child up to three
    /// times (min, max, then its share), and every nested stack does the same,
    /// so an uncached measure is exponential in nesting depth — a markdown
    /// bubble is ~15 levels deep. Nodes are immutable once built, so (node
    /// identity, proposal) always measures the same within a frame. The key is
    /// the pointer that makes the node unique: a stack's children slice, a
    /// frame's or padding's child, a measured leaf's context. Live only between
    /// `beginMeasureCache` and `endMeasureCache` (the view layer's `render`),
    /// because the next frame's arena reuses those addresses. The map's storage
    /// persists (cleared, not freed) so a frame never pays for growing it again.
    memo: std.AutoHashMapUnmanaged(MeasureKey, mod.Size) = .empty,

    /// Whether `measure` memoizes (between `beginMeasureCache` and
    /// `endMeasureCache`).
    memo_active: bool = false,

    /// The one engine. Layout runs on one thread (the UI loop), hence a plain
    /// global.
    var shared_engine: Self = .{};

    /// The engine every layout pass shares.
    ///
    /// - Returns: the shared engine.
    pub fn shared() *Self {
        return &shared_engine;
    }

    /// Start memoizing `measure`.
    ///
    /// - `self`: the engine.
    /// - Returns: false when a cache is already active, in which case the
    ///   caller must not end it.
    pub fn beginMeasureCache(self: *Self) bool {
        if (self.memo_active) return false;
        self.memo.clearRetainingCapacity();
        self.memo_active = true;
        return true;
    }

    /// Stop memoizing `measure`.
    ///
    /// - `self`: the engine.
    pub fn endMeasureCache(self: *Self) void {
        self.memo_active = false;
    }

    /// How big `node` is given `proposal`.
    ///
    /// - `self`: the engine.
    /// - `node`: the tree.
    /// - `proposal`: the size offered.
    /// - Returns: the size the node takes.
    pub fn measure(self: *Self, node: mod.Node, proposal: mod.Proposal) mod.Size {
        if (self.memo_active) if (Self.measureKey(node, proposal)) |key| {
            if (self.memo.get(key)) |size| return size;
            const size = self.measureUncached(node, proposal);
            // A failed insert only costs measuring this node again.
            self.memo.put(std.heap.page_allocator, key, size) catch return size;
            return size;
        };
        return self.measureUncached(node, proposal);
    }

    /// The narrowest `node` can be laid out without a child overflowing: a leaf's
    /// minimum, a horizontal stack's children and gaps summed, the widest child
    /// of any other stack, padding added, and a fixed frame's width. A frame that
    /// only caps or fills the width does not lower its child's minimum (`arrange`
    /// still gives the child that much), and a measured leaf (wrapped text) is
    /// zero: it wraps, and reports no wider than it is offered.
    ///
    /// - `self`: the engine.
    /// - `node`: the tree.
    /// - Returns: the width.
    pub fn minWidth(self: *const Self, node: mod.Node) f32 {
        return switch (node) {
            .leaf => |hints| hints.min.width,
            .spacer, .measured => 0,
            .padding => |padding| self.minWidth(padding.child.*) + padding.insets.horizontal(),
            .frame => |frame| frame.width orelse @max(frame.min_width orelse 0, self.minWidth(frame.child.*)),
            .stack => |stack| blk: {
                var width: f32 = 0;
                for (stack.children) |child| {
                    const child_width = if (child == .spacer and stack.direction == .horizontal) child.spacer.min_length else self.minWidth(child);
                    width = if (stack.direction == .horizontal) width + child_width else @max(width, child_width);
                }
                if (stack.direction == .horizontal and stack.children.len > 1) width += stack.spacing * @as(f32, @floatFromInt(stack.children.len - 1));
                break :blk width;
            },
        };
    }

    /// Place `node` and its descendants in `rect`.
    ///
    /// - `self`: the engine.
    /// - `allocator`: allocator for the result's children.
    /// - `node`: the tree.
    /// - `rect`: the rect the node gets.
    /// - Returns: the placements; propagates allocation failure.
    pub fn arrange(self: *Self, allocator: std.mem.Allocator, node: mod.Node, rect: mod.Rect) std.mem.Allocator.Error!mod.LayoutResult {
        switch (node) {
            // Leaf-like nodes simply take the rect they are given.
            .leaf, .spacer, .measured => return .{ .frame = rect },
            .padding => |padding| {
                const inner = rect.inset(padding.insets);
                const child = try allocator.alloc(mod.LayoutResult, 1);
                child[0] = try self.arrange(allocator, padding.child.*, inner);
                return .{ .frame = rect, .children = child };
            },
            .frame => |frame| {
                const child_proposal = mod.Proposal{
                    .width = Self.frameChildProposal(frame.width, frame.max_width, rect.width),
                    .height = Self.frameChildProposal(frame.height, frame.max_height, rect.height),
                };
                const child_size = self.measure(frame.child.*, child_proposal);
                const position = frame.alignment.position(rect.size(), child_size);
                const child_rect = mod.Rect.fromOriginSize(
                    .{ .x = rect.x + position.x, .y = rect.y + position.y },
                    child_size,
                );
                const child = try allocator.alloc(mod.LayoutResult, 1);
                child[0] = try self.arrange(allocator, frame.child.*, child_rect);
                return .{ .frame = rect, .children = child };
            },
            .stack => |stack| return self.arrangeStack(allocator, stack, rect),
        }
    }

    // -------------------------------------------------------------------------
    // Measure pass

    /// One proposal dimension as a memo key part.
    ///
    /// - `dimension`: the proposed length, or null.
    /// - `tag`: the node kind's tag (0 for the height).
    /// - Returns: the key part.
    fn axisKey(dimension: ?f32, tag: u64) u64 {
        return (tag << 33) | if (dimension) |value| @as(u64, @as(u32, @bitCast(value))) else (1 << 32);
    }

    /// The memo key for measuring `node` at `proposal`.
    ///
    /// - `node`: the node.
    /// - `proposal`: the size offered.
    /// - Returns: the key, or null for nodes cheaper to measure than to look up.
    fn measureKey(node: mod.Node, proposal: mod.Proposal) ?MeasureKey {
        const identity: NodeIdentity = switch (node) {
            .leaf, .spacer => return null, // cheaper than a lookup
            .measured => |measured| .{ .pointer = @intFromPtr(measured.context), .tag = 1 },
            .padding => |padding| .{ .pointer = @intFromPtr(padding.child), .tag = 2 },
            .frame => |frame| .{ .pointer = @intFromPtr(frame.child), .tag = 3 },
            .stack => |stack| if (stack.children.len == 0) return null else .{ .pointer = @intFromPtr(stack.children.ptr), .tag = 4 },
        };
        return .{ .pointer = identity.pointer, .width_key = Self.axisKey(proposal.width, identity.tag), .height_key = Self.axisKey(proposal.height, 0) };
    }

    /// `measure` without the memo.
    ///
    /// - `self`: the engine.
    /// - `node`: the node.
    /// - `proposal`: the size offered.
    /// - Returns: the size the node takes.
    fn measureUncached(self: *Self, node: mod.Node, proposal: mod.Proposal) mod.Size {
        return switch (node) {
            .leaf => |hints| .{
                .width = Self.resolveAxis(proposal.width, hints.min.width, hints.ideal.width, hints.max.width),
                .height = Self.resolveAxis(proposal.height, hints.min.height, hints.ideal.height, hints.max.height),
            },
            // A bare spacer outside a stack has no intrinsic size.
            .spacer => mod.Size{},
            .measured => |measured| measured.measure_fn(measured.context, proposal),
            .padding => |padding| blk: {
                const child_size = self.measure(padding.child.*, .{
                    .width = Self.subtractOptional(proposal.width, padding.insets.horizontal()),
                    .height = Self.subtractOptional(proposal.height, padding.insets.vertical()),
                });
                break :blk .{
                    .width = child_size.width + padding.insets.horizontal(),
                    .height = child_size.height + padding.insets.vertical(),
                };
            },
            .frame => |frame| self.measureFrame(frame, proposal),
            .stack => |stack| self.measureStack(stack, proposal),
        };
    }

    /// The size of a frame node.
    ///
    /// - `self`: the engine.
    /// - `frame`: the frame.
    /// - `proposal`: the size offered.
    /// - Returns: the frame's size.
    fn measureFrame(self: *Self, frame: mod.FrameNode, proposal: mod.Proposal) mod.Size {
        const child_proposal = mod.Proposal{
            .width = Self.frameChildProposal(frame.width, frame.max_width, proposal.width),
            .height = Self.frameChildProposal(frame.height, frame.max_height, proposal.height),
        };
        const child_size = self.measure(frame.child.*, child_proposal);
        return .{
            .width = Self.frameAxisSize(frame.width, frame.min_width, frame.max_width, proposal.width, child_size.width),
            .height = Self.frameAxisSize(frame.height, frame.min_height, frame.max_height, proposal.height, child_size.height),
        };
    }

    /// What a frame proposes to its child on one axis.
    ///
    /// - `fixed`: the frame's fixed length, or null.
    /// - `max`: the frame's most length, or null.
    /// - `proposed`: what the frame was offered.
    /// - Returns: the child's proposal.
    fn frameChildProposal(fixed: ?f32, max: ?f32, proposed: ?f32) ?f32 {
        if (fixed) |value| return value;
        if (max) |most| {
            if (most == infinity) return proposed; // fill available
            return if (proposed) |offered| @min(offered, most) else most;
        }
        return proposed;
    }

    /// A frame's length on one axis.
    ///
    /// - `fixed`: the frame's fixed length, or null.
    /// - `min`: the frame's least length, or null.
    /// - `max`: the frame's most length, or null.
    /// - `proposed`: what the frame was offered.
    /// - `child`: the child's length.
    /// - Returns: the frame's length.
    fn frameAxisSize(fixed: ?f32, min: ?f32, max: ?f32, proposed: ?f32, child: f32) f32 {
        if (fixed) |value| return value;
        var length = child;
        if (max) |most| {
            const upper = if (most == infinity) (proposed orelse child) else most;
            length = @min(@max(length, if (most == infinity) (proposed orelse child) else length), upper);
            if (most == infinity) length = proposed orelse child;
        }
        if (min) |least| length = @max(length, least);
        return length;
    }

    /// The size of a stack node.
    ///
    /// - `self`: the engine.
    /// - `stack`: the stack.
    /// - `proposal`: the size offered.
    /// - Returns: the stack's size.
    fn measureStack(self: *Self, stack: mod.StackNode, proposal: mod.Proposal) mod.Size {
        if (stack.children.len == 0) return .{};
        if (stack.direction == .depth) return self.measureDepthStack(stack, proposal);

        const axis: mod.Axis = if (stack.direction == .horizontal) .horizontal else .vertical;
        const main_proposal = Self.mainOf(axis, proposal);
        const cross_proposal = Self.crossOf(axis, proposal);

        var sizes_scratch: mod.Scratch(mod.Size) = .{};
        defer sizes_scratch.deinit();
        const sizes = sizes_scratch.get(stack.children.len);
        self.layoutStackChildren(stack, axis, main_proposal, cross_proposal, sizes);

        var total_main: f32 = 0;
        var max_cross: f32 = 0;
        for (sizes) |child_size| {
            total_main += Self.mainAxis(axis, child_size);
            max_cross = @max(max_cross, Self.crossAxis(axis, child_size));
        }
        total_main += stack.spacing * @as(f32, @floatFromInt(stack.children.len - 1));
        return Self.sizeFrom(axis, total_main, max_cross);
    }

    /// The size of a depth (Z) stack: its largest child on each axis.
    ///
    /// - `self`: the engine.
    /// - `stack`: the stack.
    /// - `proposal`: the size offered.
    /// - Returns: the stack's size.
    fn measureDepthStack(self: *Self, stack: mod.StackNode, proposal: mod.Proposal) mod.Size {
        var width: f32 = 0;
        var height: f32 = 0;
        for (stack.children) |child| {
            const child_size = self.measure(child, proposal);
            width = @max(width, child_size.width);
            height = @max(height, child_size.height);
        }
        return .{ .width = width, .height = height };
    }

    /// Resolve each child's size given the stack's main/cross proposals, writing
    /// results into `sizes`. Shared by measure and arrange so both agree.
    ///
    /// - `self`: the engine.
    /// - `stack`: the stack.
    /// - `axis`: the stack's main axis.
    /// - `main_proposal`: the main-axis length offered, or null.
    /// - `cross_proposal`: the cross-axis length offered, or null.
    /// - `sizes`: receives each child's size.
    fn layoutStackChildren(self: *Self, stack: mod.StackNode, axis: mod.Axis, main_proposal: ?f32, cross_proposal: ?f32, sizes: []mod.Size) void {
        const count = stack.children.len;
        if (main_proposal) |available| {
            // Bounded main axis: distribute space.
            var items_scratch: mod.Scratch(mod.FlexItem) = .{};
            defer items_scratch.deinit();
            const items = items_scratch.get(count);
            for (stack.children, 0..) |child, index| {
                items[index] = .{
                    .min = self.childMain(child, axis, 0, cross_proposal),
                    .max = self.childMain(child, axis, unbounded, cross_proposal),
                };
            }
            var mains_scratch: mod.Scratch(f32) = .{};
            defer mains_scratch.deinit();
            const mains = mains_scratch.get(count);
            const distributor = mod.SpaceDistributor{ .available = available, .spacing = stack.spacing };
            distributor.distribute(items, mains);
            for (stack.children, 0..) |child, index| {
                const child_size = self.measureInStack(child, axis, mains[index], cross_proposal);
                sizes[index] = child_size;
            }
        } else {
            // Unbounded main axis: each child takes its ideal main size.
            for (stack.children, 0..) |child, index| {
                sizes[index] = self.measureInStack(child, axis, null, cross_proposal);
            }
        }
    }

    /// Measure one child within a stack, where a Spacer is oriented along the main
    /// axis.
    ///
    /// - `self`: the engine.
    /// - `child`: the child.
    /// - `axis`: the stack's main axis.
    /// - `main`: the main-axis length offered, or null.
    /// - `cross`: the cross-axis length offered, or null.
    /// - Returns: the child's size.
    fn measureInStack(self: *Self, child: mod.Node, axis: mod.Axis, main: ?f32, cross: ?f32) mod.Size {
        switch (child) {
            .spacer => |spacer| {
                const length = if (main) |value| @max(value, spacer.min_length) else spacer.min_length;
                return Self.sizeFrom(axis, length, 0);
            },
            else => return self.measure(child, Self.proposalFrom(axis, main, cross)),
        }
    }

    /// A stack child's main-axis length.
    ///
    /// - `self`: the engine.
    /// - `child`: the child.
    /// - `axis`: the stack's main axis.
    /// - `main`: the main-axis length offered, or null.
    /// - `cross`: the cross-axis length offered, or null.
    /// - Returns: the length.
    fn childMain(self: *Self, child: mod.Node, axis: mod.Axis, main: ?f32, cross: ?f32) f32 {
        return Self.mainAxis(axis, self.measureInStack(child, axis, main, cross));
    }

    // -------------------------------------------------------------------------
    // Arrange pass

    /// Place a stack's children along its axis.
    ///
    /// - `self`: the engine.
    /// - `allocator`: allocator for the result's children.
    /// - `stack`: the stack.
    /// - `rect`: the rect the stack gets.
    /// - Returns: the placements; propagates allocation failure.
    fn arrangeStack(self: *Self, allocator: std.mem.Allocator, stack: mod.StackNode, rect: mod.Rect) std.mem.Allocator.Error!mod.LayoutResult {
        if (stack.children.len == 0) return .{ .frame = rect };
        if (stack.direction == .depth) return self.arrangeDepthStack(allocator, stack, rect);

        const axis: mod.Axis = if (stack.direction == .horizontal) .horizontal else .vertical;
        const cross_extent = Self.crossAxis(axis, rect.size());

        var sizes_scratch: mod.Scratch(mod.Size) = .{};
        defer sizes_scratch.deinit();
        const sizes = sizes_scratch.get(stack.children.len);
        self.layoutStackChildren(stack, axis, Self.mainAxis(axis, rect.size()), cross_extent, sizes);

        const results = try allocator.alloc(mod.LayoutResult, stack.children.len);
        errdefer allocator.free(results);

        const cross_fraction = Self.crossAlignFraction(axis, stack.alignment);
        var cursor: f32 = Self.mainOfPoint(axis, rect.origin());
        for (stack.children, 0..) |child, index| {
            const child_size = sizes[index];
            const child_cross = Self.crossAxis(axis, child_size);
            const cross_position = Self.crossOfPoint(axis, rect.origin()) + (cross_extent - child_cross) * cross_fraction;
            const child_rect = Self.rectFrom(axis, cursor, cross_position, Self.mainAxis(axis, child_size), child_cross);
            results[index] = try self.arrange(allocator, child, child_rect);
            cursor += Self.mainAxis(axis, child_size) + stack.spacing;
        }
        return .{ .frame = rect, .children = results };
    }

    /// Place a depth (Z) stack's children, each aligned in the whole rect.
    ///
    /// - `self`: the engine.
    /// - `allocator`: allocator for the result's children.
    /// - `stack`: the stack.
    /// - `rect`: the rect the stack gets.
    /// - Returns: the placements; propagates allocation failure.
    fn arrangeDepthStack(self: *Self, allocator: std.mem.Allocator, stack: mod.StackNode, rect: mod.Rect) std.mem.Allocator.Error!mod.LayoutResult {
        const results = try allocator.alloc(mod.LayoutResult, stack.children.len);
        errdefer allocator.free(results);
        for (stack.children, 0..) |child, index| {
            const child_size = self.measure(child, mod.Proposal.fixed(rect.size()));
            const position = stack.alignment.position(rect.size(), child_size);
            const child_rect = mod.Rect.fromOriginSize(
                .{ .x = rect.x + position.x, .y = rect.y + position.y },
                child_size,
            );
            results[index] = try self.arrange(allocator, child, child_rect);
        }
        return .{ .frame = rect, .children = results };
    }

    // -------------------------------------------------------------------------
    // Axis helpers

    /// A leaf's length on one axis: the proposal clamped to its bounds, or
    /// its ideal when unspecified.
    ///
    /// - `proposed`: the length offered, or null.
    /// - `min`: the least length.
    /// - `ideal`: the length when unspecified.
    /// - `max`: the most length.
    /// - Returns: the length.
    fn resolveAxis(proposed: ?f32, min: f32, ideal: f32, max: f32) f32 {
        if (proposed) |offered| return std.math.clamp(offered, min, max);
        return ideal;
    }

    /// `minuend - subtrahend`, keeping a null minuend null.
    ///
    /// - `minuend`: the optional length.
    /// - `subtrahend`: the amount taken off.
    /// - Returns: the difference, or null.
    fn subtractOptional(minuend: ?f32, subtrahend: f32) ?f32 {
        return if (minuend) |value| value - subtrahend else null;
    }

    /// A proposal's main-axis dimension.
    ///
    /// - `axis`: the main axis.
    /// - `proposal`: the proposal.
    /// - Returns: the dimension.
    fn mainOf(axis: mod.Axis, proposal: mod.Proposal) ?f32 {
        return if (axis == .horizontal) proposal.width else proposal.height;
    }

    /// A proposal's cross-axis dimension.
    ///
    /// - `axis`: the main axis.
    /// - `proposal`: the proposal.
    /// - Returns: the dimension.
    fn crossOf(axis: mod.Axis, proposal: mod.Proposal) ?f32 {
        return if (axis == .horizontal) proposal.height else proposal.width;
    }

    /// A size's main-axis dimension.
    ///
    /// - `axis`: the main axis.
    /// - `size`: the size.
    /// - Returns: the dimension.
    fn mainAxis(axis: mod.Axis, size: mod.Size) f32 {
        return if (axis == .horizontal) size.width else size.height;
    }

    /// A size's cross-axis dimension.
    ///
    /// - `axis`: the main axis.
    /// - `size`: the size.
    /// - Returns: the dimension.
    fn crossAxis(axis: mod.Axis, size: mod.Size) f32 {
        return if (axis == .horizontal) size.height else size.width;
    }

    /// A point's main-axis coordinate.
    ///
    /// - `axis`: the main axis.
    /// - `point`: the point.
    /// - Returns: the coordinate.
    fn mainOfPoint(axis: mod.Axis, point: mod.Point) f32 {
        return if (axis == .horizontal) point.x else point.y;
    }

    /// A point's cross-axis coordinate.
    ///
    /// - `axis`: the main axis.
    /// - `point`: the point.
    /// - Returns: the coordinate.
    fn crossOfPoint(axis: mod.Axis, point: mod.Point) f32 {
        return if (axis == .horizontal) point.y else point.x;
    }

    /// A size from main- and cross-axis lengths.
    ///
    /// - `axis`: the main axis.
    /// - `main`: the main-axis length.
    /// - `cross`: the cross-axis length.
    /// - Returns: the size.
    fn sizeFrom(axis: mod.Axis, main: f32, cross: f32) mod.Size {
        return if (axis == .horizontal)
            .{ .width = main, .height = cross }
        else
            .{ .width = cross, .height = main };
    }

    /// A proposal from main- and cross-axis lengths.
    ///
    /// - `axis`: the main axis.
    /// - `main`: the main-axis length, or null.
    /// - `cross`: the cross-axis length, or null.
    /// - Returns: the proposal.
    fn proposalFrom(axis: mod.Axis, main: ?f32, cross: ?f32) mod.Proposal {
        return if (axis == .horizontal)
            .{ .width = main, .height = cross }
        else
            .{ .width = cross, .height = main };
    }

    /// A rect from main- and cross-axis positions and lengths.
    ///
    /// - `axis`: the main axis.
    /// - `main_position`: the main-axis origin.
    /// - `cross_position`: the cross-axis origin.
    /// - `main_length`: the main-axis length.
    /// - `cross_length`: the cross-axis length.
    /// - Returns: the rect.
    fn rectFrom(axis: mod.Axis, main_position: f32, cross_position: f32, main_length: f32, cross_length: f32) mod.Rect {
        return if (axis == .horizontal)
            .{ .x = main_position, .y = cross_position, .width = main_length, .height = cross_length }
        else
            .{ .x = cross_position, .y = main_position, .width = cross_length, .height = main_length };
    }

    /// Where on the cross axis a stack's children sit.
    ///
    /// - `axis`: the main axis.
    /// - `alignment`: the stack's alignment.
    /// - Returns: the cross-axis fraction.
    fn crossAlignFraction(axis: mod.Axis, alignment: mod.Alignment) f32 {
        return if (axis == .horizontal) alignment.vertical.fraction() else alignment.horizontal.fraction();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// Nodes the tests build.
const TestNodes = struct {
    const Self = @This();

    /// A leaf of one fixed size.
    ///
    /// - `width`: the leaf's width.
    /// - `height`: the leaf's height.
    /// - Returns: the node.
    fn leaf(width: f32, height: f32) mod.Node {
        return .{ .leaf = mod.SizingHints.fixedSize(.{ .width = width, .height = height }) };
    }
};

/// A measured leaf standing in for wrapped text.
const WrapProbe = struct {
    const Self = @This();

    /// Height grows as ceil(width / 10).
    ///
    /// - `context`: unused.
    /// - `proposal`: the size offered.
    /// - Returns: the proposed width and its wrapped height.
    fn measure(context: *const anyopaque, proposal: mod.Proposal) mod.Size {
        _ = context;
        const width = proposal.width orelse 0;
        return .{ .width = width, .height = @ceil(width / 10) };
    }
};

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a stack longer than 256 children lays out (heap scratch)" {
    const children = try std.testing.allocator.alloc(mod.Node, 300);
    defer std.testing.allocator.free(children);
    for (children) |*child| child.* = .{ .leaf = mod.SizingHints.fixedSize(.{ .width = 10, .height = 2 }) };
    const size = LayoutEngine.shared().measure(.{ .stack = .{ .direction = .vertical, .spacing = 0, .children = children } }, .{ .width = 100, .height = 1000 });
    try std.testing.expectEqual(@as(f32, 600), size.height);
}

test "minWidth: sums a row, takes a column's widest, and sees through a filling frame" {
    const engine = LayoutEngine.shared();
    const wide = TestNodes.leaf(300, 10);
    const row_children = [_]mod.Node{ TestNodes.leaf(50, 10), .{ .spacer = .{} }, TestNodes.leaf(70, 10) };
    const row = mod.Node{ .stack = .{ .direction = .horizontal, .spacing = 10, .children = &row_children } };
    try std.testing.expectEqual(@as(f32, 140), engine.minWidth(row));
    const filled = mod.Node{ .frame = .{ .max_width = LayoutEngine.infinity, .child = &wide } };
    const column_children = [_]mod.Node{ row, filled };
    const column = mod.Node{ .stack = .{ .direction = .vertical, .spacing = 8, .children = &column_children } };
    const padded = mod.Node{ .padding = .{ .insets = .{ .leading = 20, .trailing = 20 }, .child = &column } };
    try std.testing.expectEqual(@as(f32, 340), engine.minWidth(padded));
    // A fixed frame is its width, whatever its child needs.
    try std.testing.expectEqual(@as(f32, 120), engine.minWidth(.{ .frame = .{ .width = 120, .child = &wide } }));
}

test "measure: leaf reports ideal when proposal unspecified" {
    const node = mod.Node{ .leaf = .{
        .min = .{ .width = 10, .height = 10 },
        .ideal = .{ .width = 50, .height = 20 },
        .max = .{ .width = 100, .height = 100 },
    } };
    try std.testing.expectEqual(mod.Size{ .width = 50, .height = 20 }, LayoutEngine.shared().measure(node, .unspecified));
}

test "measure: leaf clamps to proposal within min/max" {
    const node = mod.Node{ .leaf = .{
        .min = .{ .width = 10, .height = 10 },
        .ideal = .{ .width = 50, .height = 20 },
        .max = .{ .width = 100, .height = 100 },
    } };
    // width 200 clamps down to max 100; height 50 passes through (within bounds)
    try std.testing.expectEqual(mod.Size{ .width = 100, .height = 50 }, LayoutEngine.shared().measure(node, .{ .width = 200, .height = 50 }));
}

test "measure: HStack of two fixed leaves with spacing" {
    const children = [_]mod.Node{ TestNodes.leaf(50, 20), TestNodes.leaf(30, 40) };
    const node = mod.Node{ .stack = .{ .direction = .horizontal, .spacing = 10, .children = &children } };
    // 50 + 10 + 30 = 90 wide, max height 40
    try std.testing.expectEqual(mod.Size{ .width = 90, .height = 40 }, LayoutEngine.shared().measure(node, .unspecified));
}

test "measure: VStack stacks heights, max width" {
    const children = [_]mod.Node{ TestNodes.leaf(50, 20), TestNodes.leaf(30, 40) };
    const node = mod.Node{ .stack = .{ .direction = .vertical, .spacing = 5, .children = &children } };
    try std.testing.expectEqual(mod.Size{ .width = 50, .height = 65 }, LayoutEngine.shared().measure(node, .unspecified));
}

test "arrange: HStack places children sequentially with spacing" {
    const children = [_]mod.Node{ TestNodes.leaf(50, 20), TestNodes.leaf(30, 20) };
    const node = mod.Node{ .stack = .{ .direction = .horizontal, .spacing = 10, .alignment = .top, .children = &children } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try LayoutEngine.shared().arrange(arena.allocator(), node, .{ .x = 0, .y = 0, .width = 90, .height = 20 });
    try std.testing.expectEqual(mod.Rect{ .x = 0, .y = 0, .width = 50, .height = 20 }, result.children[0].frame);
    try std.testing.expectEqual(mod.Rect{ .x = 60, .y = 0, .width = 30, .height = 20 }, result.children[1].frame);
}

test "arrange: Spacer pushes siblings apart" {
    const children = [_]mod.Node{ TestNodes.leaf(50, 20), .{ .spacer = .{} }, TestNodes.leaf(50, 20) };
    const node = mod.Node{ .stack = .{ .direction = .horizontal, .children = &children } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try LayoutEngine.shared().arrange(arena.allocator(), node, .{ .x = 0, .y = 0, .width = 200, .height = 20 });
    try std.testing.expectEqual(@as(f32, 0), result.children[0].frame.x);
    // the spacer occupies the gap: x=50, width=100 (it draws nothing, so its
    // cross size/position is irrelevant)
    try std.testing.expectEqual(@as(f32, 50), result.children[1].frame.x);
    try std.testing.expectEqual(@as(f32, 100), result.children[1].frame.width);
    try std.testing.expectEqual(@as(f32, 150), result.children[2].frame.x);
}

test "arrange: HStack cross-axis alignment centers shorter child" {
    const children = [_]mod.Node{ TestNodes.leaf(50, 40), TestNodes.leaf(30, 10) };
    const node = mod.Node{ .stack = .{ .direction = .horizontal, .alignment = .center, .children = &children } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try LayoutEngine.shared().arrange(arena.allocator(), node, .{ .x = 0, .y = 0, .width = 80, .height = 40 });
    // second child (height 10) centered in 40 -> y = 15
    try std.testing.expectEqual(@as(f32, 15), result.children[1].frame.y);
}

test "measure+arrange: padding wraps child" {
    const child = TestNodes.leaf(50, 20);
    const node = mod.Node{ .padding = .{ .insets = mod.EdgeInsets.all(10), .child = &child } };
    try std.testing.expectEqual(mod.Size{ .width = 70, .height = 40 }, LayoutEngine.shared().measure(node, .unspecified));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try LayoutEngine.shared().arrange(arena.allocator(), node, .{ .x = 0, .y = 0, .width = 70, .height = 40 });
    try std.testing.expectEqual(mod.Rect{ .x = 10, .y = 10, .width = 50, .height = 20 }, result.children[0].frame);
}

test "measure: fixed frame overrides child size" {
    const child = TestNodes.leaf(50, 20);
    const node = mod.Node{ .frame = .{ .width = 100, .height = 100, .child = &child } };
    try std.testing.expectEqual(mod.Size{ .width = 100, .height = 100 }, LayoutEngine.shared().measure(node, .unspecified));
}

test "arrange: fixed frame centers child by default" {
    const child = TestNodes.leaf(50, 20);
    const node = mod.Node{ .frame = .{ .width = 100, .height = 100, .alignment = .center, .child = &child } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try LayoutEngine.shared().arrange(arena.allocator(), node, .{ .x = 0, .y = 0, .width = 100, .height = 100 });
    // (100-50)/2 = 25 ; (100-20)/2 = 40
    try std.testing.expectEqual(mod.Rect{ .x = 25, .y = 40, .width = 50, .height = 20 }, result.children[0].frame);
}

test "measure: frame maxWidth infinity fills proposal" {
    const child = TestNodes.leaf(50, 20);
    const node = mod.Node{ .frame = .{ .max_width = LayoutEngine.infinity, .child = &child } };
    try std.testing.expectEqual(@as(f32, 300), LayoutEngine.shared().measure(node, .{ .width = 300, .height = null }).width);
}

test "measure+arrange: .measured leaf is width-dependent and arranges to its rect" {
    const node = mod.Node{ .measured = .{ .context = undefined, .measure_fn = WrapProbe.measure } };
    try std.testing.expectEqual(@as(f32, 10), LayoutEngine.shared().measure(node, .{ .width = 100, .height = null }).height);
    try std.testing.expectEqual(@as(f32, 5), LayoutEngine.shared().measure(node, .{ .width = 50, .height = null }).height);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try LayoutEngine.shared().arrange(arena.allocator(), node, .{ .x = 1, .y = 2, .width = 30, .height = 40 });
    try std.testing.expectEqual(mod.Rect{ .x = 1, .y = 2, .width = 30, .height = 40 }, result.frame);
}

test "measure: .measured inside a VStack reports its proposed-width height" {
    const children = [_]mod.Node{ .{ .measured = .{ .context = undefined, .measure_fn = WrapProbe.measure } }, TestNodes.leaf(20, 5) };
    const node = mod.Node{ .stack = .{ .direction = .vertical, .spacing = 0, .children = &children } };
    // width 100 -> measured child is 10 tall; plus the 5-tall leaf = 15.
    try std.testing.expectEqual(@as(f32, 15), LayoutEngine.shared().measure(node, .{ .width = 100, .height = null }).height);
}

test "measure+arrange: ZStack overlays children, sized to largest" {
    const children = [_]mod.Node{ TestNodes.leaf(50, 20), TestNodes.leaf(30, 40) };
    const node = mod.Node{ .stack = .{ .direction = .depth, .alignment = .center, .children = &children } };
    try std.testing.expectEqual(mod.Size{ .width = 50, .height = 40 }, LayoutEngine.shared().measure(node, .unspecified));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try LayoutEngine.shared().arrange(arena.allocator(), node, .{ .x = 0, .y = 0, .width = 50, .height = 40 });
    // child0 (50x20) centered -> y=10 ; child1 (30x40) centered -> x=10
    try std.testing.expectEqual(mod.Rect{ .x = 0, .y = 10, .width = 50, .height = 20 }, result.children[0].frame);
    try std.testing.expectEqual(mod.Rect{ .x = 10, .y = 0, .width = 30, .height = 40 }, result.children[1].frame);
}
