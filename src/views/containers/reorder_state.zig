//! What a list of `ReorderableRow`s drags: the row under way, how far it has
//! moved, the gap it would drop into, and the move a finished drag makes.

const std = @import("std");
const log = std.log.scoped(.ziggui_reorder_state);
const mod = @import("module.zig");

/// How far, in points, the pointer moves after a press before the row is
/// dragged, so a click's jitter never dims it.
const drag_threshold: f32 = 3;

/// A finished reorder: remove the item at `from`, then insert it at `to`.
pub const ReorderMove = struct {
    const Self = @This();

    /// The moved item's index before the move.
    from: usize,

    /// The moved item's index after it (removed at `from`, then inserted here).
    to: usize,

    /// Applies the move to `items` in place: the item at `from` ends at `to`,
    /// the items between shift by one.
    ///
    /// - `self`: the move.
    /// - `T`: the items' type.
    /// - `items`: the list the move was made on.
    pub fn apply(self: *const Self, comptime T: type, items: []T) void {
        if (self.from >= items.len or self.to >= items.len or self.from == self.to) return;
        if (self.from < self.to) {
            std.mem.rotate(T, items[self.from .. self.to + 1], 1);
        } else {
            const span = items[self.to .. self.from + 1];
            std.mem.rotate(T, span, span.len - 1);
        }
    }
};

/// The app-owned state of one reorderable list. A press on a row arms its
/// drag; once the pointer moves the row is dragged (`dragging`), and the
/// mouse-up records the move (`takeMove`). No allocator: `init` is all.
pub const ReorderState = struct {
    const Self = @This();

    /// The row a press armed, until the button comes up.
    pressed: ?usize = null,

    /// The row being dragged: the pressed one, once the pointer has moved.
    dragging: ?usize = null,

    /// How far the pointer has moved down (negative: up) since the press.
    offset: f32 = 0,

    /// The distance from one row's top to the next's, captured as the drag began.
    row_height: f32 = 0,

    /// How many rows the list has, captured as the drag began.
    count: usize = 0,

    /// The move the last finished drag made, until `takeMove` takes it.
    finished: ?ReorderMove = null,

    /// Makes the state of a list with no drag under way.
    ///
    /// - Returns: the state.
    pub fn init() Self {
        const self = Self{};
        return self;
    }

    /// Records the list's row count and row pitch as its rows are built; kept
    /// unchanged while a drag is under way. `ReorderableRow` calls it.
    ///
    /// - `self`: the state.
    /// - `count`: how many rows the list has.
    /// - `row_height`: the distance from one row's top to the next's.
    pub fn setList(self: *Self, count: usize, row_height: f32) void {
        if (self.pressed != null) return;
        self.count = count;
        self.row_height = row_height;
    }

    /// While a row is dragged, the gap it would drop into: 0 above the first
    /// row up to `count` below the last, from the offset in rows (rounded to
    /// the nearest, clamped to the list).
    ///
    /// - `self`: the state.
    /// - Returns: the gap; null when no row is dragged, it has not moved past
    ///   half a row, or the gap is either side of it (no move).
    pub fn dropIndex(self: *const Self) ?usize {
        const index = self.dragging orelse return null;
        if (self.row_height <= 0 or self.count == 0 or index >= self.count) return null;
        const count: f32 = @floatFromInt(self.count);
        const shift: isize = @intFromFloat(std.math.clamp(@round(self.offset / self.row_height), -count - 1, count + 1));
        const from: isize = @intCast(index);
        const gap = if (shift > 0) @min(from + 1 + shift, @as(isize, @intCast(self.count))) else @max(from + shift, 0);
        if (gap == from or gap == from + 1) return null;
        return @intCast(gap);
    }

    /// Whether row `index` is the one being dragged.
    ///
    /// - `self`: the state.
    /// - `index`: the row.
    /// - Returns: whether it is dragged.
    pub fn isDragging(self: *const Self, index: usize) bool {
        return self.dragging == index;
    }

    /// The move the last finished drag made, once: the app applies it to its
    /// items (`ReorderMove.apply`) as it builds the next frame.
    ///
    /// - `self`: the state.
    /// - Returns: the move; null when no drag ended since, or it ended where it began.
    pub fn takeMove(self: *Self) ?ReorderMove {
        const move = self.finished;
        self.finished = null;
        return move;
    }

    /// Drops the drag under way and any move not yet taken.
    ///
    /// - `self`: the state.
    pub fn cancel(self: *Self) void {
        self.pressed = null;
        self.dragging = null;
        self.offset = 0;
        self.finished = null;
    }

    /// The drag handler for row `index` of the list, for `View.onDrag`.
    ///
    /// - `self`: the state, which outlives the drag.
    /// - `index`: the row.
    /// - Returns: the handler.
    pub fn dragCallback(self: *Self, index: usize) mod.DragCallback {
        return .{ .context = self, .function = Self.moved, .begin = Self.began, .end = Self.ended, .tag = index };
    }

    /// A press armed row `index`'s drag.
    ///
    /// - `self`: the state.
    /// - `index`: the pressed row.
    fn press(self: *Self, index: usize) void {
        self.pressed = index;
        self.dragging = null;
        self.offset = 0;
    }

    /// The pointer moved `delta_y` down with the button held.
    ///
    /// - `self`: the state.
    /// - `delta_y`: the movement down since the last event.
    fn moveBy(self: *Self, delta_y: f32) void {
        const index = self.pressed orelse return;
        self.offset += delta_y;
        if (self.dragging == null and @abs(self.offset) >= drag_threshold) self.dragging = index;
    }

    /// The button came up: a dragged row's drop becomes the finished move.
    ///
    /// - `self`: the state.
    fn finish(self: *Self) void {
        if (self.dragging) |from| if (self.dropIndex()) |gap| {
            self.finished = .{ .from = from, .to = if (gap > from) gap - 1 else gap };
        };
        self.pressed = null;
        self.dragging = null;
        self.offset = 0;
    }

    /// `DragCallback.begin`: a press on row `tag`.
    ///
    /// - `context`: the state.
    /// - `tag`: the row.
    fn began(context: ?*anyopaque, tag: usize) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        self.press(tag);
    }

    /// `DragCallback.function`: the pointer moved.
    ///
    /// - `context`: the state.
    /// - `delta_x`: the movement across (unused: rows move only up and down).
    /// - `delta_y`: the movement down.
    fn moved(context: ?*anyopaque, delta_x: f32, delta_y: f32) void {
        _ = delta_x;
        const self: *Self = @ptrCast(@alignCast(context.?));
        self.moveBy(delta_y);
    }

    /// `DragCallback.end`: the button came up.
    ///
    /// - `context`: the state.
    fn ended(context: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        self.finish();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a reorder's drop index rounds to the nearest gap and clamps to the list" {
    var state = ReorderState.init();
    state.setList(5, 20);
    try std.testing.expectEqual(@as(?usize, null), state.dropIndex());
    state.press(1);
    // Under the threshold: pressed, not dragged.
    state.moveBy(2);
    try std.testing.expect(!state.isDragging(1));
    // Under half a row: dragged, but no gap yet.
    state.moveBy(7);
    try std.testing.expect(state.isDragging(1));
    try std.testing.expectEqual(@as(?usize, null), state.dropIndex());
    // Half a row down: past row 2, into gap 3.
    state.moveBy(1);
    try std.testing.expectEqual(@as(?usize, 3), state.dropIndex());
    // 1.4 rows down rounds to one.
    state.moveBy(18);
    try std.testing.expectEqual(@as(?usize, 3), state.dropIndex());
    // Far down clamps below the last row.
    state.moveBy(1000);
    try std.testing.expectEqual(@as(?usize, 5), state.dropIndex());
    // Far up clamps above the first row.
    state.moveBy(-2000);
    try std.testing.expectEqual(@as(?usize, 0), state.dropIndex());
    // The list's size is kept while the drag is under way.
    state.setList(2, 50);
    try std.testing.expectEqual(@as(usize, 5), state.count);
    state.cancel();
    try std.testing.expectEqual(@as(?usize, null), state.dropIndex());
}

test "a reorder's move is taken once; a drag back to its start makes none" {
    var state = ReorderState.init();
    state.setList(4, 20);
    // Row 0 dragged two rows down ends at index 2.
    state.press(0);
    state.moveBy(40);
    state.finish();
    try std.testing.expectEqual(ReorderMove{ .from = 0, .to = 2 }, state.takeMove().?);
    try std.testing.expectEqual(@as(?ReorderMove, null), state.takeMove());
    // Row 3 dragged up past row 2 ends at index 2.
    state.press(3);
    state.moveBy(-12);
    state.finish();
    try std.testing.expectEqual(ReorderMove{ .from = 3, .to = 2 }, state.takeMove().?);
    // There and back again: no move.
    state.press(1);
    state.moveBy(45);
    state.moveBy(-44);
    state.finish();
    try std.testing.expectEqual(@as(?ReorderMove, null), state.takeMove());
    // A press without a drag: no move.
    state.press(2);
    state.finish();
    try std.testing.expectEqual(@as(?ReorderMove, null), state.takeMove());
    // The last row dragged further down: no move.
    state.press(3);
    state.moveBy(100);
    state.finish();
    try std.testing.expectEqual(@as(?ReorderMove, null), state.takeMove());
}

test "a reorder move applies to a slice" {
    var items = [_]u8{ 'a', 'b', 'c', 'd' };
    (ReorderMove{ .from = 0, .to = 2 }).apply(u8, &items);
    try std.testing.expectEqualStrings("bcad", &items);
    (ReorderMove{ .from = 3, .to = 0 }).apply(u8, &items);
    try std.testing.expectEqualStrings("dbca", &items);
}
