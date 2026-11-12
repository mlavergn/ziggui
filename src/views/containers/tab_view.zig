//! Tabbed container: a segmented control on top, a hairline, then the selected
//! tab's content. Pure composition: the bar is a `Picker` over the tab labels,
//! so selecting a segment drives the same interaction (and styling) as `Picker`.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_tab_view);
const mod = @import("module.zig");

/// A tabbed container: a centered segmented control at the top, a hairline, then
/// the selected tab's content filling the space below. The bar is a `Picker`
/// over the tab labels, so tapping a segment drives the same `.select`
/// interaction as `Picker` (and the `selection` binding is what the body
/// switches on). Rebuilt each frame, so "switching tabs" is just the binding
/// changing.
///
/// - `selection`: the selected tab's index.
/// - `tabs`: the pages.
/// - Returns: the tab view (`Empty` without tabs).
pub fn TabView(selection: mod.Binding(i64), tabs: []const mod.Tab) mod.View {
    const count = tabs.len;
    if (count == 0) return mod.Empty();
    const last: i64 = @intCast(count - 1);
    const selected: usize = @intCast(std.math.clamp(selection.get(), 0, last));
    const labels = mod.BuildScope.shared().allocator().alloc([]const u8, count) catch @panic("oom");
    for (tabs, 0..) |tab, index| labels[index] = tab.label;
    // Center the segmented control like a macOS tab bar (it sizes to its content).
    const bar = mod.HStack(.{ mod.Spacer(), mod.Picker(selection, labels), mod.Spacer() })
        .paddingInsets(.{ .top = 6, .leading = 8, .bottom = 6, .trailing = 8 })
        .frameMaxWidth();
    return mod.VStack(.{
        bar,
        mod.Divider(),
        tabs[selected].content.frameMaxWidth().frameMaxHeight(),
    }).spacing(0);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
