//! A multi-line, scrollable text editor.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_text_editor);
const mod = @import("module.zig");

/// A multi-line, scrollable plain-text editor (like SwiftUI's `TextEditor`). It
/// fills the space it is given. `editor_state` holds the buffer/caret/selection
/// (app-owned, like a `TextField`); `scroll_state` holds the vertical scroll so
/// the wheel can drive it and the caret can be followed. Pass `line_numbers` to
/// show a gutter. The event loop routes editing keys to whichever field is
/// focused, so no extra wiring is needed beyond owning the two states.
///
/// - `editor_state`: its buffer, caret and selection.
/// - `scroll_state`: its vertical scroll.
/// - `line_numbers`: whether a line-number gutter shows.
/// - Returns: the view.
pub fn TextEditor(editor_state: *mod.TextFieldState, scroll_state: *mod.ScrollState, line_numbers: bool) mod.View {
    return .{ .kind = .{ .textEditor = .{ .state = editor_state, .scroll = scroll_state, .line_numbers = line_numbers } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
