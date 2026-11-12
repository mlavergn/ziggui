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

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
