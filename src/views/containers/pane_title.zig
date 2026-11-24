//! A pane's title row over a divider, in the accent while the pane has the keys.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_pane_title);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A pane's title, small and semibold, then `trailing` at the far edge, over a divider.
///
/// - `title`: the title; cleaned for drawing.
/// - `focused`: the pane has the keys: the title takes the accent.
/// - `trailing`: what sits at the right (a count, a button), or `Empty()`.
/// - Returns: the view, as wide as it is given.
pub fn PaneTitle(title: []const u8, focused: bool, trailing: mod.View) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();
    return mod.VStack(.{
        mod.HStack(.{
            mod.Text(mod.DisplayText.clean(allocator, title)).font(.system(11)).fontWeight(.semibold).foregroundStyle(if (focused) tokens.accent_text else tokens.secondary_label).truncated(),
            mod.Spacer(),
            trailing,
        }).spacing(8).paddingInsets(.{ .top = 5, .leading = 10, .bottom = 5, .trailing = 10 }),
        mod.Divider(),
    }).spacing(0).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "pane title sets its title row over a divider" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const view = PaneTitle("Files", true, mod.Empty());
    window.end();
    try std.testing.expectEqual(@as(usize, 2), view.kind.stack.children.len);
}
