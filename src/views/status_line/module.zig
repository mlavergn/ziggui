//! A window's status line: the keys that work now, as `key action` pairs.

const std = @import("std");
const log = std.log.scoped(.ziggui_status_line_module);

/// One `key action` pair of a `StatusLine`.
pub const KeyHint = @import("key_hint.zig").KeyHint;
/// A `StatusLine`'s height, in points.
pub const status_line_height = @import("status_line.zig").status_line_height;
/// A window's status line: the keys that work now, as `key action` pairs.
pub const StatusLine = @import("status_line.zig").StatusLine;

// -----------------------------------------------------------------------------
// From the views module

/// The build arena, published theme and tokens, viewport, wrap cache and link handler (`BuildScope.shared()`), from the views module.
pub const BuildScope = @import("../module.zig").BuildScope;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;
/// Flexible space in a stack (from the views module).
pub const Spacer = @import("../module.zig").Spacer;
/// Builds stack views from tuples or slices (`fromSlice` keeps its slice), from the views module.
pub const StackBuilder = @import("../module.zig").StackBuilder;
/// A headless frame for the unit tests (from the views module).
pub const TestCanvas = @import("../module.zig").TestCanvas;
/// One line of text (from the views module).
pub const Text = @import("../module.zig").Text;
/// A node of the view tree (from the views module).
pub const View = @import("../module.zig").View;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("key_hint.zig");
    _ = @import("status_line.zig");
}
