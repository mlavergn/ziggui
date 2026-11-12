//! A title behind a small color swatch.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_label);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A title with a small leading symbol swatch (placeholder for an icon set).
///
/// - `title`: the title.
/// - `symbol_color`: the swatch's color.
/// - Returns: the view.
pub fn Label(title: []const u8, symbol_color: renderer.Color) mod.View {
    return .{ .kind = .{ .label = .{ .title = title, .symbol_color = symbol_color } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
