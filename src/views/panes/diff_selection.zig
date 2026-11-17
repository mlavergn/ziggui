//! A diff's selected lines (`SelectableDiffView`): a press picks a line, a
//! drag or a shift-press extends the run, and ⌘C copies the lines' text.

const std = @import("std");
const log = std.log.scoped(.ziggui_diff_selection);
const mod = @import("module.zig");

/// The lines selected in a `SelectableDiffView`, kept by the app beside the
/// diff's `ScrollState`.
///
/// A press on a row selects it (a shift-press extends from the line pressed
/// before), and a drag extends it row by row. The selection is the live
/// `TextSelection` while it lasts: ⌘C (Ctrl+C) copies its lines' text, each
/// line once (a wrapped line's rows joined back together), without the gutter
/// or the `+`/`-` marks; a press anywhere else ends it, as it ends a text
/// selection. A selection over other rows (another file, a re-wrap) is
/// dropped when the view first draws them.
pub const DiffSelection = struct {
    const Self = @This();

    /// The row the selection started at.
    anchor: usize = 0,
    /// The row it reaches now.
    head: usize = 0,
    /// The row the drag started on, which `head` follows from.
    pressed: usize = 0,
    /// The drag's movement down since the press, in points.
    moved_y: f32 = 0,
    /// The rows the selection is over: their address and length, set as the view draws them.
    lines: []const mod.DiffLine = &.{},

    /// Reports whether this selection is the live one (what ⌘C copies).
    ///
    /// - `self`: the selection.
    /// - Returns: true while it is.
    pub fn active(self: *const Self) bool {
        const current = mod.TextSelection.shared().current orelse return false;
        return current.key == self.key();
    }

    /// Reports whether a row is selected.
    ///
    /// - `self`: the selection.
    /// - `row`: the row, an index into the diff's lines.
    /// - Returns: true when it is in the live selection.
    pub fn contains(self: *const Self, row: usize) bool {
        if (!self.active()) return false;
        return row >= @min(self.anchor, self.head) and row <= @max(self.anchor, self.head);
    }

    /// The selected lines' text: each line once, a line wrapped over several
    /// rows joined back, lines ended by `\n`, no gutter or marks.
    ///
    /// - `self`: the selection.
    /// - `allocator`: allocator for the text.
    /// - Returns: the text (empty with no selection); propagates allocation failure.
    pub fn text(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        if (self.lines.len == 0) return out.toOwnedSlice(allocator);
        const first = @min(@min(self.anchor, self.head), self.lines.len - 1);
        const last = @min(@max(self.anchor, self.head), self.lines.len - 1);
        for (self.lines[first .. last + 1], first..) |line, row| {
            // A continued row is the line above, wrapped: no break between them.
            if (row > first and !line.continued) try out.append(allocator, '\n');
            try out.appendSlice(allocator, line.text);
        }
        try out.append(allocator, '\n');
        return out.toOwnedSlice(allocator);
    }

    /// Ends the selection: nothing is selected or copied.
    ///
    /// - `self`: the selection.
    pub fn clear(self: *Self) void {
        mod.TextSelection.shared().release(self.key());
    }

    /// Notes the rows the view draws this frame: a selection over other rows
    /// (another diff, the same one wrapped anew) ends.
    ///
    /// - `self`: the selection.
    /// - `lines`: the rows drawn.
    pub fn track(self: *Self, lines: []const mod.DiffLine) void {
        if (self.lines.ptr == lines.ptr and self.lines.len == lines.len) return;
        self.lines = lines;
        mod.TextSelection.shared().release(self.key());
    }

    /// The drag handler a row hands the pointer: a press there selects it,
    /// a drag extends the selection.
    ///
    /// - `self`: the selection; must outlive the frame (the app keeps it).
    /// - `row`: the row.
    /// - Returns: the handler.
    pub fn dragCallback(self: *Self, row: usize) mod.DragCallback {
        return .{ .context = self, .function = Self.dragged, .begin = Self.began, .end = Self.ended, .tag = row };
    }

    /// The identity the live `TextSelection` knows this selection by.
    ///
    /// - `self`: the selection.
    /// - Returns: the key, from its address.
    fn key(self: *const Self) u64 {
        return @as(u64, @intFromPtr(self)) ^ 0xd1ff_5e1e_c7ed_0000;
    }

    /// Makes the selected lines what ⌘C copies.
    ///
    /// - `self`: the selection.
    fn hold(self: *Self) void {
        const selected = self.text(std.heap.page_allocator) catch |err| {
            log.warn("cannot keep the selected lines [{t}]", .{err});
            return;
        };
        defer std.heap.page_allocator.free(selected);
        mod.TextSelection.shared().hold(self.key(), selected);
    }

    /// A press armed a row's drag: selects the row, or extends to it on a shift-press.
    ///
    /// - `context`: the selection.
    /// - `row`: the row pressed (the drag's tag).
    fn began(context: ?*anyopaque, row: usize) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        if (row >= self.lines.len) return;
        // A shift-press extends the selection this press ended; any other press starts one.
        const was_live = mod.TextSelection.shared().ended_by_press == self.key();
        if (!(mod.PointerInput.shared().clickShift() and was_live)) self.anchor = row;
        self.head = row;
        self.pressed = row;
        self.moved_y = 0;
        self.hold();
    }

    /// The pointer moved with the button held: the selection reaches the row it is over.
    ///
    /// - `context`: the selection.
    /// - `delta_x`: the movement across; unused.
    /// - `delta_y`: the movement down, in points.
    fn dragged(context: ?*anyopaque, delta_x: f32, delta_y: f32) void {
        _ = delta_x;
        const self: *Self = @ptrCast(@alignCast(context.?));
        if (self.lines.len == 0) return;
        self.moved_y += delta_y;
        // Rows from the one pressed, counted from its middle.
        const rows = @floor((self.moved_y + mod.diff_row_height / 2) / mod.diff_row_height);
        const at = @as(f32, @floatFromInt(self.pressed)) + rows;
        self.head = @intFromFloat(std.math.clamp(at, 0, @as(f32, @floatFromInt(self.lines.len - 1))));
    }

    /// The button came up: the lines selected become what ⌘C copies.
    ///
    /// - `context`: the selection.
    fn ended(context: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        if (self.lines.len == 0) return;
        self.hold();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "diff selection selects a line, extends by drag, and copies whole lines without marks" {
    const lines = [_]mod.DiffLine{
        .{ .kind = .hunkHeader, .text = "@@ -1,2 +1,2 @@" },
        .{ .kind = .removed, .text = "old line", .old = 1 },
        .{ .kind = .added, .text = "new li", .new = 1 },
        .{ .kind = .added, .text = "ne, wrapped", .new = 1, .continued = true },
        .{ .kind = .context, .text = "same", .old = 2, .new = 2 },
    };
    var selection: DiffSelection = .{};
    selection.track(&lines);
    try std.testing.expect(!selection.active());
    const callback = selection.dragCallback(1);
    callback.begin.?(callback.context, callback.tag);
    try std.testing.expect(selection.contains(1) and !selection.contains(2));
    try std.testing.expectEqualStrings("old line\n", mod.TextSelection.shared().selectedText().?);
    // Two rows down: the wrapped line's two rows.
    callback.function(callback.context, 0, 2 * mod.diff_row_height);
    callback.end.?(callback.context);
    try std.testing.expect(selection.contains(3));
    try std.testing.expectEqualStrings("old line\nnew line, wrapped\n", mod.TextSelection.shared().selectedText().?);
    // Another diff ends it.
    selection.track(lines[0..2]);
    try std.testing.expect(!selection.active());
    try std.testing.expect(mod.TextSelection.shared().selectedText() == null);
}
