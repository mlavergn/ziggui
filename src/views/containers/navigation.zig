//! Navigation views: a master/detail split view and a route-stack push/pop
//! flow. All pure composition over the view primitives: "navigation" is just
//! mutating an app-owned `NavigationPath` that the per-frame body switches on.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_navigation);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// What a `NavigationLink` tap pushes: a (NavigationPath, route) pair bound at build
/// time. Allocated in the per-frame build arena, which outlives the frame until
/// the next rebuild, so the hit region's callback can safely read it.
const NavigationPush = struct {
    const Self = @This();

    /// The stack the route is pushed onto.
    navigation: *mod.NavigationPath,

    /// The route pushed.
    route: i64,

    /// Pushes the route; a failed push is logged, the stack left as it was.
    ///
    /// - `context`: the `NavigationPush`.
    fn apply(context: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        self.navigation.push(self.route) catch |err| log.err("navigation push failed [{any}]", .{err});
    }
};

/// A two-column master/detail layout: a fixed-width `sidebar` pane (filled with
/// `sidebar_fill` so it stays themable), a vertical hairline, and a `detail`
/// pane that fills the remaining width. Pure composition over `HStack`. For the
/// macOS 26 look, fill the sidebar with a `Material` (frosted glass) and put a
/// `Sidebar` list inside it.
///
/// - `sidebar`: the sidebar pane.
/// - `detail`: the detail pane.
/// - `sidebar_fill`: the sidebar's background.
/// - Returns: the split view.
pub fn NavigationSplitView(sidebar: mod.View, detail: mod.View, sidebar_fill: renderer.Color) mod.View {
    return mod.StackBuilder.make(.horizontal, 0, .center, .{
        sidebar.frameWidth(220).frameMaxHeight().background(sidebar_fill),
        mod.VDivider(),
        detail.frameMaxWidth().frameMaxHeight(),
    });
}

/// The macOS 26 *inset* split view: the sidebar floats as a rounded Liquid
/// Glass panel set in from the window edges (the style of chat/notes apps),
/// with no divider — the detail pane runs over the same window background.
/// Pair with `SidebarStyled(…, .prominent)` for accent-selected content rows.
///
/// - `sidebar`: the sidebar pane.
/// - `detail`: the detail pane.
/// - Returns: the split view.
pub fn NavigationSplitViewInset(sidebar: mod.View, detail: mod.View) mod.View {
    const panel = sidebar
        .frameWidth(220)
        .frameMaxHeight()
        .cornerRadius(14)
        .glassEffect();
    return mod.StackBuilder.make(.horizontal, 0, .center, .{
        mod.StackBuilder.make(.vertical, 0, .center, .{panel})
            .paddingInsets(.{ .top = 10, .leading = 10, .bottom = 10, .trailing = 4 })
            .frameMaxHeight(),
        detail.frameMaxWidth().frameMaxHeight(),
    });
}

/// A button that, when tapped, pushes `route` onto `navigation`'s route stack.
/// Reuses the plain `.callback` hit action (no new interaction kind needed).
///
/// - `label`: the button's title.
/// - `route`: the route pushed.
/// - `navigation`: the route stack; app-owned.
/// - Returns: the button.
pub fn NavigationLink(label: []const u8, route: i64, navigation: *mod.NavigationPath) mod.View {
    const push = mod.BuildScope.shared().allocator().create(NavigationPush) catch @panic("oom");
    push.* = .{ .navigation = navigation, .route = route };
    return mod.Button(label, .{ .context = push, .function = NavigationPush.apply });
}

/// A button that pops the top route off `navigation` (the navigation "back"
/// button). Render it in the screen's top bar when `navigation.depth() > 0`.
///
/// - `label`: the button's title.
/// - `navigation`: the route stack; app-owned.
/// - Returns: the button.
pub fn NavigationBackButton(label: []const u8, navigation: *mod.NavigationPath) mod.View {
    return mod.ButtonRoled(label, .plain, mod.Callback.init(mod.NavigationPath, navigation, mod.NavigationPath.pop));
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
