//! A list row the user drags up or down to reorder its list.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_reorderable_row);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The opacity of the row being dragged.
const dragged_opacity: f32 = 0.5;

/// The thickness, in points, of the line marking the drop gap.
const drop_line_height: f32 = 2;

/// Row `index` of a reorderable list of `count` rows: `content` (a
/// `SelectableRow`, say), draggable up and down. `content` keeps its own
/// modifiers: a press taps it as before (`onTap`, `onSecondaryTap`) and, held
/// and moved, drags the row. The dragged row draws at half opacity, and a
/// line in `accent_mark` across the row marks the gap it would drop into (on
/// row `dropIndex`'s top edge, or the last row's bottom edge for `count`).
/// The app applies the finished move from `ReorderState.takeMove`.
///
/// - `content`: the row's view.
/// - `state`: the list's reorder state, owned by the app.
/// - `index`: the row's index in the list.
/// - `count`: how many rows the list has.
/// - `row_height`: the distance from one row's top to the next's (the row's
///   height plus the list's spacing).
/// - Returns: the row.
pub fn ReorderableRow(content: mod.View, state: *mod.ReorderState, index: usize, count: usize, row_height: f32) mod.View {
    state.setList(count, row_height);
    const gap = state.dropIndex();
    const edge: ?renderer.Alignment = if (gap == index)
        .topLeading
    else if (gap == count and index + 1 == count)
        .bottomLeading
    else
        null;
    const row = if (edge) |alignment| mod.StackBuilder.make(.depth, 0, alignment, .{
        content,
        mod.Rectangle(mod.BuildScope.shared().tokens().accent_mark).frameHeight(drop_line_height).frameMaxWidth(),
    }) else mod.StackBuilder.make(.depth, 0, .leading, .{content});
    return row
        .opacity(if (state.isDragging(index)) dragged_opacity else 1)
        .onDrag(state.dragCallback(index));
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

/// The rows of the tests: three `SelectableRow`s that count their taps.
const TestList = struct {
    const Self = @This();

    /// The list's reorder state.
    state: mod.ReorderState = .init(),

    /// The row last tapped.
    selection: renderer.State(i64),

    /// Right-clicks on any row.
    secondary: u32 = 0,

    /// Counts a right-click.
    ///
    /// - `self`: the list.
    fn rightClicked(self: *Self) void {
        self.secondary += 1;
    }

    /// The list's rows, 28pt tall and stacked without spacing.
    ///
    /// - `self`: the list.
    /// - Returns: the list.
    fn body(self: *Self) mod.View {
        const rows = mod.BuildScope.shared().allocator().alloc(mod.View, 3) catch @panic("oom");
        for (rows, 0..) |*row, index| {
            const tapped = mod.Callback.select(self.selection.binding(), @intCast(index));
            const content = mod.SelectableRow(mod.Text("row"), false, true, tapped).onSecondaryTap(mod.Callback.init(Self, self, Self.rightClicked));
            row.* = ReorderableRow(content, &self.state, index, rows.len, 28);
        }
        return mod.StackBuilder.fromSlice(.vertical, 0, .leading, rows).frameMaxWidth();
    }
};

test "a reorderable row taps through to its content, and a drag reorders" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var list = TestList{ .selection = renderer.State(i64).init(std.testing.allocator, -1) };
    defer list.selection.deinit();
    const input = mod.PointerInput.shared();
    defer input.endDrag();

    canvas.begin(renderer.MacosTheme.light);
    var view = list.body();
    canvas.end();
    var frame = try canvas.render(view, 200, 84);
    frame.deinit();

    // A press without movement taps the row and makes no move.
    try std.testing.expect(canvas.tap(.{ .x = 50, .y = 42 }));
    try std.testing.expectEqual(@as(i64, 1), list.selection.get());
    input.endDrag();
    try std.testing.expectEqual(@as(?mod.ReorderMove, null), list.state.takeMove());
    // The content's right-click still reaches it.
    try std.testing.expect(input.secondaryTap(canvas.hits.items, .{ .x = 50, .y = 42 }));
    try std.testing.expectEqual(@as(u32, 1), list.secondary);

    // Press row 0 and drag it down past row 1: the row dims, the line marks gap 2.
    try std.testing.expect(canvas.tap(.{ .x = 50, .y = 14 }));
    try std.testing.expectEqual(@as(i64, 0), list.selection.get());
    input.drag(canvas.hits.items, .{ .x = 50, .y = 30 });
    try std.testing.expect(list.state.isDragging(0));
    try std.testing.expectEqual(@as(?usize, 2), list.state.dropIndex());
    canvas.begin(renderer.MacosTheme.light);
    view = list.body();
    canvas.end();
    try std.testing.expectEqual(dragged_opacity, view.kind.stack.children[0].modifiers.opacity);
    frame = try canvas.render(view, 200, 84);
    defer frame.deinit();
    // The accent line sits on row 2's top edge.
    const line = frame.at(150, 57);
    try std.testing.expect(line.b > line.r + 0.3);
    input.endDrag();
    try std.testing.expectEqual(mod.ReorderMove{ .from = 0, .to = 1 }, list.state.takeMove().?);
    try std.testing.expectEqual(@as(?mod.ReorderMove, null), list.state.takeMove());
}
