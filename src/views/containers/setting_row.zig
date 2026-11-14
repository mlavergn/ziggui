//! A settings row: a label and its description, a control at the far edge.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_setting_row);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A settings row: `label` (13pt) on the leading edge with `description`
/// (12pt, `secondary_label`, wrapping) under it, omitted when empty, and
/// `control` (usually a `Toggle`) on the trailing edge at its ideal width
/// (`.fixedSize()`), vertically centered. Full width.
///
/// - `label`: what the setting is.
/// - `description`: what it does; empty for none.
/// - `control`: the control that changes it.
/// - Returns: the row.
pub fn SettingRow(label: []const u8, description: []const u8, control: mod.View) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const title = mod.Text(label).size(13).foreground(tokens.label);
    const texts = if (description.len == 0) mod.StackBuilder.make(.vertical, 0, .leading, .{title}) else mod.StackBuilder.make(.vertical, 2, .leading, .{
        title,
        mod.WrappedText(description).size(12).foreground(tokens.secondary_label).frameMaxWidth().frameAlign(.leading),
    });
    return mod.StackBuilder.make(.horizontal, 12, .center, .{
        texts.frameMaxWidth().frameAlign(.leading),
        control.fixedSize(),
    }).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a setting row puts its control at the far edge, its text at the near one" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    canvas.begin(renderer.MacosTheme.light);
    const bare = SettingRow("Strip inbound auth", "", mod.Empty());
    const row = SettingRow("Strip inbound auth", "Replace the client's Authorization with the profile's token before forwarding.", mod.Rectangle(renderer.Color.black).frame(30, 16));
    canvas.end();
    try std.testing.expectEqual(@as(usize, 1), bare.kind.stack.children[0].kind.stack.children.len);

    var frame = try canvas.render(row, 300, 60);
    defer frame.deinit();
    try std.testing.expect(frame.at(290, 30).r < 0.1);
    // Nothing dark in the gap between the wrapped text and the control.
    try std.testing.expect(frame.at(262, 30).r > 0.99);
}
