//! Split views: two panes and a divider the user drags (`HSplitView`, `VSplitView`).

const std = @import("std");
const log = std.log.scoped(.ziggui_split_module);

/// Where a split view's divider sits.
pub const SplitState = @import("split_state.zig").SplitState;
/// Two panes side by side, like SwiftUI's `HSplitView`.
pub const HSplitView = @import("split.zig").HSplitView;
/// Two panes stacked, like SwiftUI's `VSplitView`.
pub const VSplitView = @import("split.zig").VSplitView;

// -----------------------------------------------------------------------------
// From the views module

/// The build arena, published theme and tokens, viewport, wrap cache and link handler (`BuildScope.shared()`), from the views module.
pub const BuildScope = @import("../module.zig").BuildScope;
/// A tap handler (`init` wraps a method, `action` a function, `select` a selection), from the views module.
pub const Callback = @import("../module.zig").Callback;
/// A view that draws nothing (from the views module).
pub const Empty = @import("../module.zig").Empty;
/// Content built from the size it is laid out at (from the views module).
pub const GeometryReader = @import("../module.zig").GeometryReader;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;
/// Routes pointer events to a frame's regions (`PointerInput.shared()`), from the views module.
pub const PointerInput = @import("../module.zig").PointerInput;
/// A filled rectangle (from the views module).
pub const Rectangle = @import("../module.zig").Rectangle;
/// Flexible space in a stack (from the views module).
pub const Spacer = @import("../module.zig").Spacer;
/// A headless frame for the unit tests (from the views module).
pub const TestCanvas = @import("../module.zig").TestCanvas;
/// Children stacked vertically (from the views module).
pub const VStack = @import("../module.zig").VStack;
/// A node of the view tree (from the views module).
pub const View = @import("../module.zig").View;
/// Children layered front to back (from the views module).
pub const ZStack = @import("../module.zig").ZStack;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("split_state.zig");
    _ = @import("split.zig");
}
