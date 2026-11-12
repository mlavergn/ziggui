//! `List`: a SwiftUI-style scrolling vertical container with hairline dividers
//! between rows and grouped-row padding.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_list);
const mod = @import("module.zig");

/// A SwiftUI-style List: a scrolling vertical container with hairline dividers
/// between rows and grouped-background styling.
///
/// - `rows`: a tuple literal or a slice of views.
/// - Returns: the list.
pub fn List(rows: anytype) mod.View {
    const views = mod.StackBuilder.toViews(rows);
    const flat = mod.StackBuilder.flattenGroups(views);
    // interleave dividers
    var with_dividers = mod.BuildScope.shared().allocator().alloc(mod.View, if (flat.len == 0) 0 else flat.len * 2 - 1) catch @panic("oom");
    var slot: usize = 0;
    for (flat, 0..) |row, index| {
        with_dividers[slot] = row.paddingInsets(.{ .top = 6, .leading = 12, .bottom = 6, .trailing = 12 }).frameMaxWidth();
        slot += 1;
        if (index + 1 < flat.len) {
            with_dividers[slot] = mod.Divider();
            slot += 1;
        }
    }
    const stack = mod.StackBuilder.fromSlice(.vertical, 0, .leading, with_dividers);
    return mod.ScrollView(stack);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
