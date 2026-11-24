//! A one-line text field.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_text_field);
const mod = @import("module.zig");

/// A one-line text field over an app-owned `TextFieldState`.
///
/// - `placeholder`: the hint shown while it is empty.
/// - `field_state`: its buffer, caret and selection.
/// - Returns: the view.
pub fn TextField(placeholder: []const u8, field_state: *mod.TextFieldState) mod.View {
    return .{ .kind = .{ .textField = .{ .state = field_state, .placeholder = placeholder } } };
}

/// A one-line field that shows a dot per character instead of its text
/// (SwiftUI's `SecureField`): a password's. Its text is never copied, cut
/// or given to accessibility, and is wiped from memory it leaves
/// (`TextFieldState.secure`).
///
/// - `placeholder`: the hint while it is empty.
/// - `field_state`: the field's text, caret and selection; app-owned.
/// - Returns: the field.
pub fn SecureField(placeholder: []const u8, field_state: *mod.TextFieldState) mod.View {
    var view = TextField(placeholder, field_state);
    view.modifiers.secure = true;
    return view;
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
