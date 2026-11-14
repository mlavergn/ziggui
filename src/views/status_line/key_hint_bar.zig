//! A bar of the keys that work now, each a key cap followed by its action.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_key_hint_bar);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The most hints a `KeyHintBar` shows; the rest are left off.
pub const key_hint_bar_limit: usize = 6;

/// The keys that work now, each a `KeyCap` followed by its action (11pt
/// medium, `secondary_label`), 12pt between hints, at most
/// `key_hint_bar_limit` of them: a 24pt bar with 12pt side padding on the
/// `bar_background` token (the theme's sidebar background, else its window
/// background). A key-cap take on `StatusLine`.
///
/// - `hints`: the keys, left to right; those past the limit are not shown.
/// - Returns: the bar, as wide as it is given.
pub fn KeyHintBar(hints: []const mod.KeyHint) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const shown = hints[0..@min(hints.len, key_hint_bar_limit)];
    const items = mod.BuildScope.shared().allocator().alloc(mod.View, shown.len + 1) catch @panic("oom");
    for (shown, 0..) |hint, index| {
        items[index] = mod.StackBuilder.make(.horizontal, 5, .center, .{
            mod.KeyCap(hint.key),
            mod.Text(hint.action).size(11).weight(.medium).foreground(tokens.secondary_label),
        });
    }
    items[shown.len] = mod.Spacer();
    return mod.StackBuilder.fromSlice(.horizontal, 12, .center, items)
        .paddingInsets(.{ .leading = 12, .trailing = 12 })
        .frameHeight(24)
        .frameMaxWidth()
        .background(tokens.bar_background);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a key hint bar shows at most six hints, on the bar ground" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const hints = [_]mod.KeyHint{
        .{ .key = "↑↓", .action = "move" },
        .{ .key = "↩", .action = "open" },
        .{ .key = "⌘K", .action = "palette" },
        .{ .key = "esc", .action = "back" },
        .{ .key = "tab", .action = "pane" },
        .{ .key = "/", .action = "find" },
        .{ .key = "q", .action = "quit" },
    };
    canvas.begin(renderer.MacosTheme.light);
    const tokens = mod.BuildScope.shared().tokens();
    const bar = KeyHintBar(&hints);
    const empty = KeyHintBar(&.{});
    canvas.end();
    // Six hints and the trailing spacer.
    try std.testing.expectEqual(@as(usize, key_hint_bar_limit + 1), bar.kind.stack.children.len);
    try std.testing.expectEqual(@as(usize, 1), empty.kind.stack.children.len);
    try std.testing.expectEqual(tokens.bar_background, bar.modifiers.background.?.color);

    var frame = try canvas.render(bar, 600, 24);
    defer frame.deinit();
    try std.testing.expect(frame.at(598, 12).approxEql(tokens.bar_background, 0.01));
}
