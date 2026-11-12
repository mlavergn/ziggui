//! A progress bar.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_progress_view);
const mod = @import("module.zig");

/// A determinate progress bar.
///
/// - `value`: how far along, clamped to 0..1.
/// - Returns: the view.
pub fn ProgressView(value: f32) mod.View {
    return .{ .kind = .{ .progress = .{ .value = std.math.clamp(value, 0, 1) } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
