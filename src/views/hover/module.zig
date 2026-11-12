//! A hover popover: a view's details shown once the pointer rests on it.

const std = @import("std");
const log = std.log.scoped(.ziggui_hover_module);

/// Which row of a list the pointer rests on, and since when (a `HoverPopover`'s delay).
pub const HoverState = @import("hover_state.zig").HoverState;
/// A view's details in a popover once the pointer rests on it.
pub const HoverPopover = @import("hover.zig").HoverPopover;

// -----------------------------------------------------------------------------
// From the views module

/// The build arena, published theme and tokens, viewport, wrap cache and link handler (`BuildScope.shared()`), from the views module.
pub const BuildScope = @import("../module.zig").BuildScope;
/// A view that draws nothing (from the views module).
pub const Empty = @import("../module.zig").Empty;
/// The app's millisecond clock and scrollbar fade timing (`FrameClock.shared()`), from the views module.
pub const FrameClock = @import("../module.zig").FrameClock;
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
    _ = @import("hover_state.zig");
    _ = @import("hover.zig");
}
