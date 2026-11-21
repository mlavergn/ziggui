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

/// A `SelectableRow` of a label and a value, as SwiftUI's `LabeledContent`
/// in a selectable `List`: an optional leading icon and the title, then the
/// value in a footnote at the trailing edge, each truncated to fit and colored
/// by `SelectableRowStyle` (`on_accent` on the focused list's selection).
///
/// - `icon`: the leading icon, if any.
/// - `title`: what the row is.
/// - `value`: what it says about it, at the trailing edge; may be empty.
/// - `selected`: whether the row is selected.
/// - `focused`: whether its list has the keyboard focus.
/// - `on_tap`: what a tap calls.
/// - Returns: the row.
pub fn SelectableLabeledRow(icon: ?mod.IconName, title: []const u8, value: []const u8, selected: bool, focused: bool, on_tap: mod.Callback) mod.View {
    const ink = mod.SelectableRowStyle.selectionText(selected, focused);
    const soft = mod.SelectableRowStyle.secondaryText(selected, focused);
    const label = mod.Text(title).foreground(ink).truncated();
    const detail = mod.Text(value).font(.footnote).foreground(soft).truncated();
    const content = if (icon) |glyph|
        mod.HStack(.{ mod.Icon(glyph, 13, soft), label, mod.Spacer(), detail }).spacing(6)
    else
        mod.HStack(.{ label, mod.Spacer(), detail }).spacing(6);
    return SelectableRow(content, selected, focused, on_tap);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a selectable row fills by selection and focus, and taps" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const Probe = struct {
        const Self = @This();
        taps: usize = 0,
        /// Counts a tap.
        ///
        /// - `self`: the probe.
        fn onTap(self: *Self) void {
            self.taps += 1;
        }
    };
    var probe: Probe = .{};
    const callback = mod.Callback.init(Probe, &probe, Probe.onTap);
    window.begin(renderer.MacosTheme.light);
    const tokens = mod.BuildScope.shared().tokens();
    const focused = SelectableRow(mod.Text("a"), true, true, callback);
    const unfocused = SelectableRow(mod.Text("b"), true, false, callback);
    const plain = SelectableRow(mod.Text("c"), false, true, callback);
    window.end();
    try std.testing.expectEqual(tokens.accent, focused.modifiers.background.?.color);
    try std.testing.expectEqual(tokens.quaternary_fill, unfocused.modifiers.background.?.color);
    try std.testing.expect(plain.modifiers.background == null and plain.modifiers.hover_fill != null);

    var frame = try window.render(focused, 300, 28);
    defer frame.deinit();
    // The accent fills the row to its far end.
    const far = frame.at(290, 14);
    try std.testing.expect(far.b > far.r + 0.3);
    try std.testing.expect(window.tap(.{ .x = 200, .y = 14 }));
    try std.testing.expectEqual(@as(usize, 1), probe.taps);
}

test "a selectable labeled row puts its value at the trailing edge" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const Probe = struct {
        const Self = @This();
        /// A tap that does nothing.
        fn noop(_: ?*anyopaque) void {}
    };
    const callback: mod.Callback = .{ .function = Probe.noop };
    window.begin(renderer.MacosTheme.light);
    const tokens = mod.BuildScope.shared().tokens();
    const chosen = SelectableLabeledRow(.mapPin, "Pole 12", "app capture", true, true, callback);
    const plain = SelectableLabeledRow(null, "Pole 13", "MMMM", false, true, callback);
    window.end();
    try std.testing.expectEqual(tokens.accent, chosen.modifiers.background.?.color);
    try std.testing.expect(plain.modifiers.background == null and plain.modifiers.hover_fill != null);

    var frame = try window.render(plain, 300, 28);
    defer frame.deinit();
    // The value's ink is near the row's right end, past the middle.
    var rightmost: u32 = 0;
    for (0..28) |y| for (150..300) |x| {
        const pixel = frame.at(@intCast(x), @intCast(y));
        if (pixel.r < 0.7) rightmost = @max(rightmost, @as(u32, @intCast(x)));
    };
    try std.testing.expect(rightmost > 270);
}
