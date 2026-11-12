//! A window's status line: the keys that work now, as `key action` pairs on
//! one row, the bottom of the frame TUIDESIGN, WUIDESIGN and GUIDESIGN share
//! (under the notice row). Pure composition over ziggui's stacks.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_status_line);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A `StatusLine`'s height, in points.
pub const status_line_height: f32 = 24;

/// The keys that work now: each key in the label color, its action after it
/// in the secondary one, on the row stripe.
///
/// - `hints`: the keys, left to right.
/// - Returns: the line, as wide as it is given.
pub fn StatusLine(hints: []const mod.KeyHint) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const items = mod.BuildScope.shared().allocator().alloc(mod.View, hints.len + 1) catch @panic("oom");
    for (hints, 0..) |hint, index| {
        items[index] = mod.HStack(.{
            mod.Text(hint.key).font(.caption).mono().weight(.semibold).foreground(tokens.label),
            mod.Text(hint.action).font(.caption).foreground(tokens.secondary_label),
        }).spacing(4);
    }
    items[hints.len] = mod.Spacer();
    return mod.StackBuilder.fromSlice(.horizontal, 14, .center, items)
        .paddingInsets(.{ .leading = 12, .trailing = 12 })
        .frameHeight(status_line_height)
        .frameMaxWidth()
        .background(tokens.row_stripe);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a status line draws its hints, and none" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    for ([_][]const mod.KeyHint{ &.{ .{ .key = "enter", .action = "send" }, .{ .key = "esc", .action = "stop" } }, &.{} }) |hints| {
        canvas.begin(renderer.ThemeFamily.macos.forScheme(.light));
        const line = StatusLine(hints);
        canvas.end();
        var frame = try canvas.render(line, 400, 24);
        frame.deinit();
    }
}
