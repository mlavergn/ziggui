//! The colors a `SelectableRow`'s caller draws its content in.

const std = @import("std");
const log = std.log.scoped(.ziggui_selectable_row_style);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The colors that go with a `SelectableRow`'s fill, so every caller colors
/// a row's text the same way.
pub const SelectableRowStyle = struct {
    const Self = @This();

    /// The text color for a row's content: `on_accent` on a selected row of
    /// the focused list (its accent fill), else `label`.
    ///
    /// - `selected`: whether the row is selected.
    /// - `focused`: whether its list has the keyboard focus.
    /// - Returns: the text color.
    pub fn selectionText(selected: bool, focused: bool) renderer.Color {
        const tokens = mod.BuildScope.shared().tokens();
        return if (selected and focused) tokens.on_accent else tokens.label;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "selected text reads on the accent only while the list is focused" {
    mod.BuildScope.shared().setTheme(renderer.MacosTheme.light);
    const tokens = mod.BuildScope.shared().tokens();
    try std.testing.expectEqual(tokens.on_accent, SelectableRowStyle.selectionText(true, true));
    try std.testing.expectEqual(tokens.label, SelectableRowStyle.selectionText(true, false));
    try std.testing.expectEqual(tokens.label, SelectableRowStyle.selectionText(false, true));
}
