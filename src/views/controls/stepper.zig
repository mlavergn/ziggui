//! A stepper over a `Binding(i64)`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_stepper);
const mod = @import("module.zig");

/// A stepper: a label and an up/down chevron column, clamped to a range.
///
/// - `label`: the label.
/// - `value`: the value it steps.
/// - `min`: the least value.
/// - `max`: the greatest value.
/// - `step`: how far one press moves it.
/// - Returns: the view.
pub fn Stepper(label: []const u8, value: mod.Binding(i64), min: i64, max: i64, step: i64) mod.View {
    return .{ .kind = .{ .stepper = .{ .value = value, .label = label, .min = min, .max = max, .step = step } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
