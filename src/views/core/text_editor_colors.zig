//! The colors a `TextEditor` draws its caret, selection, gutter, current
//! line and find matches in, set for a subtree with `.textEditorColors()`.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_editor_colors);
const renderer = @import("renderer");

/// A `TextEditor`'s colors beyond its text (`.foregroundStyle()`) and ground
/// (`.background()`). Each is null for the theme's own: the caret in the
/// accent, the selection in the theme's selection color, no gutter ground,
/// line numbers in the tertiary label color, no current-line band, matches
/// in the soft accent and the current match outlined in the accent.
pub const TextEditorColors = struct {
    const Self = @This();

    /// The caret.
    caret: ?renderer.Color = null,

    /// The selection's fill.
    selection: ?renderer.Color = null,

    /// The line-number gutter's ground.
    gutter_background: ?renderer.Color = null,

    /// The line numbers.
    gutter_text: ?renderer.Color = null,

    /// A band across the caret's line.
    current_line: ?renderer.Color = null,

    /// A find's matches (`View.findNavigator`).
    find_match: ?renderer.Color = null,

    /// The outline of the current match.
    find_current: ?renderer.Color = null,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
