//! A macOS-style source-list sidebar of selectable rows.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_sidebar);
const mod = @import("module.zig");

/// A macOS 26 source-list sidebar: a vertical list of selectable rows with a
/// rounded "liquid glass" selection highlight, a leading icon, and a live hover
/// fill. Pure composition — each row is an `HStack` with an
/// `onTap(Callback.select)` that drives `selection`. Drop it inside a
/// `NavigationSplitView`'s sidebar pane (ideally over a `Material`).
///
/// - `items`: the rows.
/// - `selection`: the selected row's index.
/// - Returns: the sidebar.
pub fn Sidebar(items: []const mod.SidebarItem, selection: mod.Binding(i64)) mod.View {
    return SidebarStyled(items, selection, .neutral);
}

/// `Sidebar` with an explicit selection style (see `SidebarStyle`). Rows with a
/// `detail` subtitle render as two lines (chat-list style).
///
/// - `items`: the rows.
/// - `selection`: the selected row's index.
/// - `style`: how the selection is highlighted.
/// - Returns: the sidebar.
pub fn SidebarStyled(items: []const mod.SidebarItem, selection: mod.Binding(i64), style: mod.SidebarStyle) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const rows = mod.BuildScope.shared().allocator().alloc(mod.View, items.len) catch @panic("oom");
    for (items, 0..) |item, index| {
        const is_selected = selection.get() == @as(i64, @intCast(index));
        const prominent_selected = is_selected and style == .prominent;
        // Allocate the row's children in the build arena — `StackBuilder.fromSlice`
        // keeps the slice, so a stack-local array would dangle after we return.
        const contents = mod.BuildScope.shared().allocator().alloc(mod.View, 3) catch @panic("oom");
        var count: usize = 0;
        if (item.icon) |icon| {
            contents[count] = mod.Icon(icon, 16, if (prominent_selected) tokens.on_accent else null);
            count += 1;
        }
        var title = mod.Text(item.label);
        if (prominent_selected) title = title.foreground(tokens.on_accent);
        if (item.detail) |detail| {
            var subtitle = mod.Text(detail).font(.subheadline);
            subtitle = subtitle.foreground(if (prominent_selected) tokens.on_accent.withAlpha(0.75) else tokens.secondary_label);
            contents[count] = mod.StackBuilder.make(.vertical, 2, .leading, .{ title, subtitle });
        } else {
            contents[count] = title;
        }
        count += 1;
        contents[count] = mod.Spacer();
        count += 1;
        // Native sidebar rows are 32pt tall (16pt line + 8pt above/below).
        const vertical_padding: f32 = if (item.detail != null) 7 else 8;
        var row = mod.StackBuilder.fromSlice(.horizontal, 8, .center, contents[0..count])
            .paddingInsets(.{ .top = vertical_padding, .leading = 10, .bottom = vertical_padding, .trailing = 8 })
            .frameMaxWidth()
            .cornerRadius(if (style == .prominent) 10 else 6)
            .onTap(mod.Callback.select(selection, @intCast(index)));
        if (is_selected) {
            // Neutral grey wash (settings source lists) or vivid accent
            // (content lists), per the style.
            row = row.background(if (style == .prominent) tokens.selection else tokens.quaternary_fill);
        } else {
            row = row.hoverFill(tokens.hover);
        }
        rows[index] = row;
    }
    return mod.StackBuilder.fromSlice(.vertical, 2, .leading, rows).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
