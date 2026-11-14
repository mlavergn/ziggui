//! A pane's title block: a title, a one-line description, an accessory.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_pane_header);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A pane's title block: the title (22pt semibold) with `accessory` (buttons,
/// a state badge) right-aligned beside it, and the one-line description
/// (12pt, `secondary_label`) under it, omitted when empty. 20pt of padding,
/// full width.
///
/// - `title`: the pane's title.
/// - `description`: one line under it; empty for none.
/// - `accessory`: what sits right of the title (`Empty()` for nothing).
/// - Returns: the header.
pub fn PaneHeader(title: []const u8, description: []const u8, accessory: mod.View) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const title_row = mod.StackBuilder.make(.horizontal, 8, .center, .{
        mod.Text(title).size(22).weight(.semibold).foreground(tokens.label).truncated(),
        mod.Spacer(),
        accessory,
    }).frameMaxWidth();
    const block = if (description.len == 0) mod.StackBuilder.make(.vertical, 0, .leading, .{title_row}) else mod.StackBuilder.make(.vertical, 4, .leading, .{
        title_row,
        mod.Text(description).size(12).foreground(tokens.secondary_label).truncated(),
    });
    return block.padding(20).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a pane header drops an empty description and draws its accessory at the far edge" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    canvas.begin(renderer.MacosTheme.light);
    const bare = PaneHeader("Servers", "", mod.Empty());
    const full = PaneHeader("Servers", "Every endpoint this workspace knows.", mod.Rectangle(renderer.Color.black).frame(20, 20));
    const pinned = mod.VStack(.{ full, mod.Spacer() });
    canvas.end();
    try std.testing.expectEqual(@as(usize, 1), bare.kind.stack.children.len);
    try std.testing.expectEqual(@as(usize, 2), full.kind.stack.children.len);

    var frame = try canvas.render(pinned, 400, 100);
    defer frame.deinit();
    // The accessory sits inside the trailing padding, beside the title.
    try std.testing.expect(frame.at(370, 33).r < 0.1);
    try std.testing.expect(frame.at(390, 33).r > 0.99);
}
