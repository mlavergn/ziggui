//! Flexible space in a stack.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_spacer);
const mod = @import("module.zig");

/// Flexible space that takes a stack's slack.
///
/// - Returns: the view.
pub fn Spacer() mod.View {
    return .{ .kind = .{ .spacer = .{} } };
}

/// Flexible space at least `min_length` long along its stack.
///
/// - `min_length`: the least length.
/// - Returns: the view.
pub fn MinSpacer(min_length: f32) mod.View {
    return .{ .kind = .{ .spacer = .{ .min_length = min_length } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
