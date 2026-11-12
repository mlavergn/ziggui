//! A slider over a `Binding(f32)`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_slider);
const mod = @import("module.zig");

/// A horizontal slider over a range.
///
/// - `value`: the value it shows and sets.
/// - `min`: the value at the leading end.
/// - `max`: the value at the trailing end.
/// - Returns: the view.
pub fn Slider(value: mod.Binding(f32), min: f32, max: f32) mod.View {
    return .{ .kind = .{ .slider = .{ .value = value, .min = min, .max = max } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
