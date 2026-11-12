//! A switch over a `Binding(bool)`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_toggle);
const mod = @import("module.zig");

/// A switch over a `Binding(bool)`, its label on the leading edge.
///
/// - `label`: the label.
/// - `value`: the state it shows and flips.
/// - Returns: the view.
pub fn Toggle(label: []const u8, value: mod.Binding(bool)) mod.View {
    return .{ .kind = .{ .toggle = .{ .value = value, .label = label } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
