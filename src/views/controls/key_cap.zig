//! A keyboard key drawn as a small cap.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_key_cap);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A keyboard key's glyph (`⌘K`, `esc`, `↩`): 11pt medium monospaced text in
/// the secondary label color on the neutral soft ground, 5pt by 1pt of
/// padding, corner radius 4 (as the theme scales corners, so it matches the
/// cap a `ButtonKeyed` paints), a hairline border. As wide as its text.
///
/// - `key`: the key's text.
/// - Returns: the key cap.
pub fn KeyCap(key: []const u8) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    return mod.Text(key)
        .size(mod.ControlMetrics.key_cap_text_size)
        .mono()
        .weight(.medium)
        .foreground(tokens.secondary_label)
        .paddingInsets(.{
            .top = mod.ControlMetrics.key_cap_vertical_padding,
            .leading = mod.ControlMetrics.key_cap_horizontal_padding,
            .bottom = mod.ControlMetrics.key_cap_vertical_padding,
            .trailing = mod.ControlMetrics.key_cap_horizontal_padding,
        })
        .background(tokens.neutral_soft)
        .border(tokens.separator, 1)
        .cornerRadius(mod.BuildScope.shared().theme().metrics.radius(mod.ControlMetrics.key_cap_radius));
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a key cap is mono text on the neutral ground, with a border" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    canvas.begin(renderer.MacosTheme.light);
    const tokens = mod.BuildScope.shared().tokens();
    const cap = KeyCap("esc");
    const row = mod.HStack(.{ cap, mod.Spacer() });
    canvas.end();
    try std.testing.expect(cap.modifiers.mono);
    try std.testing.expectEqual(tokens.neutral_soft, cap.modifiers.background.?.color);
    try std.testing.expect(cap.modifiers.border_color != null);

    var frame = try canvas.render(row, 120, 20);
    defer frame.deinit();
    // Grey ground at the leading edge, white beyond the cap.
    try std.testing.expect(frame.at(3, 10).r < 0.99);
    try std.testing.expect(frame.at(110, 10).r > 0.99);
}
