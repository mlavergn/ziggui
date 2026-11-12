//! Hairlines across and down a stack.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_divider);
const mod = @import("module.zig");

/// A horizontal hairline across a stack.
///
/// - Returns: the view.
pub fn Divider() mod.View {
    return .{ .kind = .divider };
}

/// A vertical hairline, the `HStack` counterpart to `Divider`.
///
/// - Returns: the view.
pub fn VDivider() mod.View {
    return .{ .kind = .verticalDivider };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
