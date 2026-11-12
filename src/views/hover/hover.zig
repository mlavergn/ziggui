//! A popover that opens when the pointer rests on a view, as a tooltip does
//! but holding any view: a list row's details. Composed from ziggui's
//! `.onHover` and `.popover`; the delay and which row is under the pointer
//! are the app's `HoverState`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_hover);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One row's hold on a `HoverState`, in the build arena: the hover callback's
/// and the popover binding's context.
const HoverRow = struct {
    const Self = @This();

    /// The list's state.
    state: *mod.HoverState,

    /// The row.
    id: usize,

    /// The pointer entered or left the row.
    ///
    /// - `context`: the row.
    /// - `inside`: it entered.
    fn hovered(context: ?*anyopaque, inside: bool) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        if (inside) self.state.enter(self.id, mod.FrameClock.shared().time()) else self.state.leave(self.id);
    }

    /// The popover's binding: shown while the state says so.
    ///
    /// - `context`: the row.
    /// - Returns: true while the popover is open.
    fn presented(context: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(context));
        return self.state.shows(self.id, mod.FrameClock.shared().time());
    }

    /// The popover was dismissed (a tap outside it).
    ///
    /// - `context`: the row.
    /// - `open`: false when dismissed.
    fn setPresented(context: *anyopaque, open: bool) void {
        const self: *Self = @ptrCast(@alignCast(context));
        if (!open) self.state.dismiss();
    }
};

/// `content` with `details` in a popover once the pointer has rested on it
/// for `HoverState.delay_ms`, like a tooltip that holds a view. It closes
/// when the pointer moves to another row or leaves the list, or on a tap.
///
/// Mark the list `.popoverPassthrough()` so a click on another row reaches
/// it while a popover is open, and keep the app's loop awake while
/// `HoverState.waiting` (an idle loop draws no frame to open it on).
///
/// - `content`: the row.
/// - `state`: the list's hover state, app-owned.
/// - `id`: the row's id in the list.
/// - `details`: what the popover shows; built only while it is open, so
///   pass `mod.Empty()` and rebuild when `HoverState.shows` is false.
/// - Returns: the row.
pub fn HoverPopover(content: mod.View, state: *mod.HoverState, id: usize, details: mod.View) mod.View {
    // A row entered since the last frame starts its delay now, not at the
    // event's (possibly stale) clock.
    state.stamp(mod.FrameClock.shared().time());
    const row = mod.BuildScope.shared().allocator().create(HoverRow) catch @panic("oom");
    row.* = .{ .state = state, .id = id };
    const hovering = content.onHover(.{ .context = row, .function = HoverRow.hovered });
    if (!state.shows(id, mod.FrameClock.shared().time())) return hovering;
    return hovering.popover(.{ .context = row, .get_fn = HoverRow.presented, .set_fn = HoverRow.setPresented }, details);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a hover popover opens on its row after the delay and a dismissal closes it" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const saved = mod.FrameClock.shared().time();
    defer mod.FrameClock.shared().setTime(saved);
    var state: mod.HoverState = .{};

    // Not yet hovered: a plain row with a hover handler and no popover.
    mod.FrameClock.shared().setTime(1000);
    canvas.begin(renderer.MacosTheme.light);
    var view = HoverPopover(mod.Text("row").frame(100, 20), &state, 4, mod.Text("details"));
    canvas.end();
    try std.testing.expect(view.modifiers.on_hover != null);
    try std.testing.expectEqual(@as(usize, 0), view.modifiers.overlay.len);

    // The pointer enters through the hover callback after an idle wait: the
    // clock still reads the last frame's time. The frame it wakes starts the
    // delay; the popover opens only once the delay has passed since.
    view.modifiers.on_hover.?.call(true);
    try std.testing.expectEqual(@as(?usize, 4), state.over);
    mod.FrameClock.shared().setTime(5000);
    canvas.begin(renderer.MacosTheme.light);
    view = HoverPopover(mod.Text("row").frame(100, 20), &state, 4, mod.Text("details"));
    canvas.end();
    try std.testing.expectEqual(@as(usize, 0), view.modifiers.overlay.len);
    try std.testing.expect(state.waiting(5000));
    mod.FrameClock.shared().setTime(5000 + mod.HoverState.delay_ms);
    canvas.begin(renderer.MacosTheme.light);
    view = HoverPopover(mod.Text("row").frame(100, 20), &state, 4, mod.Text("details"));
    canvas.end();
    try std.testing.expectEqual(@as(usize, 1), view.modifiers.overlay.len);
    try std.testing.expect(view.modifiers.overlay[0].presented.get());

    // A tap outside dismisses it.
    view.modifiers.overlay[0].presented.set(false);
    try std.testing.expect(!state.shows(4, mod.FrameClock.shared().time()));
}
