//! Placing and moving marks on a picture: a segment's two clicks, and a marker
//! held under a drag.

const std = @import("std");
const log = std.log.scoped(.ziggui_annotation_state);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A segment two clicks made, in content units.
pub const AnnotationSegment = struct {
    const Self = @This();

    /// Where the first click landed.
    start: renderer.Point,
    /// Where the second click landed.
    end: renderer.Point,
};

/// The marks an app places on a picture as it is being marked up, owned by
/// the app (like `ZoomState`) so it survives across frames: a segment's first
/// click while the second is awaited (`click`, `cancel`, with a rubber band to
/// the pointer from `drawBand`), and the marker a press took hold of while a
/// drag moves it (`grab`, `drag`, `release`). Points are in content units (a
/// photo's pixels), mapped through the picture's `ZoomGeometry`. What a mark
/// means stays the app's: `click` hands back the finished segment, `grab` the
/// index of the marker in the list the app gave, `drag` how far to move it;
/// the app keeps the marks and draws them (`CanvasMarkers`). A second click
/// off the picture is clipped to its edge with `ZoomGeometry.clipToContent`.
pub const AnnotationState = struct {
    const Self = @This();

    /// A segment's first click while the second is awaited, in content units.
    pending: ?renderer.Point = null,
    /// The marker a press took hold of: its index in the list `grab` was given.
    grabbed: ?usize = null,

    /// A click toward a segment: the first is kept, the second finishes it.
    ///
    /// - `self`: the state.
    /// - `point`: the click, in content units.
    /// - Returns: the segment on the second click; null on the first.
    pub fn click(self: *Self, point: renderer.Point) ?AnnotationSegment {
        const start = self.pending orelse {
            self.pending = point;
            return null;
        };
        self.pending = null;
        return .{ .start = start, .end = point };
    }

    /// Drops a segment's first click (Esc, or a change of tool).
    ///
    /// - `self`: the state.
    pub fn cancel(self: *Self) void {
        self.pending = null;
    }

    /// Whether a segment's first click awaits its second.
    ///
    /// - `self`: the state.
    /// - Returns: true while one does.
    pub fn isPending(self: *const Self) bool {
        return self.pending != null;
    }

    /// The rubber band from a segment's first click to the pointer, while the
    /// second click is awaited.
    ///
    /// - `self`: the state.
    /// - `graphics`: what it draws with.
    /// - `geometry`: the picture's layout.
    /// - `pointer`: the pointer, in view points.
    /// - `width`: the band's stroke, in points.
    /// - `color`: its color.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawBand(self: *const Self, graphics: *mod.GraphicsContext, geometry: *const mod.ZoomGeometry, pointer: renderer.Point, width: f32, color: renderer.Color) std.mem.Allocator.Error!void {
        const start = self.pending orelse return;
        try graphics.line(geometry.at(start), pointer, width, color);
    }

    /// Takes hold of the marker nearest a press, within reach on screen.
    ///
    /// - `self`: the state.
    /// - `geometry`: the picture's layout, for its scale.
    /// - `markers`: the markers that may be taken, in content units.
    /// - `at`: the press, in content units.
    /// - `reach`: how near the press must be, in view points.
    /// - Returns: the marker's index in `markers`, now held; null when none is in reach.
    pub fn grab(self: *Self, geometry: *const mod.ZoomGeometry, markers: []const renderer.Point, at: renderer.Point, reach: f32) ?usize {
        if (!(geometry.scale > 0)) return null;
        self.grabbed = mod.CanvasMarkers.nearest(markers, at, reach / geometry.scale);
        return self.grabbed;
    }

    /// A drag's movement, for the marker held.
    ///
    /// - `self`: the state.
    /// - `geometry`: the picture's layout, for its scale.
    /// - `delta_x`: the movement across, in view points.
    /// - `delta_y`: the movement down, in view points.
    /// - Returns: how far to move the marker, in content units; null when none
    ///   is held (the drag is the app's: a pan, say).
    pub fn drag(self: *const Self, geometry: *const mod.ZoomGeometry, delta_x: f32, delta_y: f32) ?renderer.Point {
        if (self.grabbed == null or !(geometry.scale > 0)) return null;
        return .{ .x = delta_x / geometry.scale, .y = delta_y / geometry.scale };
    }

    /// Lets go of the marker held.
    ///
    /// - `self`: the state.
    /// - Returns: the index of the marker let go, or null when none was held.
    pub fn release(self: *Self) ?usize {
        const held = self.grabbed;
        self.grabbed = null;
        return held;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(AnnotationState);
    // Nothing here does I/O to trace.
    _ = log;
}

test "annotation state makes a segment of two clicks, and cancels the first" {
    var state = AnnotationState{};
    try std.testing.expectEqual(null, state.click(.{ .x = 1, .y = 2 }));
    try std.testing.expect(state.isPending());
    const segment = state.click(.{ .x = 3, .y = 4 }).?;
    try std.testing.expectEqual(@as(f32, 1), segment.start.x);
    try std.testing.expectEqual(@as(f32, 4), segment.end.y);
    try std.testing.expect(!state.isPending());
    _ = state.click(.{ .x = 5, .y = 5 });
    state.cancel();
    try std.testing.expect(!state.isPending());
}

test "annotation state holds the marker in reach on screen and moves it in content units" {
    var zoom = mod.ZoomState{};
    // 1000 × 1000 content in a 500 pt frame: half a point a unit.
    const geometry = zoom.layout(.{ .x = 0, .y = 0, .width = 500, .height = 500 }, 1000, 1000);
    const markers = [_]renderer.Point{ .{ .x = 100, .y = 100 }, .{ .x = 400, .y = 400 } };
    var state = AnnotationState{};
    // 12 pt reaches 24 units here: 20 units off takes it, 30 does not.
    try std.testing.expectEqual(@as(?usize, 1), state.grab(&geometry, &markers, .{ .x = 420, .y = 400 }, 12));
    const moved = state.drag(&geometry, 5, -2).?;
    try std.testing.expectApproxEqAbs(@as(f32, 10), moved.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -4), moved.y, 1e-4);
    try std.testing.expectEqual(@as(?usize, 1), state.release());
    try std.testing.expectEqual(null, state.drag(&geometry, 5, 5));
    try std.testing.expectEqual(null, state.grab(&geometry, &markers, .{ .x = 130, .y = 100 }, 12));
}
