//! A picker over a selected index: its options side by side (segmented),
//! or a pop-up menu, as `.pickerStyle()` and the theme family's platform say.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_picker);
const mod = @import("module.zig");

/// A picker bound to a selected index, as SwiftUI's `Picker`: segmented, or
/// a pop-up menu in a `Form` or with `.pickerStyle(.menu)`.
///
/// - `selection`: the chosen option's index.
/// - `options`: the options' titles.
/// - Returns: the view.
pub fn Picker(selection: mod.Binding(i64), options: []const []const u8) mod.View {
    return .{ .kind = .{ .picker = .{ .selection = selection, .options = options } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
