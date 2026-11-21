//! A find bar: a search field, where the find stands, and Previous, Next
//! and Done, as an editor or a table shows under ⌘F.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_find_bar);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A find bar: a `SearchField` 300pt wide, the count ("3 of 40"), then
/// Previous, Next and Done at the trailing edge, on the bar ground. Pass the
/// app's keys through `actions.handleKey(key, field)` while it shows.
///
/// - `placeholder`: the field's hint while it is empty.
/// - `field`: the field's text; app-owned.
/// - `count`: where the find stands, or null before one has run.
/// - `actions`: what Enter, the buttons and the keys do.
/// - Returns: the bar, as wide as it is given.
pub fn FindBar(placeholder: []const u8, field: *mod.TextFieldState, count: ?mod.FindCount, actions: mod.FindActions) mod.View {
    const scope = mod.BuildScope.shared();
    const tokens = scope.tokens();
    const status: []const u8 = if (count) |found| found.textAlloc(scope.allocator()) catch @panic("oom") else "";
    return mod.StackBuilder.make(.horizontal, 8, .center, .{
        mod.SearchField(placeholder, field, actions.on_submit, null).frameWidth(300),
        mod.Text(status).font(.footnote).foreground(tokens.secondary_label),
        mod.Spacer(),
        mod.ButtonRoled("Previous", .normal, actions.on_previous),
        mod.ButtonRoled("Next", .normal, actions.on_next),
        mod.ButtonRoled("Done", .normal, actions.on_done),
    }).paddingInsets(.{ .top = 6, .leading = 10, .bottom = 6, .trailing = 10 }).frameMaxWidth().background(tokens.bar_background);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a find bar shows the count and its Done button closes it" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    defer mod.Focus.shared().clear();
    const Probe = struct {
        const Self = @This();

        /// How many times the bar was closed.
        done: usize = 0,

        /// Ignores a find.
        ///
        /// - `self`: the probe.
        fn ignore(self: *Self) void {
            _ = self;
        }

        /// Counts a close.
        ///
        /// - `self`: the probe.
        fn close(self: *Self) void {
            self.done += 1;
        }
    };
    var probe: Probe = .{};
    const ignore = mod.Callback.init(Probe, &probe, Probe.ignore);
    const actions = mod.FindActions{ .on_submit = ignore, .on_next = ignore, .on_previous = ignore, .on_done = mod.Callback.init(Probe, &probe, Probe.close) };

    window.begin(renderer.MacosTheme.light);
    const bar = FindBar("Find", &field, .{ .current = 2, .total = 40 }, actions);
    window.end();
    var frame = try window.render(bar, 800, 40);
    defer frame.deinit();
    // Done is the trailing button.
    var x: f32 = 796;
    while (x > 600 and probe.done == 0) : (x -= 2) _ = window.tap(.{ .x = x, .y = 20 });
    try std.testing.expectEqual(@as(usize, 1), probe.done);
}
