//! A choice drawn as macOS draws one in a grouped list (a Wi-Fi network, a
//! setting's options): rows in a rounded group, hairlines between them, and a
//! checkmark in a leading column on the chosen row. The rows say what each
//! option is; the app keeps which is chosen and moves the mark on a tap.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_check_list);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The checkmark's column: its glyph's size and the room it leaves before
/// the content, so every row's content lines up whether checked or not.
const check_size: f32 = 13;

/// The column's width.
const check_column: f32 = 20;

/// The row's side padding.
const side_inset: f32 = 12;

/// The row's padding above and below its content.
const row_inset: f32 = 9;

/// One option of a `CheckList`: `content` (a title, or a title over a line
/// of detail) after a checkmark column, the mark drawn while `checked`, the
/// whole row's width filled under the pointer, a tap anywhere on it calling
/// `on_tap`.
///
/// - `content`: what the option is.
/// - `checked`: it is the chosen one.
/// - `on_tap`: what choosing it does (the app moves the mark).
/// - Returns: the row.
pub fn CheckRow(content: mod.View, checked: bool, on_tap: mod.Callback) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const mark = if (checked) mod.Icon(.check, check_size, tokens.label) else mod.Empty();
    const row = mod.HStack(.{ mark.frameWidth(check_column).frameAlign(.leading), content, mod.Spacer() })
        .spacing(0)
        .paddingInsets(.{ .top = row_inset, .leading = side_inset, .bottom = row_inset, .trailing = side_inset })
        .frameMaxWidth()
        .hoverFill(tokens.hover)
        .onTapGesture(on_tap);
    return if (checked) row.accessibilityAddTraits(.{ .is_selected = true }) else row;
}

/// The group a choice's `CheckRow`s sit in: rounded, on a ground a shade off
/// the panel's, a hairline between each two rows, inset past the checkmark
/// column as macOS insets it.
///
/// - `rows`: the options (`CheckRow`s), in order.
/// - Returns: the group, as wide as it is given.
pub fn CheckList(rows: []const mod.View) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();
    const views = allocator.alloc(mod.View, if (rows.len == 0) 0 else rows.len * 2 - 1) catch @panic("oom");
    for (rows, 0..) |row, index| {
        if (index > 0) views[index * 2 - 1] = mod.Divider().paddingInsets(.{ .leading = side_inset + check_column });
        views[index * 2] = row;
    }
    return mod.StackBuilder.fromSlice(.vertical, 0, .leading, views)
        .frameMaxWidth()
        .background(tokens.hover)
        .cornerRadius(8)
        .clipped();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a check list marks the chosen row and takes a tap anywhere across a row" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const Probe = struct {
        const Self = @This();
        chosen: usize = 1,
        /// Moves the mark.
        ///
        /// - `self`: the probe.
        /// - `index`: the row tapped.
        fn choose(self: *Self, index: usize) void {
            self.chosen = index;
        }
    };
    var probe: Probe = .{};
    for (0..2) |_| {
        window.begin(renderer.MacosTheme.light);
        const rows = [_]mod.View{
            CheckRow(mod.Text("SSH"), probe.chosen == 0, mod.Callback.tagged(Probe, &probe, Probe.choose, 0)),
            CheckRow(mod.Text("HTTPS"), probe.chosen == 1, mod.Callback.tagged(Probe, &probe, Probe.choose, 1)),
        };
        const view = CheckList(&rows);
        window.end();
        var frame = try window.render(view, 300, 100);
        defer frame.deinit();
        // The rows' tap regions, in order; only the chosen one carries the
        // mark: dark ink in its checkmark column.
        try std.testing.expectEqual(2, window.hits.items.len);
        for (window.hits.items, 0..) |region, index| {
            var dark = false;
            const top: usize = @intFromFloat(region.rect.y);
            const bottom: usize = @intFromFloat(region.rect.maxY());
            for (14..30) |x| for (top..bottom) |y| if (frame.at(@intCast(x), @intCast(y)).r < 0.5) {
                dark = true;
            };
            try std.testing.expectEqual(index == probe.chosen, dark);
        }
        // A tap at the far right of the first row, past its text, chooses it.
        const first = window.hits.items[0].rect;
        if (probe.chosen == 1) try std.testing.expect(window.tap(.{ .x = first.maxX() - 4, .y = first.midY() }));
    }
    try std.testing.expectEqual(0, probe.chosen);
}
