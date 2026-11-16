//! The column widths a user dragged in a `TableResizable`, kept by the app so
//! a resize survives across frames.

const std = @import("std");
const log = std.log.scoped(.ziggui_table_column_customization);
const mod = @import("module.zig");

/// The column widths a user dragged in a `TableResizable`, owned by the app
/// (like `SplitState`) so a resize survives across frames; after SwiftUI's
/// `TableColumnCustomization`, widths only.
///
/// Dragging a column's trailing edge moves width between it and the column
/// after it, as a split's divider does: the table's width stays, and the
/// other columns stay where they are. A column never dragged keeps its
/// `TableColumn.width`, or its share of the room left when that is null.
pub const TableColumnCustomization = struct {
    const Self = @This();

    /// The most columns whose widths are kept; edges past it do not drag.
    pub const max_columns = 32;

    /// Each column's width as the user last dragged it, in points; negative
    /// for a column never dragged.
    widths: [max_columns]f32 = @splat(-1),

    /// Each column's width at the last layout, which a drag starts from.
    laid_out: [max_columns]f32 = @splat(0),

    /// Each column's smallest width at the last layout.
    minimums: [max_columns]f32 = @splat(0),

    /// How many columns the last layout had.
    count: usize = 0,

    /// The column whose trailing edge the pointer holds.
    dragging: usize = 0,

    /// How far the pointer has moved since the press, unclamped, so past a
    /// minimum the edge waits for the pointer to come back.
    drag_offset: f32 = 0,

    /// The held column's and the next one's widths when the press came.
    drag_start: [2]f32 = .{ 0, 0 },

    /// Forgets every dragged width: each column goes back to its own.
    ///
    /// - `self`: the customization.
    pub fn reset(self: *Self) void {
        self.widths = @splat(-1);
    }

    /// Lays `columns` out across `room` points: a dragged width, else the
    /// column's own, else an equal share of what those leave (in whole
    /// points, the last sharing column taking the rest), none under its
    /// `min_width`. Once every sharing column has been dragged, those columns
    /// (the ones whose `TableColumn.width` is null) take the room gained or
    /// lost in proportion to their widths, so the table still fits; a table
    /// of fixed columns only lets its last one grow into room left over.
    /// Records the widths for the next drag.
    ///
    /// - `self`: the customization.
    /// - `columns`: the table's columns.
    /// - `room`: the width the columns share.
    /// - `widths`: receives each column's width; as long as `columns`.
    pub fn resolve(self: *Self, columns: []const mod.TableColumn, room: f32, widths: []f32) void {
        var fixed: f32 = 0;
        var sharing: usize = 0;
        for (columns, 0..) |column, index| {
            if (self.chosen(index, column)) |width| fixed += width else sharing += 1;
        }
        // Whole points, so the edges fall on pixels; the last sharing column
        // takes what rounding leaves.
        const left = @max(0, room - fixed);
        const share = if (sharing > 0) @floor(left / @as(f32, @floatFromInt(sharing))) else 0;
        var used: f32 = 0;
        var shared: usize = 0;
        for (columns, widths, 0..) |column, *width, index| {
            var want = self.chosen(index, column);
            if (want == null) {
                shared += 1;
                want = if (shared == sharing) left - share * @as(f32, @floatFromInt(sharing - 1)) else share;
            }
            width.* = @max(column.min_width, want.?);
            used += width.*;
        }
        if (sharing == 0 and columns.len > 0) Self.fit(columns, room, used, widths);
        self.count = columns.len;
        for (columns, widths, 0..) |column, width, index| {
            if (index >= max_columns) break;
            self.laid_out[index] = width;
            self.minimums[index] = column.min_width;
        }
    }

    /// The handler for a press on `column`'s trailing edge: holds the edge
    /// and arms `PointerInput` to feed it the pointer's movement until the
    /// button is up. Nothing changes until the pointer moves.
    ///
    /// - `self`: the customization; must outlive the drag.
    /// - `column`: the column whose trailing edge was pressed.
    pub fn pressEdge(self: *Self, column: usize) void {
        if (column + 1 >= max_columns) return;
        // A dragged width `fit` stretched is kept as drawn, so the drag moves
        // what the user sees.
        for (self.widths[0..@min(self.count, max_columns)], self.laid_out[0..@min(self.count, max_columns)]) |*width, drawn| {
            if (width.* >= 0) width.* = drawn;
        }
        self.dragging = column;
        self.drag_offset = 0;
        self.drag_start = .{ self.laid_out[column], self.laid_out[column + 1] };
        mod.PointerInput.shared().armDrag(.{ .context = self, .function = Self.onDrag });
    }

    /// Moves the held edge by a drag's movement across: the held column
    /// grows by what the next one gives, neither under its minimum.
    ///
    /// - `self`: the customization.
    /// - `delta_x`: the drag's movement across.
    pub fn drag(self: *Self, delta_x: f32) void {
        const column = self.dragging;
        self.drag_offset += delta_x;
        const total = self.drag_start[0] + self.drag_start[1];
        const least = self.minimums[column];
        const most = total - self.minimums[column + 1];
        // Too narrow for both minimums: the edge stays put.
        if (most < least) return;
        const first = std.math.clamp(self.drag_start[0] + self.drag_offset, least, most);
        self.widths[column] = first;
        self.widths[column + 1] = total - first;
    }

    /// Fits columns that all have a width to `room`: the room gained or lost
    /// goes to the columns made to share it (`TableColumn.width` null), in
    /// proportion to their widths, in whole points (the last of them taking
    /// the rest), none under its minimum; with none such, the last column
    /// grows into room left over and never shrinks.
    ///
    /// - `columns`: the table's columns.
    /// - `room`: the width the columns share.
    /// - `used`: the width `widths` add up to.
    /// - `widths`: each column's width, changed in place.
    fn fit(columns: []const mod.TableColumn, room: f32, used: f32, widths: []f32) void {
        var elastic: f32 = 0;
        var last_elastic: ?usize = null;
        for (columns, widths, 0..) |column, width, index| {
            if (column.width == null) {
                elastic += width;
                last_elastic = index;
            }
        }
        const last = last_elastic orelse {
            if (used < room) widths[columns.len - 1] += room - used;
            return;
        };
        if (elastic <= 0) return;
        const target = @max(0, elastic + room - used);
        var assigned: f32 = 0;
        for (columns, widths, 0..) |column, *width, index| {
            if (column.width != null) continue;
            const scaled = if (index == last) target - assigned else @floor(width.* * target / elastic);
            width.* = @max(column.min_width, scaled);
            assigned += width.*;
        }
    }

    /// The width `column` keeps whatever the room: the one dragged, else its own.
    ///
    /// - `self`: the customization.
    /// - `index`: the column's index.
    /// - `column`: the column.
    /// - Returns: the width, or null for a column that shares the room.
    fn chosen(self: *const Self, index: usize, column: mod.TableColumn) ?f32 {
        if (index < max_columns and self.widths[index] >= 0) return self.widths[index];
        return column.width;
    }

    /// The drag handler `pressEdge` arms.
    ///
    /// - `pointer`: the `TableColumnCustomization`.
    /// - `delta_x`: the drag's movement across.
    /// - `delta_y`: the drag's movement down, unused.
    fn onDrag(pointer: ?*anyopaque, delta_x: f32, delta_y: f32) void {
        _ = delta_y;
        const self: *Self = @ptrCast(@alignCast(pointer.?));
        self.drag(delta_x);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "columns share the room left by fixed ones, none under its minimum" {
    var customization: TableColumnCustomization = .{};
    const columns = [_]mod.TableColumn{ .{ .title = "Name" }, .{ .title = "Role" }, .{ .title = "Age", .width = 60 } };
    var widths: [3]f32 = undefined;
    customization.resolve(&columns, 300, &widths);
    try std.testing.expectEqualSlices(f32, &.{ 120, 120, 60 }, &widths);
    // Too little room: the sharing columns stop at their minimum.
    customization.resolve(&columns, 100, &widths);
    try std.testing.expectEqualSlices(f32, &.{ 40, 40, 60 }, &widths);
}

test "a dragged edge moves width between its column and the next, within their minimums" {
    var customization: TableColumnCustomization = .{};
    const columns = [_]mod.TableColumn{ .{ .title = "Name" }, .{ .title = "Role" }, .{ .title = "Age", .width = 60 } };
    var widths: [3]f32 = undefined;
    customization.resolve(&columns, 300, &widths);
    customization.dragging = 0;
    customization.drag_start = .{ 120, 120 };
    // A press alone changes nothing.
    try std.testing.expectEqual(@as(f32, -1), customization.widths[0]);
    customization.drag(30);
    customization.resolve(&columns, 300, &widths);
    try std.testing.expectEqualSlices(f32, &.{ 150, 90, 60 }, &widths);
    // Past the next column's minimum the edge stops, and waits for the pointer.
    customization.drag(500);
    try std.testing.expectEqual(@as(f32, 200), customization.widths[0]);
    // Back 480: the pointer is 50 past where it pressed, and so is the edge.
    customization.drag(-480);
    try std.testing.expectEqual(@as(f32, 170), customization.widths[0]);
    // Reset, each column has its own width again.
    customization.reset();
    customization.resolve(&columns, 300, &widths);
    try std.testing.expectEqualSlices(f32, &.{ 120, 120, 60 }, &widths);
}

test "once every sharing column is dragged, they still take the room the table gains or loses" {
    var customization: TableColumnCustomization = .{};
    const columns = [_]mod.TableColumn{ .{ .title = "Name" }, .{ .title = "Role" }, .{ .title = "Age", .width = 60 } };
    var widths: [3]f32 = undefined;
    customization.resolve(&columns, 300, &widths);
    customization.dragging = 0;
    customization.drag_start = .{ 120, 120 };
    customization.drag(30);
    // Wider: Name and Role grow in proportion (150:90), Age keeps its width.
    customization.resolve(&columns, 400, &widths);
    try std.testing.expectEqualSlices(f32, &.{ 212, 128, 60 }, &widths);
    // Narrower: they shrink to fit, never under their minimum.
    customization.resolve(&columns, 200, &widths);
    try std.testing.expectEqualSlices(f32, &.{ 87, 53, 60 }, &widths);
    customization.resolve(&columns, 100, &widths);
    try std.testing.expectEqualSlices(f32, &.{ 40, 40, 60 }, &widths);
    // A press keeps the widths as drawn, so the next drag starts from them.
    customization.resolve(&columns, 400, &widths);
    customization.pressEdge(0);
    defer mod.PointerInput.shared().endDrag();
    try std.testing.expectEqual(@as(f32, 212), customization.widths[0]);
    try std.testing.expectEqual(@as(f32, 128), customization.widths[1]);
}

test "with no column sharing the room, the last one takes what is left" {
    var customization: TableColumnCustomization = .{};
    const columns = [_]mod.TableColumn{ .{ .title = "A", .width = 50 }, .{ .title = "B", .width = 50 } };
    var widths: [2]f32 = undefined;
    customization.resolve(&columns, 300, &widths);
    try std.testing.expectEqualSlices(f32, &.{ 50, 250 }, &widths);
}

test "shares are whole points, the last sharing column taking the rest" {
    var customization: TableColumnCustomization = .{};
    const columns = [_]mod.TableColumn{ .{ .title = "A" }, .{ .title = "B" }, .{ .title = "C" } };
    var widths: [3]f32 = undefined;
    customization.resolve(&columns, 301, &widths);
    try std.testing.expectEqualSlices(f32, &.{ 100, 100, 101 }, &widths);
}
