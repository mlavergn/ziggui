//! A view that draws nothing.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_empty);
const mod = @import("module.zig");

/// A view that draws nothing and takes no space of its own.
///
/// - Returns: the view.
pub fn Empty() mod.View {
    return .{ .kind = .empty };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
