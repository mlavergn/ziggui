//! An app's settings, as SwiftUI's `Settings` scene draws a `TabView` on
//! macOS: the selected page's title, a toolbar of tabs (a symbol over each
//! title), and the selected page below.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_settings);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Builds the settings toolbar's tabs.
const SettingsToolbar = struct {
    const Self = @This();

    /// One tab: its symbol over its title, in the accent while selected on a
    /// rounded ground, lit under the pointer otherwise.
    ///
    /// - `tab`: the tab.
    /// - `index`: its index.
    /// - `selected`: whether it is the one shown.
    /// - `selection`: the selected tab's index, set by a tap.
    /// - Returns: the tab's button.
    fn tabButton(tab: mod.Tab, index: usize, selected: bool, selection: mod.Binding(i64)) mod.View {
        const tokens = mod.BuildScope.shared().tokens();
        const color = if (selected) tokens.accent else tokens.secondary_label;
        var button = mod.VStack(.{
            if (tab.icon) |icon| mod.Icon(icon, 22, color) else mod.Empty(),
            mod.Text(tab.label).font(.subheadline).foreground(color),
        }).spacing(3)
            .paddingInsets(.{ .top = 5, .leading = 9, .bottom = 4, .trailing = 9 })
            .frameMinWidth(64)
            .cornerRadius(7)
            .onTap(mod.Callback.select(selection, @intCast(index)));
        button = if (selected) button.background(tokens.quaternary_fill) else button.hoverFill(tokens.hover);
        return button;
    }
};

/// An app's settings, as SwiftUI's `Settings { TabView { … } }` draws on
/// macOS: the selected tab's title over a toolbar of `tabs` (each its `icon`
/// over its `label`, the selected one in the accent), a divider, and the
/// selected tab's content (usually a `Form`) below. Present it in a sheet
/// (`.sheet`) at the width the app chooses, as SwiftUI's `.frame(width:)`.
///
/// - `selection`: the selected tab's index; app-owned, clamped to the tabs.
/// - `tabs`: the pages.
/// - Returns: the settings view.
pub fn Settings(selection: mod.Binding(i64), tabs: []const mod.Tab) mod.View {
    const scope = mod.BuildScope.shared();
    const tokens = scope.tokens();
    if (tabs.len == 0) return mod.Empty();
    const last: i64 = @intCast(tabs.len - 1);
    const shown: usize = @intCast(std.math.clamp(selection.get(), 0, last));
    const buttons = scope.allocator().alloc(mod.View, tabs.len) catch @panic("oom");
    for (tabs, buttons, 0..) |tab, *button, index| button.* = SettingsToolbar.tabButton(tab, index, index == shown, selection);
    const toolbar = mod.VStack(.{
        mod.Text(tabs[shown].label).font(.headline).foreground(tokens.secondary_label),
        mod.StackBuilder.fromSlice(.horizontal, 2, .center, buttons),
    }).spacing(8)
        .paddingInsets(.{ .top = 10, .bottom = 8 })
        .frameMaxWidth()
        .background(tokens.bar_background);
    return mod.VStack(.{
        toolbar,
        mod.Divider(),
        mod.StackBuilder.make(.vertical, 0, .leading, .{tabs[shown].content})
            .paddingInsets(.{ .top = 16, .leading = 20, .bottom = 20, .trailing = 20 })
            .frameMaxWidth(),
    }).spacing(0).frameMaxWidth();
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "settings shows the selected tab's page, and a tap on another tab selects it" {
    const window = try mod.TestWindow.create(std.testing.allocator);
    defer window.destroy();
    var selection = renderer.State(i64).init(std.testing.allocator, 0);
    defer selection.deinit();
    window.begin(renderer.MacosTheme.light);
    const tabs = [_]mod.Tab{
        .{ .label = "General", .icon = .settings, .content = mod.Text("general page") },
        .{ .label = "Advanced", .icon = .slidersHorizontal, .content = mod.Text("advanced page") },
    };
    const view = Settings(selection.binding(), &tabs);
    window.end();
    // Title, toolbar, divider, then the first tab's page.
    try std.testing.expectEqualStrings("general page", view.kind.stack.children[2].kind.stack.children[0].kind.text.string);
    var frame = try window.render(view, 400, 200);
    defer frame.deinit();
    // The tab buttons are the only tap regions; the second is the rightmost.
    var second: ?renderer.Rect = null;
    for (window.hits.items) |hit| {
        if (second == null or hit.rect.x > second.?.x) second = hit.rect;
    }
    try std.testing.expect(window.tap(.{ .x = second.?.midX(), .y = second.?.midY() }));
    try std.testing.expectEqual(@as(i64, 1), selection.get());
}
