//! A form field: its label over the control, and a line of help under it.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_labeled_field);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A labeled form field: `label` in the secondary color over `control`, and `help` wrapped under it.
///
/// - `label`: a sentence-case noun ("Bucket", "Region"); cleaned for drawing.
/// - `control`: the field, picker, table or toggle.
/// - `help`: a constraint or a note, or empty for none; cleaned for drawing.
/// - Returns: the view, leading-aligned, as wide as it is given.
pub fn LabeledField(label: []const u8, control: mod.View, help: []const u8) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();
    return mod.VStack(.{
        mod.Text(mod.DisplayText.clean(allocator, label)).size(12).foreground(tokens.secondary_label),
        control,
        if (help.len > 0) mod.WrappedText(mod.DisplayText.clean(allocator, help)).size(12).foreground(tokens.secondary_label).frameMaxWidth().frameAlign(.leading) else mod.Empty(),
    }).spacing(4).alignment(.leading).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "labeled field drops empty help" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    window.begin(renderer.MacosTheme.light);
    const view = LabeledField("Bucket", mod.Empty(), "");
    window.end();
    try std.testing.expect(view.kind.stack.children[2].kind == .empty);
}
