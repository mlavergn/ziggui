//! Stack space distribution — the pure numeric core of HStack/VStack layout.
//!
//! Given an available length along the main axis, inter-item spacing, and each
//! item's `min`/`max` main length, `distribute` assigns a final length to every
//! item. It follows SwiftUI's algorithm: hand out the remaining space in equal
//! shares, least-flexible item first, so rigid items take exactly what they need
//! and flexible ones (e.g. `Spacer`, `.frame(maxWidth: .infinity)`) absorb the
//! leftover. No allocation beyond the caller's output buffer, which makes the
//! trickiest part of layout trivially testable.

const std = @import("std");
const log = std.log.scoped(.ziggui_space_distributor);
const mod = @import("module.zig");

/// Shares a stack's main-axis length among its children.
pub const SpaceDistributor = struct {
    const Self = @This();

    /// The stack's length along its main axis.
    available: f32,
    /// The gap between neighbouring items.
    spacing: f32,

    /// Fill `lengths` (len == items.len) with each item's assigned main length.
    ///
    /// - `self`: the distributor.
    /// - `items`: each item's bounds.
    /// - `lengths`: receives each item's length.
    pub fn distribute(self: *const Self, items: []const mod.FlexItem, lengths: []f32) void {
        std.debug.assert(lengths.len == items.len);
        const count = items.len;
        if (count == 0) return;

        const total_spacing = self.spacing * @as(f32, @floatFromInt(count - 1));
        var remaining = self.available - total_spacing;

        // Visit indices ordered by ascending flexibility.
        var scratch: mod.Scratch(usize) = .{};
        defer scratch.deinit();
        const order = scratch.get(count);
        for (0..count) |index| order[index] = index;
        Self.sortByFlexibility(order, items);

        var items_left: f32 = @floatFromInt(count);
        for (order) |index| {
            const share = remaining / items_left;
            const length = std.math.clamp(share, items[index].min, items[index].max);
            lengths[index] = length;
            remaining -= length;
            items_left -= 1;
        }
    }

    /// Sort `order` (indices into `items`) by ascending flexibility.
    ///
    /// - `order`: the indices, sorted in place.
    /// - `items`: the items the indices name.
    fn sortByFlexibility(order: []usize, items: []const mod.FlexItem) void {
        // Simple insertion sort — stable and allocation-free; the count is a
        // stack's children. Keeps original order among equally-flexible items.
        var index: usize = 1;
        while (index < order.len) : (index += 1) {
            const key = order[index];
            const key_flexibility = items[key].flexibility();
            var probe: isize = @as(isize, @intCast(index)) - 1;
            while (probe >= 0 and items[order[@intCast(probe)]].flexibility() > key_flexibility) : (probe -= 1) {
                order[@intCast(probe + 1)] = order[@intCast(probe)];
            }
            order[@intCast(probe + 1)] = key;
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "distribute: rigid items take exactly their size" {
    const items = [_]mod.FlexItem{ .{ .min = 50, .max = 50 }, .{ .min = 30, .max = 30 } };
    var lengths: [2]f32 = undefined;
    (mod.SpaceDistributor{ .available = 200, .spacing = 0 }).distribute(&items, &lengths);
    try std.testing.expectEqual(@as(f32, 50), lengths[0]);
    try std.testing.expectEqual(@as(f32, 30), lengths[1]);
}

test "distribute: spacing reduces available before allocation" {
    const items = [_]mod.FlexItem{ .{ .min = 50, .max = 50 }, .{ .min = 50, .max = 50 } };
    var lengths: [2]f32 = undefined;
    (mod.SpaceDistributor{ .available = 200, .spacing = 10 }).distribute(&items, &lengths);
    try std.testing.expectEqual(@as(f32, 50), lengths[0]);
    try std.testing.expectEqual(@as(f32, 50), lengths[1]);
}

test "distribute: a flexible spacer absorbs the leftover" {
    // two rigid 50s and one fully-flexible spacer in 200 -> spacer gets 100.
    const big = 1_000_000.0;
    const items = [_]mod.FlexItem{
        .{ .min = 50, .max = 50 },
        .{ .min = 0, .max = big },
        .{ .min = 50, .max = 50 },
    };
    var lengths: [3]f32 = undefined;
    (mod.SpaceDistributor{ .available = 200, .spacing = 0 }).distribute(&items, &lengths);
    try std.testing.expectEqual(@as(f32, 50), lengths[0]);
    try std.testing.expectEqual(@as(f32, 100), lengths[1]);
    try std.testing.expectEqual(@as(f32, 50), lengths[2]);
}

test "distribute: two equal flexible items split remaining evenly" {
    const big = 1_000_000.0;
    const items = [_]mod.FlexItem{ .{ .min = 0, .max = big }, .{ .min = 0, .max = big } };
    var lengths: [2]f32 = undefined;
    (mod.SpaceDistributor{ .available = 200, .spacing = 0 }).distribute(&items, &lengths);
    try std.testing.expectEqual(@as(f32, 100), lengths[0]);
    try std.testing.expectEqual(@as(f32, 100), lengths[1]);
}

test "distribute: least-flexible-first frees space for a stretchy item" {
    // available 100; one rigid 80, one flexible [0,inf]. Flexible gets 20.
    const big = 1_000_000.0;
    const items = [_]mod.FlexItem{ .{ .min = 0, .max = big }, .{ .min = 80, .max = 80 } };
    var lengths: [2]f32 = undefined;
    (mod.SpaceDistributor{ .available = 100, .spacing = 0 }).distribute(&items, &lengths);
    try std.testing.expectEqual(@as(f32, 20), lengths[0]);
    try std.testing.expectEqual(@as(f32, 80), lengths[1]);
}

test "distribute: single item gets all available" {
    const items = [_]mod.FlexItem{.{ .min = 0, .max = 1000 }};
    var lengths: [1]f32 = undefined;
    (mod.SpaceDistributor{ .available = 123, .spacing = 10 }).distribute(&items, &lengths);
    try std.testing.expectEqual(@as(f32, 123), lengths[0]);
}
