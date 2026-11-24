//! A zoomable picture's app-owned zoom, pan and last layout.

const std = @import("std");
const log = std.log.scoped(.ziggui_zoom_state);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Where a zoomed picture was laid out: its view's frame, and how its content
/// maps into it. Content coordinates are the picture's own (pixels, for a photo).
pub const ZoomGeometry = struct {
    const Self = @This();

    /// The view's frame.
    frame: renderer.Rect = .{},
    /// The part of `frame` on screen as it was drawn: the frame cut by the
    /// scroll viewport it sits in (`Context.visible`), so a picture half
    /// scrolled under the page's edge takes no gesture over the hidden half.
    visible: renderer.Rect = .{},
    /// The content's top-left, in points.
    origin: renderer.Point = .{ .x = 0, .y = 0 },
    /// Points per content unit.
    scale: f32 = 1,
    /// The content's width, in its own units.
    content_width: f32 = 0,
    /// The content's height, in its own units.
    content_height: f32 = 0,

    /// Where a content point is drawn.
    ///
    /// - `self`: the geometry.
    /// - `content`: the point, in content units.
    /// - Returns: the point, in view points.
    pub fn at(self: *const Self, content: renderer.Point) renderer.Point {
        return .{ .x = self.origin.x + content.x * self.scale, .y = self.origin.y + content.y * self.scale };
    }

    /// The content point under a view point.
    ///
    /// - `self`: the geometry.
    /// - `point`: the point, in view points.
    /// - Returns: the point, in content units, or null off the content.
    pub fn contentAt(self: *const Self, point: renderer.Point) ?renderer.Point {
        if (!(self.scale > 0)) return null;
        const content = renderer.Point{ .x = (point.x - self.origin.x) / self.scale, .y = (point.y - self.origin.y) / self.scale };
        if (!(content.x >= 0 and content.y >= 0 and content.x < self.content_width and content.y < self.content_height)) return null;
        return content;
    }

    /// Where a segment from a content point toward a view point leaves the
    /// content: a second click off a picture ends a line at its edge. The
    /// point stays half a unit inside, so for a photo it is still a pixel of it.
    ///
    /// - `self`: the geometry.
    /// - `inside`: the segment's start, in content units, on the content.
    /// - `toward`: where it heads, in view points, on the content or off it.
    /// - Returns: the last point of the segment on the content, in content
    ///   units (`toward`'s own when it is on the content); null when `inside`
    ///   is off the content or the geometry has no scale.
    pub fn clipToContent(self: *const Self, inside: renderer.Point, toward: renderer.Point) ?renderer.Point {
        if (!(self.scale > 0)) return null;
        if (!(inside.x >= 0 and inside.y >= 0 and inside.x < self.content_width and inside.y < self.content_height)) return null;
        const delta_x = (toward.x - self.origin.x) / self.scale - inside.x;
        const delta_y = (toward.y - self.origin.y) / self.scale - inside.y;
        var reach: f32 = 1;
        // Half a unit in from each side, so the point stays on the content.
        if (delta_x > 0) reach = @min(reach, (self.content_width - 0.5 - inside.x) / delta_x) else if (delta_x < 0) reach = @min(reach, (0.5 - inside.x) / delta_x);
        if (delta_y > 0) reach = @min(reach, (self.content_height - 0.5 - inside.y) / delta_y) else if (delta_y < 0) reach = @min(reach, (0.5 - inside.y) / delta_y);
        reach = @max(0, reach);
        return .{ .x = inside.x + delta_x * reach, .y = inside.y + delta_y * reach };
    }

    /// The content's rectangle, in view points: where the picture is drawn.
    ///
    /// - `self`: the geometry.
    /// - Returns: the rectangle, which may run past the frame when zoomed.
    pub fn contentRect(self: *const Self) renderer.Rect {
        return .{ .x = self.origin.x, .y = self.origin.y, .width = self.content_width * self.scale, .height = self.content_height * self.scale };
    }
};

/// The zoom and pan of a `ZoomableImage`, owned by the app (like `ScrollState`)
/// so it survives across frames and can be driven by the event loop: a pinch or
/// ⌘-scroll zooms about the pointer (`pinch`, `wheel`), a scroll or a drag pans
/// (`wheel`, `panDrag`), and the chip the view draws while zoomed fits it again
/// (`chipContains`, `fit`). A zoom of 1 fits the content to the frame,
/// centered; `geometry` is written back by the view each frame, and kept
/// current by every zoom and pan in between, so several events before the
/// next frame each act on where the content is.
///
/// Only the visible part of the frame, as the last frame of the main window
/// drew it, takes input. The view cannot tell whether a sheet, alert or
/// popover is presented over it (overlays draw after it), so the app passes
/// no wheel turns or pinches while one is up, as the gallery's
/// `Gallery.pictureZoom` does for its modals.
pub const ZoomState = struct {
    const Self = @This();

    /// Points a wheel line pans.
    pub const points_per_line: f32 = 28;
    /// How hard a zooming wheel line zooms: each line scales by `exp(this)`.
    pub const zoom_per_line: f32 = 0.1;

    /// The zoom; 1 fits the content to the frame.
    zoom: f32 = 1,
    /// The pan from the centered fit, in points.
    offset: renderer.Point = .{ .x = 0, .y = 0 },
    /// The least zoom.
    min_zoom: f32 = 0.25,
    /// The most zoom.
    max_zoom: f32 = 64,
    /// Whether a wheel turn's up and down pans the other way: the content moves
    /// down for a turn away from the user, rather than up as a scroll view's does.
    invert_scroll_y: bool = false,
    /// Whether a wheel turn's sideways pans the other way: the content moves left
    /// for a turn to the right, rather than right.
    invert_scroll_x: bool = false,
    /// The last layout, written by the view each frame.
    geometry: ZoomGeometry = .{},
    /// Where the view drew its zoom chip, while zoomed or panned.
    chip: ?renderer.Rect = null,
    /// The frame `layout` last ran in, in the window that drew it (the main
    /// window or the popover window): a view scrolled out of sight, or on a
    /// page no longer shown, is not laid out, and its old `geometry` must not
    /// take the pointer. Only that window's frames count, so the other
    /// window's change nothing (`BuildScope.isLatest`).
    laid_out_in: ?mod.FrameStamp = null,

    /// Lays the content out in a frame at the current zoom and pan, and keeps
    /// the result as `geometry`.
    ///
    /// - `self`: the state.
    /// - `frame`: the view's frame.
    /// - `content_width`: the content's width, in its own units.
    /// - `content_height`: the content's height, in its own units.
    /// - Returns: the geometry.
    pub fn layout(self: *Self, frame: renderer.Rect, content_width: f32, content_height: f32) ZoomGeometry {
        self.laid_out_in = mod.BuildScope.shared().stamp();
        self.geometry = .{ .frame = frame, .visible = frame, .content_width = content_width, .content_height = content_height };
        self.place();
        return self.geometry;
    }

    /// Cuts the laid-out frame to the part on screen, so the hidden part takes
    /// no gesture. `ZoomableImage` calls it with its paint's `Context.visible`.
    ///
    /// - `self`: the state.
    /// - `visible`: the on-screen part of the scroll viewport the view sits
    ///   in, or null when all of it is on screen.
    pub fn clipVisible(self: *Self, visible: ?renderer.Rect) void {
        const area = visible orelse return;
        const frame = self.geometry.frame;
        self.geometry.visible = frame.intersection(area) orelse .{ .x = frame.x, .y = frame.y, .width = 0, .height = 0 };
    }

    /// Zooms about the frame's center.
    ///
    /// - `self`: the state.
    /// - `factor`: how much; above 1 zooms in.
    pub fn zoomBy(self: *Self, factor: f32) void {
        if (!(factor > 0)) return;
        const next = std.math.clamp(self.zoom * factor, self.min_zoom, self.max_zoom);
        const applied = next / self.zoom;
        self.zoom = next;
        self.offset.x *= applied;
        self.offset.y *= applied;
        self.place();
    }

    /// Zooms about a point, keeping the content under it in place (a pinch, or
    /// ⌘-scroll, under the pointer). Before the first layout it zooms about the
    /// center.
    ///
    /// - `self`: the state.
    /// - `point`: the point, in view points.
    /// - `factor`: how much; above 1 zooms in.
    pub fn zoomAt(self: *Self, point: renderer.Point, factor: f32) void {
        const geometry = self.geometry;
        if (!(geometry.scale > 0) or geometry.content_width <= 0 or geometry.content_height <= 0) return self.zoomBy(factor);
        if (!(factor > 0)) return;
        const next = std.math.clamp(self.zoom * factor, self.min_zoom, self.max_zoom);
        const scale = Self.fitScale(geometry.frame, geometry.content_width, geometry.content_height) * next;
        // The content under `point` stays there: solve the new origin, then the offset.
        const content_x = (point.x - geometry.origin.x) / geometry.scale;
        const content_y = (point.y - geometry.origin.y) / geometry.scale;
        const centered = Self.centeredOrigin(geometry.frame, geometry.content_width, geometry.content_height, scale);
        self.offset.x = point.x - content_x * scale - centered.x;
        self.offset.y = point.y - content_y * scale - centered.y;
        self.zoom = next;
        self.place();
    }

    /// Pans.
    ///
    /// - `self`: the state.
    /// - `delta_x`: across, in points.
    /// - `delta_y`: down, in points.
    pub fn panBy(self: *Self, delta_x: f32, delta_y: f32) void {
        self.offset.x += delta_x;
        self.offset.y += delta_y;
        self.place();
    }

    /// Fits the content to the frame again.
    ///
    /// - `self`: the state.
    pub fn fit(self: *Self) void {
        self.zoom = 1;
        self.offset = .{ .x = 0, .y = 0 };
        self.place();
    }

    /// Whether the content is fitted, neither zoomed nor panned.
    ///
    /// - `self`: the state.
    /// - Returns: true when it is.
    pub fn isFit(self: *const Self) bool {
        return self.zoom == 1 and self.offset.x == 0 and self.offset.y == 0;
    }

    /// Whether a point is over the visible part of the view, as the last
    /// frame drew it.
    ///
    /// - `self`: the state.
    /// - `point`: the point, in view points.
    /// - Returns: true when it is; false when the last frame did not draw the
    ///   view (scrolled away, or another page shown) or the point is on a part
    ///   scrolled out of sight.
    pub fn contains(self: *const Self, point: renderer.Point) bool {
        if (!self.drawnLastFrame()) return false;
        return self.geometry.visible.contains(point);
    }

    /// Whether a point is on the zoom chip the view drew in the last frame.
    ///
    /// - `self`: the state.
    /// - `point`: the point, in view points.
    /// - Returns: true when it is; a click there should `fit`. False when the
    ///   last frame did not draw the view.
    pub fn chipContains(self: *const Self, point: renderer.Point) bool {
        if (!self.drawnLastFrame()) return false;
        const chip = self.chip orelse return false;
        return chip.contains(point);
    }

    /// A wheel turn over the view: zooms about the pointer when `zooming` (⌘ or
    /// Ctrl held, for a mouse wheel), pans otherwise (a two-finger scroll),
    /// moving the content as a scroll view moves its content for the same
    /// deltas (`PointerInput.scrollBoth`), or the other way on an axis the app
    /// inverts (`invert_scroll_y`, `invert_scroll_x`).
    ///
    /// - `self`: the state.
    /// - `point`: the pointer, in view points.
    /// - `delta_x`: sideways lines, positive to the right.
    /// - `delta_y`: lines, positive away from the user.
    /// - `zooming`: whether the turn zooms.
    /// - Returns: true when the view took it (the pointer is over it).
    pub fn wheel(self: *Self, point: renderer.Point, delta_x: f32, delta_y: f32, zooming: bool) bool {
        if (!self.contains(point)) return false;
        if (zooming) {
            self.zoomAt(point, @exp(delta_y * zoom_per_line));
        } else {
            // As a scroll view: its offset grows by `delta_y` (the content
            // moves up) and its sideways offset by `-delta_x` (the content
            // moves right); either axis the other way when inverted.
            const sideways: f32 = if (self.invert_scroll_x) -1 else 1;
            const upward: f32 = if (self.invert_scroll_y) 1 else -1;
            self.panBy(sideways * delta_x * points_per_line, upward * delta_y * points_per_line);
        }
        return true;
    }

    /// A trackpad pinch over the view: zooms about the pointer.
    ///
    /// - `self`: the state.
    /// - `point`: the pointer, in view points.
    /// - `scale`: the pinch's change since its last update; above 1 zooms in.
    /// - Returns: true when the view took it (the pointer is over it).
    pub fn pinch(self: *Self, point: renderer.Point, scale: f32) bool {
        if (!self.contains(point)) return false;
        self.zoomAt(point, scale);
        return true;
    }

    /// Pans by a drag: a `DragCallback.function` whose context is the state.
    ///
    /// - `context`: the state.
    /// - `delta_x`: the movement across, in points.
    /// - `delta_y`: the movement down, in points.
    pub fn panDrag(context: ?*anyopaque, delta_x: f32, delta_y: f32) void {
        const self: *Self = @ptrCast(@alignCast(context orelse return));
        self.panBy(delta_x, delta_y);
    }

    /// Whether the last frame of the window that drew the view laid it out.
    ///
    /// - `self`: the state.
    /// - Returns: true when it did.
    fn drawnLastFrame(self: *const Self) bool {
        const frame = self.laid_out_in orelse return false;
        return mod.BuildScope.shared().isLatest(frame);
    }

    /// Brings `geometry`'s scale and origin up to the current zoom and pan, in
    /// the frame it was last laid out in, so another zoom or pan before the
    /// next layout starts from where the content now is. Before a layout
    /// (no content) it leaves the geometry alone.
    ///
    /// - `self`: the state.
    fn place(self: *Self) void {
        const geometry = &self.geometry;
        if (!(geometry.content_width > 0 and geometry.content_height > 0)) return;
        geometry.scale = Self.fitScale(geometry.frame, geometry.content_width, geometry.content_height) * self.zoom;
        const centered = Self.centeredOrigin(geometry.frame, geometry.content_width, geometry.content_height, geometry.scale);
        geometry.origin = .{ .x = centered.x + self.offset.x, .y = centered.y + self.offset.y };
    }

    /// The scale that fits content to a frame: a zoom of 1.
    ///
    /// - `frame`: the frame.
    /// - `content_width`: the content's width, in its own units.
    /// - `content_height`: the content's height, in its own units.
    /// - Returns: points per content unit; 1 for empty content.
    fn fitScale(frame: renderer.Rect, content_width: f32, content_height: f32) f32 {
        if (!(content_width > 0 and content_height > 0)) return 1;
        return @min(frame.width / content_width, frame.height / content_height);
    }

    /// Where content drawn at a scale has its top-left when centered in a
    /// frame, before any pan.
    ///
    /// - `frame`: the frame.
    /// - `content_width`: the content's width, in its own units.
    /// - `content_height`: the content's height, in its own units.
    /// - `scale`: points per content unit.
    /// - Returns: the top-left, in view points.
    fn centeredOrigin(frame: renderer.Rect, content_width: f32, content_height: f32, scale: f32) renderer.Point {
        return .{
            .x = frame.x + (frame.width - content_width * scale) / 2,
            .y = frame.y + (frame.height - content_height * scale) / 2,
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(ZoomState);
    std.testing.refAllDecls(ZoomGeometry);
    // Nothing here does I/O to trace.
    _ = log;
}

test "zoom state fits, centers and maps both ways" {
    var state = ZoomState{};
    const geometry = state.layout(.{ .x = 10, .y = 20, .width = 400, .height = 200 }, 1000, 1000);
    // A square in a wide frame: fitted to the height, centered across.
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), geometry.scale, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 110), geometry.origin.x, 1e-4);
    const point = geometry.at(.{ .x = 500, .y = 500 });
    try std.testing.expectApproxEqAbs(@as(f32, 210), point.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 120), point.y, 1e-4);
    const back = geometry.contentAt(point).?;
    try std.testing.expectApproxEqAbs(@as(f32, 500), back.x, 1e-3);
    try std.testing.expectEqual(null, geometry.contentAt(.{ .x = 15, .y = 30 }));
    try std.testing.expect(state.isFit());
}

test "zoom geometry clips a segment to the content's edge" {
    var state = ZoomState{};
    // 100 × 50 content fitted 1:1 at the frame's origin.
    const geometry = state.layout(.{ .x = 0, .y = 0, .width = 100, .height = 50 }, 100, 50);
    const inside = renderer.Point{ .x = 50, .y = 25 };
    // Toward a point on the content: that point.
    const on = geometry.clipToContent(inside, .{ .x = 60, .y = 30 }).?;
    try std.testing.expectApproxEqAbs(@as(f32, 60), on.x, 1e-4);
    // Straight down past the foot: half a unit above the bottom edge, same column.
    const below = geometry.clipToContent(inside, .{ .x = 50, .y = 200 }).?;
    try std.testing.expectApproxEqAbs(@as(f32, 49.5), below.y, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 50), below.x, 1e-4);
    // Off to the upper left: along the segment, inside both edges.
    const corner = geometry.clipToContent(inside, .{ .x = -50, .y = -25 }).?;
    try std.testing.expect(corner.x >= 0.5 - 1e-4 and corner.y >= 0.5 - 1e-4);
    try std.testing.expectApproxEqAbs(corner.x / 2, corner.y, 0.3);
    // A start off the content clips nothing.
    try std.testing.expectEqual(null, geometry.clipToContent(.{ .x = -1, .y = 0 }, .{ .x = 10, .y = 10 }));
}

test "zoom state zooms about the pointer, keeping the content under it" {
    var state = ZoomState{};
    const frame = renderer.Rect{ .x = 0, .y = 0, .width = 400, .height = 300 };
    const before = state.layout(frame, 800, 600);
    const pointer = renderer.Point{ .x = 100, .y = 80 };
    const under = before.contentAt(pointer).?;
    state.zoomAt(pointer, 3);
    const after = state.layout(frame, 800, 600);
    const moved = after.at(under);
    try std.testing.expectApproxEqAbs(pointer.x, moved.x, 1e-3);
    try std.testing.expectApproxEqAbs(pointer.y, moved.y, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 3), state.zoom, 1e-6);
    try std.testing.expect(!state.isFit());

    // Clamped to its range, and fitted again.
    state.zoomAt(pointer, 1000);
    try std.testing.expectEqual(state.max_zoom, state.zoom);
    state.fit();
    try std.testing.expect(state.isFit());
}

test "zoom state takes wheel and pinch input only over the view" {
    var state = ZoomState{};
    _ = state.layout(.{ .x = 0, .y = 0, .width = 100, .height = 100 }, 50, 50);
    try std.testing.expect(!state.wheel(.{ .x = 200, .y = 10 }, 0, 1, false));
    // Panned as a scroll view scrolls for the same deltas: right with x,
    // up with y.
    try std.testing.expect(state.wheel(.{ .x = 50, .y = 50 }, 1, 2, false));
    try std.testing.expectApproxEqAbs(ZoomState.points_per_line, state.offset.x, 1e-4);
    try std.testing.expectApproxEqAbs(-ZoomState.points_per_line * 2, state.offset.y, 1e-4);
    // Inverted, each axis pans the other way; zooming is not affected.
    state.fit();
    state.invert_scroll_y = true;
    state.invert_scroll_x = true;
    try std.testing.expect(state.wheel(.{ .x = 50, .y = 50 }, 1, 2, false));
    try std.testing.expectApproxEqAbs(-ZoomState.points_per_line, state.offset.x, 1e-4);
    try std.testing.expectApproxEqAbs(ZoomState.points_per_line * 2, state.offset.y, 1e-4);
    state.invert_scroll_y = false;
    state.invert_scroll_x = false;
    state.fit();
    try std.testing.expect(state.wheel(.{ .x = 50, .y = 50 }, 0, 1, true));
    try std.testing.expectApproxEqAbs(@exp(ZoomState.zoom_per_line), state.zoom, 1e-5);
    try std.testing.expect(state.pinch(.{ .x = 50, .y = 50 }, 2));
    ZoomState.panDrag(&state, 5, -5);
    try std.testing.expect(!state.isFit());
    try std.testing.expect(!state.chipContains(.{ .x = 50, .y = 50 }));

    // A frame that did not lay it out (scrolled away, another page shown): its
    // old frame takes nothing.
    const scope = mod.BuildScope.shared();
    const saved = scope.frame_number;
    defer scope.frame_number = saved;
    scope.frame_number +%= 1;
    try std.testing.expect(!state.pinch(.{ .x = 50, .y = 50 }, 2));
    try std.testing.expect(!state.wheel(.{ .x = 50, .y = 50 }, 0, 1, true));
}

test "zoom state keeps the content under the pointer through several events in one frame" {
    var state = ZoomState{};
    const frame = renderer.Rect{ .x = 0, .y = 0, .width = 400, .height = 300 };
    const pointer = renderer.Point{ .x = 100, .y = 80 };

    // Two zooms before the next layout.
    const under = state.layout(frame, 800, 600).contentAt(pointer).?;
    state.zoomAt(pointer, 2);
    state.zoomAt(pointer, 2);
    try std.testing.expectApproxEqAbs(@as(f32, 4), state.zoom, 1e-6);
    const twice = state.geometry.at(under);
    try std.testing.expectApproxEqAbs(pointer.x, twice.x, 1e-3);
    try std.testing.expectApproxEqAbs(pointer.y, twice.y, 1e-3);
    const laid_out = state.layout(frame, 800, 600).at(under);
    try std.testing.expectApproxEqAbs(pointer.x, laid_out.x, 1e-3);
    try std.testing.expectApproxEqAbs(pointer.y, laid_out.y, 1e-3);

    // A pan, then a zoom, before the next layout.
    state.fit();
    _ = state.layout(frame, 800, 600);
    state.panBy(30, -20);
    const panned = state.geometry.contentAt(pointer).?;
    state.zoomAt(pointer, 3);
    const after = state.layout(frame, 800, 600).at(panned);
    try std.testing.expectApproxEqAbs(pointer.x, after.x, 1e-3);
    try std.testing.expectApproxEqAbs(pointer.y, after.y, 1e-3);
}

test "zoom state takes input only over the visible part, and its chip only while drawn" {
    var state = ZoomState{};
    _ = state.layout(.{ .x = 0, .y = 100, .width = 200, .height = 200 }, 100, 100);
    // Half of it scrolled under the viewport's bottom edge.
    state.clipVisible(.{ .x = 0, .y = 0, .width = 400, .height = 200 });
    try std.testing.expect(state.contains(.{ .x = 50, .y = 150 }));
    try std.testing.expect(!state.contains(.{ .x = 50, .y = 250 }));
    try std.testing.expect(!state.pinch(.{ .x = 50, .y = 250 }, 2));
    // Wholly out of sight.
    state.clipVisible(.{ .x = 0, .y = 0, .width = 400, .height = 50 });
    try std.testing.expect(!state.contains(.{ .x = 50, .y = 150 }));

    // The chip counts only in the frame that drew it.
    _ = state.layout(.{ .x = 0, .y = 0, .width = 200, .height = 200 }, 100, 100);
    state.chip = .{ .x = 60, .y = 160, .width = 80, .height = 24 };
    try std.testing.expect(state.chipContains(.{ .x = 100, .y = 170 }));
    const scope = mod.BuildScope.shared();
    const saved = scope.frame_number;
    defer scope.frame_number = saved;
    scope.frame_number +%= 1;
    try std.testing.expect(!state.chipContains(.{ .x = 100, .y = 170 }));
}

test "zoom state counts only its own window's frames, the main window's or the popover window's" {
    var state = ZoomState{};
    const scope = mod.BuildScope.shared();
    const saved = scope.frame_number;
    const saved_popover = scope.popover_window_frame_number;
    defer {
        scope.frame_number = saved;
        scope.popover_window_frame_number = saved_popover;
        scope.popover_window = false;
    }

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // The main window's frame lays the picture out.
    scope.begin(arena.allocator());
    _ = state.layout(.{ .x = 0, .y = 0, .width = 100, .height = 100 }, 50, 50);
    scope.end();
    // The popover window's frame after it leaves the count alone: the picture still takes a pinch.
    scope.beginPopoverWindow(arena.allocator());
    scope.end();
    try std.testing.expect(state.pinch(.{ .x = 50, .y = 50 }, 2));
    // The next main window frame that does not draw it does.
    scope.begin(arena.allocator());
    scope.end();
    try std.testing.expect(!state.pinch(.{ .x = 50, .y = 50 }, 2));

    // A picture the popover window lays out takes a pinch through the main window's frames,
    var popover_picture = ZoomState{};
    scope.beginPopoverWindow(arena.allocator());
    _ = popover_picture.layout(.{ .x = 0, .y = 0, .width = 100, .height = 100 }, 50, 50);
    scope.end();
    scope.begin(arena.allocator());
    scope.end();
    try std.testing.expect(popover_picture.pinch(.{ .x = 50, .y = 50 }, 2));
    // until the popover window draws without it, or hides.
    scope.forgetPopoverWindow();
    try std.testing.expect(!popover_picture.pinch(.{ .x = 50, .y = 50 }, 2));
}
