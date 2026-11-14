//! A list row that shows its selection and whether its list has the focus.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_selectable_row);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A selectable list row: `content` pinned leading in a full-width, 28pt row
/// with 8pt of side padding and corner radius 6. A selected row of the
/// focused list fills with the accent (color the content with
/// `SelectableRowStyle.selectionText`, `on_accent` there); a selected row of
/// an unfocused list with `quaternary_fill`; an unselected row shows a hover
/// fill. Tapping it calls `on_tap`.
///
/// - `content`: the row's content.
/// - `selected`: whether the row is selected.
/// - `focused`: whether its list has the keyboard focus.
/// - `on_tap`: what a tap calls.
/// - Returns: the row.
pub fn SelectableRow(content: mod.View, selected: bool, focused: bool, on_tap: mod.Callback) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const row = mod.StackBuilder.make(.horizontal, 0, .center, .{content})
        .paddingInsets(.{ .leading = 8, .trailing = 8 })
        .frameHeight(28)
        .frameMaxWidth()
        .frameAlign(.leading)
        .cornerRadius(6)
        .onTap(on_tap);
    if (!selected) return row.hoverFill(tokens.hover);
    return row.background(if (focused) tokens.accent else tokens.quaternary_fill);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a selectable row fills by selection and focus, and taps" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const Probe = struct {
        const Self = @This();
        taps: usize = 0,
        fn onTap(self: *Self) void {
            self.taps += 1;
        }
    };
    var probe: Probe = .{};
    const callback = mod.Callback.init(Probe, &probe, Probe.onTap);
    canvas.begin(renderer.MacosTheme.light);
    const tokens = mod.BuildScope.shared().tokens();
    const focused = SelectableRow(mod.Text("a"), true, true, callback);
    const unfocused = SelectableRow(mod.Text("b"), true, false, callback);
    const plain = SelectableRow(mod.Text("c"), false, true, callback);
    canvas.end();
    try std.testing.expectEqual(tokens.accent, focused.modifiers.background.?.color);
    try std.testing.expectEqual(tokens.quaternary_fill, unfocused.modifiers.background.?.color);
    try std.testing.expect(plain.modifiers.background == null and plain.modifiers.hover_fill != null);

    var frame = try canvas.render(focused, 300, 28);
    defer frame.deinit();
    // The accent fills the row to its far end.
    const far = frame.at(290, 14);
    try std.testing.expect(far.b > far.r + 0.3);
    try std.testing.expect(canvas.tap(.{ .x = 200, .y = 14 }));
    try std.testing.expectEqual(@as(usize, 1), probe.taps);
}
