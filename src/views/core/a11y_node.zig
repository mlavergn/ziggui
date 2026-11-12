//! One node of the accessibility tree a frame emits.

const std = @import("std");
const log = std.log.scoped(.ziggui_a11y_node);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One node of the accessibility tree ziggui emits in parallel with drawing
/// (there is no native view hierarchy to introspect). A platform bridge consumes
/// this tree; it is also directly assertable in headless tests.
pub const A11yNode = struct {
    const Self = @This();

    /// The node's frame.
    rect: renderer.Rect,

    /// What it is.
    role: mod.A11yRole,

    /// What it says.
    label: []const u8 = "",

    /// Its value ("on", a slider's number, a field's text).
    value: []const u8 = "",
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
