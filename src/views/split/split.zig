//! Split views, as SwiftUI's `HSplitView` and `VSplitView`: two panes with a
//! divider the user drags. Composed from ziggui's `GeometryReader`, so each
//! pane is laid out at the size the split gives it in the same frame. Where
//! the divider sits is the app's `SplitState`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_split);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// How far either side of the divider a press grabs it.
const grab: f32 = 4;

/// A split view's panes and state, in the build arena until its
/// `GeometryReader` lays it out.
const Split = struct {
    const Self = @This();

    /// Where the divider sits.
    state: *mod.SplitState,

    /// The leading or top pane.
    first: mod.View,

    /// The trailing or bottom pane.
    second: mod.View,

    /// A split along `axis`.
    ///
    /// - `axis`: `.horizontal` for side by side, `.vertical` for stacked.
    /// - `state`: where the divider sits.
    /// - `first`: the leading or top pane.
    /// - `second`: the trailing or bottom pane.
    /// - Returns: the split view.
    fn view(axis: renderer.Axis, state: *mod.SplitState, first: mod.View, second: mod.View) mod.View {
        state.axis = axis;
        const self = mod.BuildScope.shared().allocator().create(Self) catch @panic("oom");
        self.* = .{ .state = state, .first = first, .second = second };
        return mod.GeometryReader(Self, self, Self.body);
    }

    /// The panes, divider and grab strip for a split of `size`.
    ///
    /// - `self`: the split.
    /// - `size`: the size the split is laid out at.
    /// - Returns: the split's content.
    fn body(self: *const Self, size: renderer.Size) mod.View {
        const state = self.state;
        const horizontal = state.axis == .horizontal;
        state.total = if (horizontal) size.width else size.height;
        // Clamped for this layout only: `state.size` keeps what the user chose.
        const first = state.resolved(state.total);
        const rest = @max(0, state.total - first - 1);
        const line = mod.BuildScope.shared().tokens().separator;
        const handle = mod.Empty().onTap(state.pressCallback());
        const lead = @max(0, first - grab);
        if (horizontal) {
            const panes = mod.HStack(.{
                self.first.frame(first, size.height).clipped(),
                mod.Rectangle(line).frame(1, size.height),
                self.second.frame(rest, size.height).clipped(),
            }).spacing(0);
            // The grab strip goes last, so it wins over the panes' edges.
            const strip = mod.HStack(.{
                mod.Empty().frame(lead, size.height),
                handle.frame(1 + 2 * grab, size.height),
                mod.Spacer(),
            }).spacing(0);
            return mod.ZStack(.{ panes, strip });
        }
        const panes = mod.VStack(.{
            self.first.frame(size.width, first).clipped(),
            mod.Rectangle(line).frame(size.width, 1),
            self.second.frame(size.width, rest).clipped(),
        }).spacing(0);
        const strip = mod.VStack(.{
            mod.Empty().frame(size.width, lead),
            handle.frame(size.width, 1 + 2 * grab),
            mod.Spacer(),
        }).spacing(0);
        return mod.ZStack(.{ panes, strip });
    }
};

/// Two panes side by side, split by a divider the user drags, like SwiftUI's
/// `HSplitView`. Fills the space it is offered, so give it a frame or a
/// flexible parent.
///
/// - `state`: where the divider sits (app-owned).
/// - `first`: the leading pane.
/// - `second`: the trailing pane.
/// - Returns: the split view.
pub fn HSplitView(state: *mod.SplitState, first: mod.View, second: mod.View) mod.View {
    return Split.view(.horizontal, state, first, second);
}

/// Two panes stacked, split by a divider the user drags, like SwiftUI's
/// `VSplitView`. Fills the space it is offered, so give it a frame or a
/// flexible parent.
///
/// - `state`: where the divider sits (app-owned).
/// - `first`: the top pane.
/// - `second`: the bottom pane.
/// - Returns: the split view.
pub fn VSplitView(state: *mod.SplitState, first: mod.View, second: mod.View) mod.View {
    return Split.view(.vertical, state, first, second);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "an HSplitView paints both panes and drags its divider" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    // A failed expect must not leave a drag armed on this stack's `split`.
    defer mod.PointerInput.shared().endDrag();
    var split: mod.SplitState = .{ .initial_ratio = 0.4, .min_first = 20, .min_second = 20 };
    canvas.begin(renderer.MacosTheme.light);
    const view = HSplitView(&split, mod.Rectangle(renderer.Color.red), mod.Rectangle(renderer.Color.blue));
    canvas.end();
    var frame = try canvas.render(view, 100, 40);
    defer frame.deinit();
    try std.testing.expectEqual(@as(f32, 40), split.resolved(split.total));
    try std.testing.expect(frame.at(10, 20).r > frame.at(10, 20).b);
    try std.testing.expect(frame.at(80, 20).b > frame.at(80, 20).r);
    // A press on the divider arms a drag that moves it, clamped to the minimums.
    try std.testing.expect(canvas.tap(.{ .x = 40, .y = 20 }));
    mod.PointerInput.shared().drag(canvas.hits.items, .{ .x = 65, .y = 20 });
    try std.testing.expectEqual(@as(f32, 65), split.size);
    mod.PointerInput.shared().drag(canvas.hits.items, .{ .x = 540, .y = 20 });
    try std.testing.expectEqual(@as(f32, 80), split.size);
    // Coming back, the divider waits until the pointer reaches it.
    mod.PointerInput.shared().drag(canvas.hits.items, .{ .x = 530, .y = 20 });
    try std.testing.expectEqual(@as(f32, 80), split.size);
    mod.PointerInput.shared().drag(canvas.hits.items, .{ .x = 50, .y = 20 });
    try std.testing.expectEqual(@as(f32, 50), split.size);
}

test "a VSplitView stacks its panes, and a pane's content stays inside it" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var split: mod.SplitState = .{ .initial_size = 30, .min_first = 10, .min_second = 10 };
    canvas.begin(renderer.MacosTheme.light);
    // The top pane's red is taller than its pane: it must not spill below.
    const view = VSplitView(&split, mod.Rectangle(renderer.Color.red).frame(100, 90), mod.Empty());
    canvas.end();
    var frame = try canvas.render(view, 100, 100);
    defer frame.deinit();
    try std.testing.expectEqual(@as(f32, 30), split.resolved(split.total));
    try std.testing.expectEqual(renderer.Axis.vertical, split.axis);
    try std.testing.expect(frame.at(50, 15).r > 0.9 and frame.at(50, 15).g < 0.2);
    try std.testing.expect(frame.at(50, 70).g > 0.9);
}
