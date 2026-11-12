//! Where a split view's divider sits, kept by the app so a drag survives across frames.

const std = @import("std");
const log = std.log.scoped(.ziggui_split_state);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Where a split view's divider sits, owned by the app (like `ScrollState`)
/// so a drag survives across frames.
///
/// One state can drive two splits of the same length (two rows sharing a
/// column divider): dragging either moves both.
pub const SplitState = struct {
    const Self = @This();

    /// The first pane's length along the split, in points, as the user last
    /// dragged it; negative until the first drag, while `initial_size` or
    /// `initial_ratio` places the divider. Layout clamps it without writing it
    /// back, so a window shrunk and grown again gets the pane back.
    size: f32 = -1,

    /// The first pane's share of the length when `initial_size` is null.
    initial_ratio: f32 = 0.5,

    /// The first pane's starting length in points (wins over the ratio).
    initial_size: ?f32 = null,

    /// The smallest the first pane may be dragged to.
    min_first: f32 = 80,

    /// The smallest the second pane may be dragged to.
    min_second: f32 = 80,

    /// The split's length at the last layout, for dragging.
    total: f32 = 0,

    /// The split's axis at the last build, for dragging.
    axis: renderer.Axis = .horizontal,

    /// Where the pointer has dragged the divider since the press, unclamped,
    /// so past a minimum the divider waits for the pointer to come back.
    drag_at: f32 = 0,

    /// The first pane's length in a split `total` long, clamped to the
    /// minimums and to the split.
    ///
    /// - `self`: the state.
    /// - `total`: the split's length.
    /// - Returns: the first pane's length.
    pub fn resolved(self: *const Self, total: f32) f32 {
        const want = if (self.size >= 0) self.size else self.initial_size orelse total * self.initial_ratio;
        return self.clamped(want, total);
    }

    /// Starts a drag at the divider's current place, as a press on it does.
    ///
    /// - `self`: the state.
    pub fn beginDrag(self: *Self) void {
        self.drag_at = self.resolved(self.total);
    }

    /// Moves the divider by a drag's movement since the last event, clamped
    /// to the minimums. The unclamped place is kept, so the divider and the
    /// pointer stay together when a drag goes past a minimum and comes back.
    ///
    /// - `self`: the state.
    /// - `delta_x`: the drag's horizontal movement.
    /// - `delta_y`: the drag's vertical movement.
    pub fn drag(self: *Self, delta_x: f32, delta_y: f32) void {
        self.drag_at += if (self.axis == .horizontal) delta_x else delta_y;
        self.size = self.clamped(self.drag_at, self.total);
    }

    /// The divider's tap handler: a press starts a drag (`beginDrag`) and
    /// arms `PointerInput` to feed it the pointer's movement until the button is up.
    ///
    /// - `self`: the state; must outlive the drag.
    /// - Returns: the callback, for the divider's `onTap`.
    pub fn pressCallback(self: *Self) mod.Callback {
        return .{ .context = self, .function = Self.onPress };
    }

    /// `want` clamped to the minimums, the first pane's winning when the split
    /// is too short for both, and never past the split itself.
    ///
    /// - `self`: the state.
    /// - `want`: the first pane's wanted length.
    /// - `total`: the split's length.
    /// - Returns: the first pane's length.
    fn clamped(self: *const Self, want: f32, total: f32) f32 {
        const upper_bound = @max(self.min_first, total - self.min_second);
        return @min(std.math.clamp(want, @min(self.min_first, upper_bound), upper_bound), @max(0, total));
    }

    /// The `pressCallback` thunk: starts a drag and arms it.
    ///
    /// - `pointer`: the `SplitState`.
    fn onPress(pointer: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(pointer.?));
        self.beginDrag();
        mod.PointerInput.shared().armDrag(.{ .context = self, .function = Self.onDrag });
    }

    /// The drag handler `onPress` arms.
    ///
    /// - `pointer`: the `SplitState`.
    /// - `delta_x`: the drag's horizontal movement.
    /// - `delta_y`: the drag's vertical movement.
    fn onDrag(pointer: ?*anyopaque, delta_x: f32, delta_y: f32) void {
        const self: *Self = @ptrCast(@alignCast(pointer.?));
        self.drag(delta_x, delta_y);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a split clamps to its length without forgetting the dragged size" {
    var split: SplitState = .{ .size = 50, .min_first = 20, .min_second = 20 };
    // Shrunk, the pane is clamped for layout; grown again, it comes back.
    try std.testing.expectEqual(@as(f32, 40), split.resolved(60));
    try std.testing.expectEqual(@as(f32, 50), split.resolved(100));
    // Too short for both minimums, the first pane still fits the split.
    try std.testing.expectEqual(@as(f32, 10), split.resolved(10));
    try std.testing.expectEqual(@as(f32, 0), split.resolved(0));
}

test "a drag past a minimum waits for the pointer to come back" {
    var split: SplitState = .{ .initial_size = 40, .min_first = 20, .min_second = 20, .total = 100 };
    split.beginDrag();
    split.drag(500, 0);
    try std.testing.expectEqual(@as(f32, 80), split.size);
    split.drag(-10, 0);
    try std.testing.expectEqual(@as(f32, 80), split.size);
    split.drag(-480, 0);
    try std.testing.expectEqual(@as(f32, 50), split.size);
}
