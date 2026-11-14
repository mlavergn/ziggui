//! The look of a composed field: what a `TokenField`, a `SearchField` and a
//! `FileBrowser` draw around themselves, so they read as one text field.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_field_chrome);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A composed field's corner radius, in points.
const field_radius: f32 = 6;

/// `content` drawn as one field: the `raised` ground, a `line_strong`
/// hairline border, corner radius 6. For a control composed of several views
/// (capsules and an input, a glyph and a chromeless `TextField`) that should
/// read as a single text field. Pad and size `content` first: the chrome is
/// added to its modifiers, and replaces any ground, border or corner it had.
///
/// - `content`: the field's content, padded and framed.
/// - Returns: the field.
pub fn FieldChrome(content: mod.View) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    return content
        .background(tokens.raised)
        .border(tokens.line_strong, 1)
        .cornerRadius(field_radius);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "field chrome adds the raised ground, the strong border and the corner, keeping the padding" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    canvas.begin(renderer.MacosTheme.light);
    const tokens = mod.BuildScope.shared().tokens();
    const field = FieldChrome(mod.Text("x").padding(4));
    canvas.end();
    try std.testing.expectEqual(tokens.raised, field.modifiers.background.?.color);
    try std.testing.expectEqual(tokens.line_strong, field.modifiers.border_color.?);
    try std.testing.expectEqual(field_radius, field.modifiers.corner_radius);
    try std.testing.expect(field.modifiers.padding != null);
}
