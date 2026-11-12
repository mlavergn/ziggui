//! Stacks: children stacked vertically, side by side, or layered; and `ForEach`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_stacks);
const mod = @import("module.zig");

/// Children stacked vertically, 8 points apart, centered.
///
/// - `children`: a tuple literal or a slice of views.
/// - Returns: the stack.
pub fn VStack(children: anytype) mod.View {
    return mod.StackBuilder.make(.vertical, 8, .center, children);
}

/// Children side by side, 8 points apart, centered.
///
/// - `children`: a tuple literal or a slice of views.
/// - Returns: the stack.
pub fn HStack(children: anytype) mod.View {
    return mod.StackBuilder.make(.horizontal, 8, .center, children);
}

/// Children layered front to back, centered.
///
/// - `children`: a tuple literal or a slice of views.
/// - Returns: the stack.
pub fn ZStack(children: anytype) mod.View {
    return mod.StackBuilder.make(.depth, 0, .center, children);
}

/// Maps a slice to views; the result is spliced into the enclosing stack.
///
/// - `items`: the slice.
/// - `map`: makes an item's view.
/// - Returns: a group of the views.
pub fn ForEach(items: anytype, comptime map: anytype) mod.View {
    var views = mod.BuildScope.shared().allocator().alloc(mod.View, items.len) catch @panic("oom");
    for (items, 0..) |item, index| views[index] = map(item);
    return .{ .kind = .{ .group = views } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
