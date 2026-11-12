//! Builds stack views from tuples or slices of children.

const std = @import("std");
const log = std.log.scoped(.ziggui_stack_builder);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Builds stack views: what `VStack`/`HStack`/`ZStack` are made with, and what
/// composed containers use to assemble rows and columns.
pub const StackBuilder = struct {
    const Self = @This();

    /// A stack of `children` (a tuple literal or a slice of views).
    ///
    /// - `direction`: vertical, horizontal or layered.
    /// - `spacing`: space between children.
    /// - `alignment`: cross-axis alignment.
    /// - `children`: the children.
    /// - Returns: the stack.
    pub fn make(direction: renderer.Direction, spacing: f32, alignment: renderer.Alignment, children: anytype) mod.View {
        return Self.fromSlice(direction, spacing, alignment, Self.toViews(children));
    }

    /// A stack over an already-allocated slice of children (kept, not copied).
    ///
    /// - `direction`: vertical, horizontal or layered.
    /// - `spacing`: space between children.
    /// - `alignment`: cross-axis alignment.
    /// - `views`: the children, in the build arena.
    /// - Returns: the stack.
    pub fn fromSlice(direction: renderer.Direction, spacing: f32, alignment: renderer.Alignment, views: []const mod.View) mod.View {
        return .{ .kind = .{ .stack = .{
            .direction = direction,
            .spacing = spacing,
            .alignment = alignment,
            .children = Self.flattenGroups(views),
        } } };
    }

    /// Normalizes a tuple literal or `[]const View` into an owned `[]View` in the
    /// build arena, for composed containers that accept variadic children.
    ///
    /// - `children`: a tuple literal `.{a, b}` or a slice.
    /// - Returns: the children, in the build arena.
    pub fn toViews(children: anytype) []mod.View {
        const T = @TypeOf(children);
        const arena = mod.BuildScope.shared().allocator();
        // Accept either a tuple literal `.{a, b}` or a slice `[]const View`.
        if (T == []const mod.View or T == []mod.View) {
            const out = arena.alloc(mod.View, children.len) catch @panic("oom");
            @memcpy(out, children);
            return out;
        }
        const names = comptime std.meta.fieldNames(T);
        var out = arena.alloc(mod.View, names.len) catch @panic("oom");
        inline for (names, 0..) |name, index| out[index] = @field(children, name);
        return out;
    }

    /// Splices any `.group` children (from `ForEach`) into a flat child list,
    /// for composed containers (e.g. `List`) that flatten before laying out.
    ///
    /// - `views`: the children.
    /// - Returns: them flat (the same slice when nothing needed splicing).
    pub fn flattenGroups(views: []const mod.View) []const mod.View {
        // A child count alone cannot tell: an empty group and a group of two
        // add up to as many children as there are groups.
        var total: usize = 0;
        var grouped = false;
        for (views) |view| {
            if (view.kind == .group) {
                total += view.kind.group.len;
                grouped = true;
            } else total += 1;
        }
        if (!grouped) return views; // nothing to flatten
        var out = mod.BuildScope.shared().allocator().alloc(mod.View, total) catch @panic("oom");
        var index: usize = 0;
        for (views) |view| {
            if (view.kind == .group) {
                for (view.kind.group) |member| {
                    out[index] = member;
                    index += 1;
                }
            } else {
                out[index] = view;
                index += 1;
            }
        }
        return out;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "flattenGroups splices groups even when the child count stays the same" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    mod.BuildScope.shared().begin(arena.allocator());
    defer mod.BuildScope.shared().end();
    const two = [_]mod.View{ .{ .kind = .empty }, .{ .kind = .{ .text = .{ .string = "b" } } } };
    // ForEach(empty), ForEach(two): two children before and after.
    const views = [_]mod.View{ .{ .kind = .{ .group = &.{} } }, .{ .kind = .{ .group = &two } } };
    const flat = StackBuilder.flattenGroups(&views);
    try std.testing.expectEqual(@as(usize, 2), flat.len);
    try std.testing.expect(flat[0].kind == .empty);
    try std.testing.expect(flat[1].kind == .text);

    // No group: the same slice comes back.
    try std.testing.expectEqual(@as([*]const mod.View, &two), StackBuilder.flattenGroups(&two).ptr);
}
