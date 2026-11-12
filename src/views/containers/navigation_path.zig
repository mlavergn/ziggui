//! A navigation route stack, app-owned, that a per-frame body switches on.

const std = @import("std");
const log = std.log.scoped(.ziggui_navigation_path);

/// A navigation route stack for `NavigationStack`-style flows. Owned by the app
/// (like `TextFieldState`), so it survives across frames; the per-frame body
/// switches on `top()` to choose the screen. Routes are opaque integer tokens
/// the app interprets. Because the tree is rebuilt every frame, "navigation" is
/// just mutating this stack.
pub const NavigationPath = struct {
    const Self = @This();

    /// The pushed routes, the current one last.
    stack: std.ArrayList(i64) = .empty,

    /// Where `stack` grows.
    allocator: std.mem.Allocator,

    /// An empty stack, at the root.
    ///
    /// - `allocator`: where the routes are kept.
    /// - Returns: the stack.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Frees the routes.
    ///
    /// - `self`: the stack.
    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.allocator);
    }

    /// Pushes a route, making it the current one.
    ///
    /// - `self`: the stack.
    /// - `route`: the route.
    /// - Returns: nothing; propagates allocation failure.
    pub fn push(self: *Self, route: i64) std.mem.Allocator.Error!void {
        try self.stack.append(self.allocator, route);
    }

    /// Pops the current route; a no-op at the root.
    ///
    /// - `self`: the stack.
    pub fn pop(self: *Self) void {
        if (self.stack.items.len > 0) _ = self.stack.pop();
    }

    /// The current (top-most) route.
    ///
    /// - `self`: the stack.
    /// - Returns: the route, or null at the root.
    pub fn top(self: *const Self) ?i64 {
        const count = self.stack.items.len;
        return if (count == 0) null else self.stack.items[count - 1];
    }

    /// How many routes are pushed.
    ///
    /// - `self`: the stack.
    /// - Returns: the depth (0 at the root).
    pub fn depth(self: *const Self) usize {
        return self.stack.items.len;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "NavigationPath: push/pop/top/depth" {
    var navigation = NavigationPath.init(std.testing.allocator);
    defer navigation.deinit();
    try std.testing.expectEqual(@as(usize, 0), navigation.depth());
    try std.testing.expect(navigation.top() == null);
    try navigation.push(7);
    try navigation.push(3);
    try std.testing.expectEqual(@as(usize, 2), navigation.depth());
    try std.testing.expectEqual(@as(i64, 3), navigation.top().?);
    navigation.pop();
    try std.testing.expectEqual(@as(i64, 7), navigation.top().?);
    navigation.pop();
    navigation.pop(); // underflow is a no-op
    try std.testing.expectEqual(@as(usize, 0), navigation.depth());
    try std.testing.expect(navigation.top() == null);
}
