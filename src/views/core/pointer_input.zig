//! Routes the app's pointer events to what a frame painted: taps, right-clicks,
//! double and triple clicks, drags, hovers and wheel scrolls.

const std = @import("std");
const log = std.log.scoped(.ziggui_pointer_input);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Points scrolled per unit of wheel delta. Negative so a wheel-up (positive
/// `delta_y` in SDL) moves the content toward the top (decreasing offset),
/// matching platform convention.
const scroll_speed: f32 = -28;

/// The pointer's routing state: the drag under way, where the last press
/// landed, the modifiers and click count of the tap being dispatched. The
/// app's event loop feeds it; a frame's hit regions are what it routes to.
pub const PointerInput = struct {
    const Self = @This();

    /// The `TextEditor` currently being drag-selected (set on mouse-down over its
    /// text, cleared on mouse-up). Identity only — the live geometry is re-read from
    /// the current frame's hit regions on each motion event (so scrolling mid-drag
    /// stays correct).
    text_drag: ?*mod.TextFieldState = null,

    /// The `Binding.context` of a slider being dragged (mouse held after a
    /// knob/track press). Identifies the slider's hit region across rebuilds, the
    /// way `text_drag` uses the `*TextFieldState` pointer for a text drag.
    slider_drag: ?*anyopaque = null,

    /// A drag-area handler armed by a press.
    area_drag: ?mod.DragCallback = null,

    /// The last pointer position fed to `area_drag`.
    area_last: renderer.Point = .{ .x = 0, .y = 0 },

    /// Where the last primary press landed, for `armDrag` from inside a tap handler.
    press_point: renderer.Point = .{ .x = 0, .y = 0 },

    /// Called when a drag armed by `armDrag`/`onDrag` ends (mouse-up).
    drag_end: ?*const fn () void = null,

    /// Shift was held at the current tap's press.
    click_shift: bool = false,

    /// ⌘ (Ctrl off macOS) was held at the current tap's press.
    click_command: bool = false,

    /// The click count of the tap being dispatched (2 = a double-click).
    tap_clicks: u8 = 1,

    /// The current thread's pointer state.
    threadlocal var shared_input: Self = .{};

    /// The current thread's pointer input.
    ///
    /// - Returns: the shared pointer input.
    pub fn shared() *Self {
        return &shared_input;
    }

    /// A tap handler turns the press it is handling into a drag: `callback`
    /// then gets pointer deltas.
    ///
    /// - `self`: the pointer input.
    /// - `callback`: the drag handler.
    pub fn armDrag(self: *Self, callback: mod.DragCallback) void {
        self.arm(callback, self.press_point);
    }

    /// Sets what runs when an armed drag ends.
    ///
    /// - `self`: the pointer input.
    /// - `hook`: called on mouse-up after a drag; null for none.
    pub fn setDragEndHook(self: *Self, hook: ?*const fn () void) void {
        self.drag_end = hook;
    }

    /// Ends an in-progress mouse drag (the app calls this on mouse-up): an
    /// armed drag's own `end` runs, then the drag-end hook.
    ///
    /// - `self`: the pointer input.
    pub fn endDrag(self: *Self) void {
        const selection = mod.TextSelection.shared();
        if (selection.current) |*span| {
            span.dragging = false;
            if (span.anchor == span.head) selection.current = null;
        }
        if (self.area_drag) |armed| {
            if (armed.end) |end| end(armed.context);
            if (self.drag_end) |hook| hook();
        }
        self.text_drag = null;
        self.slider_drag = null;
        self.area_drag = null;
    }

    /// Drops every reference to `field`: a text drag on it ends. Its
    /// `TextFieldState.deinit` calls this, so a freed field is never matched.
    ///
    /// - `self`: the pointer input.
    /// - `field`: the field going away.
    pub fn forget(self: *Self, field: *const mod.TextFieldState) void {
        if (self.text_drag == field) self.text_drag = null;
    }

    /// Continues a drag started by a mouse-down on a `TextEditor` (extend the
    /// caret), a `Slider` (set its value from `point.x`), selectable text or an
    /// armed drag area. The dragged control's hit region is re-emitted every
    /// frame, so this re-reads the current geometry. No-op when no drag is active.
    ///
    /// - `self`: the pointer input.
    /// - `regions`: the frame's hit regions.
    /// - `point`: the pointer.
    pub fn drag(self: *Self, regions: []const mod.HitRegion, point: renderer.Point) void {
        if (self.area_drag) |armed| {
            armed.function(armed.context, point.x - self.area_last.x, point.y - self.area_last.y);
            self.area_last = point;
            return;
        }
        if (mod.TextSelection.shared().current) |*span| if (span.dragging) {
            // The view's region is re-emitted each frame: find this frame's copy.
            var index = regions.len;
            while (index > 0) {
                index -= 1;
                switch (regions[index].action) {
                    .textSelect => |hit| if (hit.key == span.key) {
                        span.head = hit.indexAt(point);
                        return;
                    },
                    else => {},
                }
            }
            return;
        };
        if (self.text_drag == null and self.slider_drag == null) return;
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (region.disabled) continue;
            switch (region.action) {
                .textClick => |click| if (click.state == self.text_drag) {
                    click.state.caret = click.caretIndexAt(point);
                    click.state.preferred_column = null;
                    return;
                },
                .slider => |slider| if (slider.binding.context == self.slider_drag) {
                    slider.binding.set(slider.valueForX(point.x));
                    return;
                },
                else => {},
            }
        }
    }

    /// Dispatches a tap at `point` to the top-most enabled hit region containing
    /// it. A plain tap (a callback or a selection) that arms no drag of its own
    /// also arms the nearest `onDrag` region beneath it under the point, so a
    /// tappable row inside a draggable one taps and can be dragged.
    ///
    /// - `self`: the pointer input.
    /// - `regions`: the frame's hit regions.
    /// - `point`: the tap.
    /// - Returns: true if a region took it.
    pub fn tap(self: *Self, regions: []const mod.HitRegion, point: renderer.Point) bool {
        self.press_point = point;
        mod.TextSelection.shared().current = null; // a press elsewhere clears it; a press on selectable text starts anew
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (region.action == .secondary) continue;
            if (!region.disabled and region.rect.contains(point)) {
                self.perform(region.action, point);
                if (self.passesDrag(region.action)) self.armBeneath(regions[0..index], point, region.rect);
                return true;
            }
        }
        return false;
    }

    /// Right-click at `point`: runs the top-most `onSecondaryTap` handler under it.
    ///
    /// - `self`: the pointer input.
    /// - `regions`: the frame's hit regions.
    /// - `point`: the click.
    /// - Returns: true if a handler ran.
    pub fn secondaryTap(self: *Self, regions: []const mod.HitRegion, point: renderer.Point) bool {
        _ = self;
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (region.disabled or !region.rect.contains(point)) continue;
            switch (region.action) {
                .secondary => |callback| {
                    callback.call();
                    return true;
                },
                else => {},
            }
        }
        return false;
    }

    /// Records the modifier keys held at a press so a tap handler can read them;
    /// the app runtime calls it, and tests do.
    ///
    /// - `self`: the pointer input.
    /// - `shift`: Shift was held.
    /// - `command`: ⌘ (Ctrl off macOS) was held.
    pub fn setClickModifiers(self: *Self, shift: bool, command: bool) void {
        self.click_shift = shift;
        self.click_command = command;
    }

    /// Whether Shift was held at the current tap's press (extend a selection).
    ///
    /// - `self`: the pointer input.
    /// - Returns: whether Shift was held.
    pub fn clickShift(self: *const Self) bool {
        return self.click_shift;
    }

    /// Whether ⌘ (Ctrl off macOS) was held at the current tap's press (add to a selection).
    ///
    /// - `self`: the pointer input.
    /// - Returns: whether it was held.
    pub fn clickCommand(self: *const Self) bool {
        return self.click_command;
    }

    /// Sets the click count of the tap about to be dispatched; the event loop
    /// sets it before dispatching.
    ///
    /// - `self`: the pointer input.
    /// - `count`: the click count (at least 1).
    pub fn setTapCount(self: *Self, count: u8) void {
        self.tap_clicks = @max(1, count);
    }

    /// The click count of the tap being dispatched (2 = a double-click), so a tap
    /// callback can tell a double-click on a row from a single one.
    ///
    /// - `self`: the pointer input.
    /// - Returns: the click count.
    pub fn tapCount(self: *const Self) u8 {
        return self.tap_clicks;
    }

    /// Handles a double-click at `point`: if the top-most region under it is an
    /// editable text field, selects the word there.
    ///
    /// - `self`: the pointer input.
    /// - `regions`: the frame's hit regions.
    /// - `point`: the click.
    /// - Returns: true when it selected a word; false so the caller can fall back to a tap.
    pub fn doubleClick(self: *Self, regions: []const mod.HitRegion, point: renderer.Point) bool {
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (region.disabled or !region.rect.contains(point)) continue;
            switch (region.action) {
                .textClick => |click| {
                    mod.Focus.shared().set(click.state);
                    click.state.selectWordAt(click.caretIndexAt(point));
                    self.text_drag = null; // a double-click selects a word; it does not arm a drag
                    return true;
                },
                else => return false, // a non-text control is on top — let the caller tap it
            }
        }
        return false;
    }

    /// Handles a triple-click at `point`: if the top-most region under it is an
    /// editable text field, selects all of its text.
    ///
    /// - `self`: the pointer input.
    /// - `regions`: the frame's hit regions.
    /// - `point`: the click.
    /// - Returns: true when it selected the text.
    pub fn tripleClick(self: *Self, regions: []const mod.HitRegion, point: renderer.Point) bool {
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (region.disabled or !region.rect.contains(point)) continue;
            switch (region.action) {
                .textClick => |click| {
                    mod.Focus.shared().set(click.state);
                    click.state.selectAll();
                    self.text_drag = null;
                    return true;
                },
                else => return false,
            }
        }
        return false;
    }

    /// The pointer moved from `from` to `to` (null = outside the window): tells
    /// each enabled hover region it left (`false`), then each it entered
    /// (`true`), so a menu bar hears the old title's leave before the new one's
    /// enter.
    ///
    /// - `self`: the pointer input.
    /// - `regions`: the frame's hover regions.
    /// - `from`: where the pointer was.
    /// - `to`: where it is.
    /// - Returns: whether any callback fired.
    pub fn hover(self: *const Self, regions: []const mod.HoverRegion, from: ?renderer.Point, to: ?renderer.Point) bool {
        _ = self;
        var fired = false;
        for ([_]bool{ false, true }) |entering| {
            for (regions) |region| {
                if (region.disabled) continue;
                const was = if (from) |point| region.rect.contains(point) else false;
                const now = if (to) |point| region.rect.contains(point) else false;
                if (was == now or now != entering) continue;
                region.callback.call(now);
                fired = true;
            }
        }
        return fired;
    }

    /// Routes a wheel delta to the top-most scroll region containing `point`
    /// (back-to-front, like `tap`).
    ///
    /// - `self`: the pointer input.
    /// - `regions`: the frame's scroll regions.
    /// - `point`: the pointer.
    /// - `delta_y`: SDL's `wheel.y`, positive away from the user.
    /// - Returns: true if a region consumed it.
    pub fn scroll(self: *const Self, regions: []const mod.ScrollRegion, point: renderer.Point, delta_y: f32) bool {
        _ = self;
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (region.rect.contains(point)) {
                region.state.scrollBy(delta_y * scroll_speed);
                // Surface the overlay scrollbar and keep the loop awake long enough
                // for it to fade back out (see FrameClock.scrollbarsAnimating).
                const clock = mod.FrameClock.shared();
                region.state.last_active_ms = clock.time_ms;
                clock.keepScrollbarsVisible();
                return true;
            }
        }
        return false;
    }

    /// Routes a wheel event with both deltas: `delta_y` as `scroll` does,
    /// and `delta_x` to the top-most horizontal region (`ScrollViewStateBoth`)
    /// containing `point`. A zero delta is skipped.
    ///
    /// - `self`: the pointer input.
    /// - `regions`: the frame's scroll regions, back to front.
    /// - `point`: the pointer.
    /// - `delta_x`: SDL's `wheel.x`, positive to the right.
    /// - `delta_y`: SDL's `wheel.y`, positive away from the user.
    /// - Returns: true when a region took either delta.
    pub fn scrollBoth(self: *const Self, regions: []const mod.ScrollRegion, point: renderer.Point, delta_x: f32, delta_y: f32) bool {
        var consumed = false;
        if (delta_y != 0) consumed = self.scroll(regions, point, delta_y);
        if (delta_x == 0) return consumed;
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (!region.horizontal or !region.rect.contains(point)) continue;
            // Positive x is to the right: the content moves left, so the offset grows.
            region.state.scrollByX(-delta_x * scroll_speed);
            const clock = mod.FrameClock.shared();
            region.state.last_active_ms = clock.time_ms;
            clock.keepScrollbarsVisible();
            return true;
        }
        return consumed;
    }

    /// Whether the pointer over `point` should show the text (I-beam) cursor: the
    /// top-most thing under it is a text field, an editor or selectable text.
    ///
    /// - `self`: the pointer input.
    /// - `regions`: the frame's hit regions.
    /// - `point`: the pointer.
    /// - Returns: whether to show the I-beam.
    pub fn textCursorAt(self: *const Self, regions: []const mod.HitRegion, point: renderer.Point) bool {
        _ = self;
        if (mod.TextSelection.shared().current) |span| if (span.dragging) return true;
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (region.disabled or region.action == .secondary or !region.rect.contains(point)) continue;
            return switch (region.action) {
                .textClick, .focus, .textSelect => true,
                else => false,
            };
        }
        return false;
    }

    /// Arms `callback` as the drag under way from `point`, telling it so (`begin`).
    ///
    /// - `self`: the pointer input.
    /// - `callback`: the drag handler.
    /// - `point`: where the drag starts.
    fn arm(self: *Self, callback: mod.DragCallback, point: renderer.Point) void {
        self.area_drag = callback;
        self.area_last = point;
        if (callback.begin) |begin| begin(callback.context, callback.tag);
    }

    /// Whether a tap that ran `action` leaves the press free to arm an
    /// `onDrag` region beneath it: a plain tap that started no drag of its own.
    /// A toggle or a stepper changes on the press, so pressing one to drag its
    /// row would change it too: they keep the press to themselves.
    ///
    /// - `self`: the pointer input.
    /// - `action`: the tapped region's action, just performed.
    /// - Returns: whether to look beneath it.
    fn passesDrag(self: *const Self, action: mod.HitAction) bool {
        if (self.area_drag != null or self.text_drag != null or self.slider_drag != null) return false;
        return switch (action) {
            .callback, .select => true,
            else => false,
        };
    }

    /// Arms the nearest draggable view beneath a tapped region, when the tapped
    /// region is part of it: a tap on a sheet's button, or on a context menu's
    /// full-frame dismiss area, over a draggable row never drags the row.
    ///
    /// - `self`: the pointer input.
    /// - `regions`: the regions beneath the tapped one, in paint order.
    /// - `point`: the press.
    /// - `tapped`: the tapped region's rect.
    fn armBeneath(self: *Self, regions: []const mod.HitRegion, point: renderer.Point, tapped: renderer.Rect) void {
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (region.disabled or !region.rect.contains(point)) continue;
            switch (region.action) {
                .drag => |armed| {
                    if (region.rect.containsRect(tapped, 0.5)) self.arm(armed, point);
                    return;
                },
                // A sheet's or popover's scrim: nothing under it takes the press.
                .dismiss => return,
                else => {},
            }
        }
    }

    /// Does what a tapped region does.
    ///
    /// - `self`: the pointer input.
    /// - `action`: the region's action.
    /// - `point`: the tap.
    fn perform(self: *Self, action: mod.HitAction, point: renderer.Point) void {
        switch (action) {
            .callback => |callback| callback.call(),
            .toggle, .dismiss => |binding| binding.set(!binding.get()),
            .slider => |slider| {
                slider.binding.set(slider.valueForX(point.x));
                self.slider_drag = slider.binding.context; // arm a drag so mouse-move tracks the knob
            },
            .step => |step| {
                const next = std.math.clamp(step.binding.get() + step.delta, step.min, step.max);
                step.binding.set(next);
            },
            .focus => |field| mod.Focus.shared().set(field),
            .textClick => |click| {
                mod.Focus.shared().set(click.state);
                const caret = click.caretIndexAt(point);
                click.state.caret = caret;
                click.state.last_caret = caret;
                // Anchor the selection here: a pure click leaves anchor == caret (no
                // selection); a drag (see `drag`) then extends from this point.
                click.state.selection_anchor = caret;
                click.state.preferred_column = null;
                self.text_drag = click.state;
            },
            .select => |selected| selected.binding.set(selected.value),
            .drag => |armed| self.arm(armed, point),
            .textSelect => |hit| {
                const at = hit.indexAt(point);
                mod.TextSelection.shared().current = .{ .key = hit.key, .anchor = at, .head = at, .dragging = true };
            },
            .secondary => {},
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "view: dispatchScroll routes a wheel delta to the region under the point" {
    var first = mod.ScrollState{ .content_height = 200, .viewport_height = 100, .offset = 50 };
    var second = mod.ScrollState{ .content_height = 200, .viewport_height = 100, .offset = 50 };
    const regions = [_]mod.ScrollRegion{
        .{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 100 }, .state = &first },
        .{ .rect = .{ .x = 0, .y = 100, .width = 100, .height = 100 }, .state = &second },
    };
    const input = PointerInput.shared();
    // a point in region b's rect moves b, not a
    try std.testing.expect(input.scroll(&regions, .{ .x = 50, .y = 150 }, 1));
    try std.testing.expectEqual(@as(f32, 50), first.offset);
    try std.testing.expect(second.offset != 50);
    // a point outside every region consumes nothing
    try std.testing.expect(!input.scroll(&regions, .{ .x = 500, .y = 500 }, 1));
}

test "view: dispatchScrollXY sends sideways deltas only to horizontal regions" {
    var vertical = mod.ScrollState{ .content_height = 200, .viewport_height = 100, .offset = 50 };
    var both = mod.ScrollState{ .content_height = 200, .viewport_height = 100, .offset = 50, .content_width = 300, .viewport_width = 100, .offset_x = 50 };
    const regions = [_]mod.ScrollRegion{
        .{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 100 }, .state = &vertical },
        .{ .rect = .{ .x = 0, .y = 100, .width = 100, .height = 100 }, .state = &both, .horizontal = true },
    };
    const input = PointerInput.shared();
    // Sideways over the vertical region: nothing takes it.
    try std.testing.expect(!input.scrollBoth(&regions, .{ .x = 50, .y = 50 }, 1, 0));
    try std.testing.expectEqual(@as(f32, 50), vertical.offset);
    // Sideways over the horizontal region: to the right grows the offset; the vertical one is untouched.
    try std.testing.expect(input.scrollBoth(&regions, .{ .x = 50, .y = 150 }, 1, 0));
    try std.testing.expect(both.offset_x > 50);
    try std.testing.expectEqual(@as(f32, 50), both.offset);
    // Down still goes to the region under the point, as dispatchScroll does.
    try std.testing.expect(input.scrollBoth(&regions, .{ .x = 50, .y = 50 }, 0, -1));
    try std.testing.expect(vertical.offset > 50);
}

test "an armed drag hears its press, its moves and, once, its end" {
    const Probe = struct {
        const Self = @This();
        tag: ?usize = null,
        travel: f32 = 0,
        ends: u32 = 0,
        fn begin(context: ?*anyopaque, tag: usize) void {
            const self: *Self = @ptrCast(@alignCast(context.?));
            self.tag = tag;
        }
        fn move(context: ?*anyopaque, delta_x: f32, delta_y: f32) void {
            const self: *Self = @ptrCast(@alignCast(context.?));
            self.travel += delta_x + delta_y;
        }
        fn end(context: ?*anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(context.?));
            self.ends += 1;
        }
    };
    var probe: Probe = .{};
    const regions = [_]mod.HitRegion{
        .{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 20 }, .action = .{ .drag = .{ .context = &probe, .function = Probe.move, .begin = Probe.begin, .end = Probe.end, .tag = 7 } }, .disabled = false },
    };
    const input = PointerInput.shared();
    defer input.endDrag();
    try std.testing.expect(input.tap(&regions, .{ .x = 10, .y = 10 }));
    try std.testing.expectEqual(@as(?usize, 7), probe.tag);
    input.drag(&regions, .{ .x = 10, .y = 16 });
    try std.testing.expectEqual(@as(f32, 6), probe.travel);
    input.endDrag();
    input.endDrag();
    try std.testing.expectEqual(@as(u32, 1), probe.ends);
}

test "a tap on a tappable view inside a draggable one taps it and arms the drag" {
    const Probe = struct {
        const Self = @This();
        taps: u32 = 0,
        travel: f32 = 0,
        ends: u32 = 0,
        fn tapped(self: *Self) void {
            self.taps += 1;
        }
        fn move(context: ?*anyopaque, delta_x: f32, delta_y: f32) void {
            const self: *Self = @ptrCast(@alignCast(context.?));
            self.travel += delta_x + delta_y;
        }
        fn end(context: ?*anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(context.?));
            self.ends += 1;
        }
    };
    var probe: Probe = .{};
    const outer: renderer.Rect = .{ .x = 0, .y = 0, .width = 100, .height = 40 };
    const regions = [_]mod.HitRegion{
        .{ .rect = outer, .action = .{ .drag = .{ .context = &probe, .function = Probe.move, .end = Probe.end } }, .disabled = false },
        .{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 20 }, .action = .{ .callback = mod.Callback.init(Probe, &probe, Probe.tapped) }, .disabled = false },
    };
    const input = PointerInput.shared();
    defer input.endDrag();
    // On the tappable part: the tap runs, and the press drags.
    try std.testing.expect(input.tap(&regions, .{ .x = 10, .y = 10 }));
    try std.testing.expectEqual(@as(u32, 1), probe.taps);
    input.drag(&regions, .{ .x = 10, .y = 15 });
    try std.testing.expectEqual(@as(f32, 5), probe.travel);
    input.endDrag();
    try std.testing.expectEqual(@as(u32, 1), probe.ends);
    // Outside the draggable view, a tap arms nothing.
    try std.testing.expect(!input.tap(&regions, .{ .x = 10, .y = 90 }));
    try std.testing.expect(input.area_drag == null);
}

test "a tap on an overlay above a draggable view never arms its drag" {
    const Probe = struct {
        const Self = @This();
        taps: u32 = 0,
        fn tapped(self: *Self) void {
            self.taps += 1;
        }
        fn move(_: ?*anyopaque, _: f32, _: f32) void {}
    };
    var probe: Probe = .{};
    var shown: renderer.State(bool) = .init(std.testing.allocator, true);
    defer shown.deinit();
    const row: renderer.Rect = .{ .x = 0, .y = 0, .width = 100, .height = 40 };
    const input = PointerInput.shared();
    defer input.endDrag();
    // A sheet: its scrim, then its button, both over the row.
    const sheet = [_]mod.HitRegion{
        .{ .rect = row, .action = .{ .drag = .{ .context = &probe, .function = Probe.move } }, .disabled = false },
        .{ .rect = .{ .x = 0, .y = 0, .width = 400, .height = 400 }, .action = .{ .dismiss = shown.binding() }, .disabled = false },
        .{ .rect = .{ .x = 5, .y = 5, .width = 300, .height = 30 }, .action = .{ .callback = mod.Callback.init(Probe, &probe, Probe.tapped) }, .disabled = false },
    };
    try std.testing.expect(input.tap(&sheet, .{ .x = 10, .y = 10 }));
    try std.testing.expectEqual(@as(u32, 1), probe.taps);
    try std.testing.expect(input.area_drag == null);
    // A context menu's full-frame dismiss area over the row.
    const menu = [_]mod.HitRegion{
        .{ .rect = row, .action = .{ .drag = .{ .context = &probe, .function = Probe.move } }, .disabled = false },
        .{ .rect = .{ .x = 0, .y = 0, .width = 400, .height = 400 }, .action = .{ .callback = mod.Callback.init(Probe, &probe, Probe.tapped) }, .disabled = false },
    };
    try std.testing.expect(input.tap(&menu, .{ .x = 10, .y = 10 }));
    try std.testing.expect(input.area_drag == null);
}

test "a toggle inside a draggable view flips on the press but never arms the drag" {
    const Probe = struct {
        const Self = @This();
        fn move(_: ?*anyopaque, _: f32, _: f32) void {}
    };
    var probe: Probe = .{};
    var on: renderer.State(bool) = .init(std.testing.allocator, false);
    defer on.deinit();
    const input = PointerInput.shared();
    defer input.endDrag();
    const regions = [_]mod.HitRegion{
        .{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 40 }, .action = .{ .drag = .{ .context = &probe, .function = Probe.move } }, .disabled = false },
        .{ .rect = .{ .x = 60, .y = 10, .width = 30, .height = 20 }, .action = .{ .toggle = on.binding() }, .disabled = false },
    };
    try std.testing.expect(input.tap(&regions, .{ .x = 70, .y = 20 }));
    try std.testing.expect(on.get());
    try std.testing.expect(input.area_drag == null);
}
