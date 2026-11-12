//! The overlay scrollbars a `ScrollViewState` draws and drags.

const std = @import("std");
const log = std.log.scoped(.ziggui_scrollbar);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A scrollbar thumb along one axis: where it starts, how long it is, and how
/// far it can travel. Shared by painting and dragging.
pub const Thumb = struct {
    const Self = @This();

    /// The thumb's top (its left on the horizontal bar).
    start: f32,

    /// Its height (its width on the horizontal bar).
    length: f32,

    /// How far it can move along the track.
    travel: f32,
};

/// Slim, rounded overlay scroll indicators on the right and bottom edges of a
/// viewport whose content overflows. A thumb's length and position track the
/// visible fraction, like a native overlay scrollbar; it shows briefly after a
/// scroll (see `FrameClock`), and its edge strip takes presses and drags.
pub const Scrollbar = struct {
    const Self = @This();

    /// The gap between a thumb and the viewport's edges.
    pub const inset: f32 = 2;

    /// The right-edge strip that grabs scrollbar clicks.
    ///
    /// - `view_rect`: the viewport.
    /// - Returns: the strip.
    pub fn strip(view_rect: renderer.Rect) renderer.Rect {
        return .{ .x = view_rect.maxX() - 12, .y = view_rect.y, .width = 12, .height = view_rect.height };
    }

    /// The bottom-edge strip that grabs horizontal scrollbar clicks.
    ///
    /// - `view_rect`: the viewport.
    /// - Returns: the strip.
    pub fn stripHorizontal(view_rect: renderer.Rect) renderer.Rect {
        return .{ .x = view_rect.x, .y = view_rect.maxY() - 12, .width = view_rect.width, .height = 12 };
    }

    /// The vertical thumb for a viewport of `scroll_state.viewport_height`
    /// starting at `top`.
    ///
    /// - `scroll_state`: the scroll position, with its recorded heights.
    /// - `top`: the viewport's top edge.
    /// - Returns: the thumb; null when the content fits.
    pub fn thumb(scroll_state: *const mod.ScrollState, top: f32) ?Thumb {
        return Self.thumbAlong(top, scroll_state.viewport_height, scroll_state.content_height, scroll_state.offset, scroll_state.maxOffset());
    }

    /// The horizontal bar's thumb.
    ///
    /// - `scroll_state`: the scroll position, with its recorded widths.
    /// - `left`: the viewport's left edge.
    /// - Returns: the thumb, its `start` the left and `length` the width; null when the content fits.
    pub fn thumbHorizontal(scroll_state: *const mod.ScrollState, left: f32) ?Thumb {
        return Self.thumbAlong(left, scroll_state.viewport_width, scroll_state.content_width, scroll_state.offset_x, scroll_state.maxOffsetX());
    }

    /// A press in the scrollbar strip: off the thumb, jump so the thumb centres on
    /// the pointer (macOS "jump to the spot clicked"); then drag from there.
    ///
    /// - `context`: the `ScrollState`.
    pub fn press(context: ?*anyopaque) void {
        const scroll_state: *mod.ScrollState = @ptrCast(@alignCast(context.?));
        const found = Self.thumb(scroll_state, scroll_state.viewport_y) orelse return;
        const input = mod.PointerInput.shared();
        if (input.press_point.y < found.start or input.press_point.y > found.start + found.length) {
            const fraction = (input.press_point.y - scroll_state.viewport_y - inset - found.length / 2) / found.travel;
            scroll_state.offset = std.math.clamp(fraction, 0, 1) * scroll_state.maxOffset();
        }
        scroll_state.last_active_ms = mod.FrameClock.shared().time_ms;
        input.armDrag(.{ .context = scroll_state, .function = Self.drag });
    }

    /// A drag of the vertical thumb.
    ///
    /// - `context`: the `ScrollState`.
    /// - `delta_y`: how far the pointer moved down.
    pub fn drag(context: ?*anyopaque, _: f32, delta_y: f32) void {
        const scroll_state: *mod.ScrollState = @ptrCast(@alignCast(context.?));
        const found = Self.thumb(scroll_state, scroll_state.viewport_y) orelse return;
        scroll_state.scrollBy(delta_y * scroll_state.maxOffset() / found.travel);
        scroll_state.last_active_ms = mod.FrameClock.shared().time_ms;
    }

    /// A press in the horizontal bar's strip: `press` across.
    ///
    /// - `context`: the `ScrollState`.
    pub fn pressHorizontal(context: ?*anyopaque) void {
        const scroll_state: *mod.ScrollState = @ptrCast(@alignCast(context.?));
        const found = Self.thumbHorizontal(scroll_state, scroll_state.viewport_x) orelse return;
        const input = mod.PointerInput.shared();
        if (input.press_point.x < found.start or input.press_point.x > found.start + found.length) {
            const fraction = (input.press_point.x - scroll_state.viewport_x - inset - found.length / 2) / found.travel;
            scroll_state.offset_x = std.math.clamp(fraction, 0, 1) * scroll_state.maxOffsetX();
        }
        scroll_state.last_active_ms = mod.FrameClock.shared().time_ms;
        input.armDrag(.{ .context = scroll_state, .function = Self.dragHorizontal });
    }

    /// A drag of the horizontal bar's thumb: `drag` across.
    ///
    /// - `context`: the `ScrollState`.
    /// - `delta_x`: how far the pointer moved across.
    pub fn dragHorizontal(context: ?*anyopaque, delta_x: f32, _: f32) void {
        const scroll_state: *mod.ScrollState = @ptrCast(@alignCast(context.?));
        const found = Self.thumbHorizontal(scroll_state, scroll_state.viewport_x) orelse return;
        scroll_state.scrollByX(delta_x * scroll_state.maxOffsetX() / found.travel);
        scroll_state.last_active_ms = mod.FrameClock.shared().time_ms;
    }

    /// Draws the vertical thumb on the right edge of `rect` when the content
    /// overflows and it is showing. No-op when everything fits.
    ///
    /// - `context`: the paint context.
    /// - `scroll_state`: the scroll position.
    /// - `rect`: the viewport.
    /// - `canvas`: where it draws.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paint(context: *const mod.Context, scroll_state: *const mod.ScrollState, rect: renderer.Rect, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
        const found = Self.thumb(scroll_state, rect.y) orelse return; // fits → nothing to show
        // Grabbed, or the pointer over its strip: shown solid and a little wider.
        const dragging = if (mod.PointerInput.shared().area_drag) |armed| armed.context == @as(?*anyopaque, @ptrCast(@constCast(scroll_state))) and armed.function == Self.drag else false;
        const hot = dragging or (if (context.hover_point) |point| Self.strip(rect).contains(point) else false);

        // Auto-hide: only visible briefly after the last scroll, then fade out.
        const fade = Self.fadeAmount(scroll_state, hot) orelse return;

        const width: f32 = if (hot) 7 else 4;
        const bar = renderer.Rect{ .x = rect.x + rect.width - width - inset, .y = found.start, .width = width, .height = found.length };
        // A muted thumb that reads on both light and dark surfaces.
        const color = context.theme.colors.secondary_label.withAlpha(0.45 * context.opacity * fade);
        try canvas.fillRoundedRect(bar, width / 2, color);
    }

    /// The horizontal overlay bar along the bottom edge: `paint` across.
    ///
    /// - `context`: the paint context.
    /// - `scroll_state`: the scroll position.
    /// - `rect`: the viewport.
    /// - `canvas`: where it draws.
    /// - Returns: nothing; propagates allocation failure.
    pub fn paintHorizontal(context: *const mod.Context, scroll_state: *const mod.ScrollState, rect: renderer.Rect, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
        const found = Self.thumbHorizontal(scroll_state, rect.x) orelse return;
        const dragging = if (mod.PointerInput.shared().area_drag) |armed| armed.context == @as(?*anyopaque, @ptrCast(@constCast(scroll_state))) and armed.function == Self.dragHorizontal else false;
        const hot = dragging or (if (context.hover_point) |point| Self.stripHorizontal(rect).contains(point) else false);
        const fade = Self.fadeAmount(scroll_state, hot) orelse return;
        const height: f32 = if (hot) 7 else 4;
        const bar = renderer.Rect{ .x = found.start, .y = rect.y + rect.height - height - inset, .width = found.length, .height = height };
        const color = context.theme.colors.secondary_label.withAlpha(0.45 * context.opacity * fade);
        try canvas.fillRoundedRect(bar, height / 2, color);
    }

    /// A thumb along one axis, sized by the visible fraction and placed by the offset.
    ///
    /// - `start`: where the track starts.
    /// - `shown`: the viewport's length.
    /// - `total`: the content's length.
    /// - `offset`: how far the content is scrolled.
    /// - `max`: the furthest it can be.
    /// - Returns: the thumb; null when the content fits.
    fn thumbAlong(start: f32, shown: f32, total: f32, offset: f32, max: f32) ?Thumb {
        const track_length = shown - inset * 2;
        if (max <= 0.5 or track_length <= 0) return null;
        const length = @max(24, track_length * std.math.clamp(shown / total, 0.06, 1));
        const travel = @max(1, track_length - length);
        return .{ .start = start + inset + travel * std.math.clamp(offset / max, 0, 1), .length = length, .travel = travel };
    }

    /// How visible a scrollbar is: 1 while hot or just scrolled, fading to 0
    /// after `FrameClock.scrollbar_hold_ms`.
    ///
    /// - `scroll_state`: the scroll position, with its last scroll's time.
    /// - `hot`: grabbed, or under the pointer.
    /// - Returns: the opacity; null when hidden (never scrolled, headless, faded out).
    fn fadeAmount(scroll_state: *const mod.ScrollState, hot: bool) ?f32 {
        if (hot) return 1;
        const now = mod.FrameClock.shared().time_ms;
        if (scroll_state.last_active_ms == 0 or now == 0) return null;
        const since = now -| scroll_state.last_active_ms;
        if (since >= mod.FrameClock.scrollbar_visible_ms) return null;
        if (since > mod.FrameClock.scrollbar_hold_ms) return 1 - @as(f32, @floatFromInt(since - mod.FrameClock.scrollbar_hold_ms)) / @as(f32, @floatFromInt(mod.FrameClock.scrollbar_fade_ms));
        return 1;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "view: dragging the horizontal scrollbar thumb scrolls the content sideways" {
    var scroll_state = mod.ScrollState{ .content_width = 1000, .viewport_width = 100, .viewport_x = 0 };
    const first = Scrollbar.thumbHorizontal(&scroll_state, 0).?;
    const input = mod.PointerInput.shared();
    // Press on the thumb, drag it all the way right: the content reaches its end.
    input.press_point = .{ .x = first.start + 1, .y = 95 };
    Scrollbar.pressHorizontal(&scroll_state);
    try std.testing.expectEqual(@as(f32, 0), scroll_state.offset_x);
    Scrollbar.dragHorizontal(&scroll_state, first.travel, 0);
    try std.testing.expectEqual(scroll_state.maxOffsetX(), scroll_state.offset_x);
    input.endDrag();
    // A press far right on the track, off the thumb, jumps there.
    scroll_state.offset_x = 0;
    input.press_point = .{ .x = 90, .y = 95 };
    Scrollbar.pressHorizontal(&scroll_state);
    try std.testing.expect(scroll_state.offset_x > scroll_state.maxOffsetX() * 0.8);
    input.endDrag();
}

test "view: dragging the scrollbar thumb scrolls the content" {
    var scroll_state = mod.ScrollState{ .content_height = 1000, .viewport_height = 100, .viewport_y = 0 };
    const first = Scrollbar.thumb(&scroll_state, 0).?;
    const input = mod.PointerInput.shared();
    // Press on the thumb, drag it all the way down: the content reaches its end.
    input.press_point = .{ .x = 95, .y = first.start + 1 };
    Scrollbar.press(&scroll_state);
    try std.testing.expectEqual(@as(f32, 0), scroll_state.offset);
    Scrollbar.drag(&scroll_state, 0, first.travel);
    try std.testing.expectEqual(scroll_state.maxOffset(), scroll_state.offset);
    input.endDrag();
    // A press low on the track, off the thumb, jumps there.
    scroll_state.offset = 0;
    input.press_point = .{ .x = 95, .y = 90 };
    Scrollbar.press(&scroll_state);
    try std.testing.expect(scroll_state.offset > scroll_state.maxOffset() * 0.8);
    input.endDrag();
}
