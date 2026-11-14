//! An axis-aligned rectangle in logical coordinates.

const std = @import("std");
const log = std.log.scoped(.ziggui_rect);
const mod = @import("module.zig");

/// An axis-aligned rectangle stored as origin + extent. Min edges are
/// inclusive, max edges exclusive (half-open), so adjacent rects tile without
/// overlap and `contains` is unambiguous.
pub const Rect = struct {
    const Self = @This();

    /// The left edge.
    x: f32 = 0,
    /// The top edge.
    y: f32 = 0,
    /// The horizontal extent.
    width: f32 = 0,
    /// The vertical extent.
    height: f32 = 0,

    /// The empty rect at the origin.
    pub const zero = Self{};

    /// The rect with its top-left corner at `top_left` and the given extent.
    ///
    /// - `top_left`: the origin.
    /// - `extent`: the size.
    /// - Returns: the rect.
    pub fn fromOriginSize(top_left: mod.Point, extent: mod.Size) Self {
        return .{ .x = top_left.x, .y = top_left.y, .width = extent.width, .height = extent.height };
    }

    /// The top-left corner.
    ///
    /// - `self`: the rect.
    /// - Returns: the origin.
    pub fn origin(self: *const Self) mod.Point {
        return .{ .x = self.x, .y = self.y };
    }

    /// The extent.
    ///
    /// - `self`: the rect.
    /// - Returns: the width and height.
    pub fn size(self: *const Self) mod.Size {
        return .{ .width = self.width, .height = self.height };
    }

    /// The left edge.
    ///
    /// - `self`: the rect.
    /// - Returns: the smallest x.
    pub fn minX(self: *const Self) f32 {
        return self.x;
    }

    /// The top edge.
    ///
    /// - `self`: the rect.
    /// - Returns: the smallest y.
    pub fn minY(self: *const Self) f32 {
        return self.y;
    }

    /// The right edge (exclusive).
    ///
    /// - `self`: the rect.
    /// - Returns: x plus width.
    pub fn maxX(self: *const Self) f32 {
        return self.x + self.width;
    }

    /// The bottom edge (exclusive).
    ///
    /// - `self`: the rect.
    /// - Returns: y plus height.
    pub fn maxY(self: *const Self) f32 {
        return self.y + self.height;
    }

    /// The horizontal center.
    ///
    /// - `self`: the rect.
    /// - Returns: the middle x.
    pub fn midX(self: *const Self) f32 {
        return self.x + self.width / 2;
    }

    /// The vertical center.
    ///
    /// - `self`: the rect.
    /// - Returns: the middle y.
    pub fn midY(self: *const Self) f32 {
        return self.y + self.height / 2;
    }

    /// The center point.
    ///
    /// - `self`: the rect.
    /// - Returns: the middle of both axes.
    pub fn center(self: *const Self) mod.Point {
        return .{ .x = self.midX(), .y = self.midY() };
    }

    /// Whether `point` lies inside (min edges inclusive, max edges exclusive).
    ///
    /// - `self`: the rect.
    /// - `point`: the point tested.
    /// - Returns: true when the point is inside.
    pub fn contains(self: *const Self, point: mod.Point) bool {
        return point.x >= self.minX() and point.x < self.maxX() and
            point.y >= self.minY() and point.y < self.maxY();
    }

    /// Whether `other` lies wholly inside, give or take `slack` on each edge
    /// (layout's float rounding).
    ///
    /// - `self`: the outer rect.
    /// - `other`: the rect tested.
    /// - `slack`: how far past an edge still counts as inside.
    /// - Returns: true when it is inside.
    pub fn containsRect(self: *const Self, other: Self, slack: f32) bool {
        return other.minX() >= self.minX() - slack and other.maxX() <= self.maxX() + slack and
            other.minY() >= self.minY() - slack and other.maxY() <= self.maxY() + slack;
    }

    /// Whether two rects overlap.
    ///
    /// - `self`: the first rect.
    /// - `other`: the second rect.
    /// - Returns: true when they share any area.
    pub fn intersects(self: *const Self, other: Self) bool {
        return self.minX() < other.maxX() and other.minX() < self.maxX() and
            self.minY() < other.maxY() and other.minY() < self.maxY();
    }

    /// The overlapping region, or null if the rects are disjoint.
    ///
    /// - `self`: the first rect.
    /// - `other`: the second rect.
    /// - Returns: the overlap, or null.
    pub fn intersection(self: *const Self, other: Self) ?Self {
        const left = @max(self.minX(), other.minX());
        const top = @max(self.minY(), other.minY());
        const right = @min(self.maxX(), other.maxX());
        const bottom = @min(self.maxY(), other.maxY());
        if (right <= left or bottom <= top) return null;
        return .{ .x = left, .y = top, .width = right - left, .height = bottom - top };
    }

    /// The smallest rect containing both inputs.
    ///
    /// - `self`: the first rect.
    /// - `other`: the second rect.
    /// - Returns: the bounding rect.
    pub fn unionRect(self: *const Self, other: Self) Self {
        const left = @min(self.minX(), other.minX());
        const top = @min(self.minY(), other.minY());
        const right = @max(self.maxX(), other.maxX());
        const bottom = @max(self.maxY(), other.maxY());
        return .{ .x = left, .y = top, .width = right - left, .height = bottom - top };
    }

    /// Shrink by per-side insets (top/leading/bottom/trailing).
    ///
    /// - `self`: the rect.
    /// - `insets`: how far each side moves in.
    /// - Returns: the inset rect.
    pub fn inset(self: *const Self, insets: mod.EdgeInsets) Self {
        return .{
            .x = self.x + insets.leading,
            .y = self.y + insets.top,
            .width = self.width - insets.horizontal(),
            .height = self.height - insets.vertical(),
        };
    }

    /// Shrink uniformly by `delta_x` on the horizontal sides and `delta_y` on
    /// the vertical.
    ///
    /// - `self`: the rect.
    /// - `delta_x`: how far the left and right sides move in.
    /// - `delta_y`: how far the top and bottom sides move in.
    /// - Returns: the inset rect.
    pub fn insetBy(self: *const Self, delta_x: f32, delta_y: f32) Self {
        return .{
            .x = self.x + delta_x,
            .y = self.y + delta_y,
            .width = self.width - 2 * delta_x,
            .height = self.height - 2 * delta_y,
        };
    }

    /// The rect moved by `delta_x`, `delta_y`.
    ///
    /// - `self`: the rect.
    /// - `delta_x`: the horizontal move.
    /// - `delta_y`: the vertical move.
    /// - Returns: the moved rect.
    pub fn offsetBy(self: *const Self, delta_x: f32, delta_y: f32) Self {
        return .{ .x = self.x + delta_x, .y = self.y + delta_y, .width = self.width, .height = self.height };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "Rect: edges, center, contains" {
    const rect = mod.Rect{ .x = 10, .y = 20, .width = 100, .height = 40 };
    try std.testing.expectEqual(@as(f32, 10), rect.minX());
    try std.testing.expectEqual(@as(f32, 110), rect.maxX());
    try std.testing.expectEqual(@as(f32, 20), rect.minY());
    try std.testing.expectEqual(@as(f32, 60), rect.maxY());
    try std.testing.expectEqual(@as(f32, 60), rect.midX());
    try std.testing.expectEqual(@as(f32, 40), rect.midY());
    try std.testing.expectEqual(mod.Point{ .x = 60, .y = 40 }, rect.center());
    try std.testing.expect(rect.contains(.{ .x = 60, .y = 40 }));
    try std.testing.expect(!rect.contains(.{ .x = 0, .y = 0 }));
    // Boundary: min edge inclusive, max edge exclusive (half-open).
    try std.testing.expect(rect.contains(.{ .x = 10, .y = 20 }));
    try std.testing.expect(!rect.contains(.{ .x = 110, .y = 20 }));
}

test "Rect: origin/size round trip" {
    const rect = mod.Rect.fromOriginSize(.{ .x = 5, .y = 6 }, .{ .width = 7, .height = 8 });
    try std.testing.expectEqual(mod.Point{ .x = 5, .y = 6 }, rect.origin());
    try std.testing.expectEqual(mod.Size{ .width = 7, .height = 8 }, rect.size());
}

test "Rect: intersection" {
    const first = mod.Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const second = mod.Rect{ .x = 50, .y = 50, .width = 100, .height = 100 };
    const overlap = first.intersection(second).?;
    try std.testing.expectEqual(mod.Rect{ .x = 50, .y = 50, .width = 50, .height = 50 }, overlap);
    // disjoint rects -> null
    const far = mod.Rect{ .x = 200, .y = 200, .width = 10, .height = 10 };
    try std.testing.expect(first.intersection(far) == null);
    try std.testing.expect(first.intersects(second));
    try std.testing.expect(!first.intersects(far));
}

test "Rect: union" {
    const first = mod.Rect{ .x = 0, .y = 0, .width = 50, .height = 50 };
    const second = mod.Rect{ .x = 100, .y = 100, .width = 50, .height = 50 };
    try std.testing.expectEqual(
        mod.Rect{ .x = 0, .y = 0, .width = 150, .height = 150 },
        first.unionRect(second),
    );
}

test "Rect: inset by EdgeInsets shrinks from each side" {
    const rect = mod.Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const insets = mod.EdgeInsets{ .top = 10, .leading = 20, .bottom = 30, .trailing = 40 };
    try std.testing.expectEqual(
        mod.Rect{ .x = 20, .y = 10, .width = 40, .height = 60 },
        rect.inset(insets),
    );
}

test "Rect: insetBy uniform dx/dy" {
    const rect = mod.Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    try std.testing.expectEqual(
        mod.Rect{ .x = 10, .y = 10, .width = 80, .height = 80 },
        rect.insetBy(10, 10),
    );
}

test "Rect: offsetBy translates" {
    const rect = mod.Rect{ .x = 5, .y = 5, .width = 10, .height = 10 };
    try std.testing.expectEqual(
        mod.Rect{ .x = 8, .y = 1, .width = 10, .height = 10 },
        rect.offsetBy(3, -4),
    );
}
