//! A segmented picker over a selected index.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_picker);
const mod = @import("module.zig");

/// A segmented picker bound to a selected index.
///
/// - `selection`: the selected segment's index.
/// - `options`: the segments' titles.
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
