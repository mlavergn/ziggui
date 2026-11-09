const std = @import("std");
const log = std.log.scoped(.ziggui_menu_bar_menu);
const zigui = @import("zigui");

/// One entry of a `MenuBarMenu`: a title, its key on the right, and what
/// choosing it does. An empty title is a separator.
pub const MenuBarItem = struct {
    const Self = @This();

    /// The entry's title; empty for a separator.
    title: []const u8 = "",

    /// The key that does the same, right-aligned (`ctrl+O`); empty for none.
    key_text: []const u8 = "",

    /// Whether it can be chosen; a disabled entry is drawn dimmed and skipped by the keys.
    enabled: bool = true,

    /// What choosing it does, after the menu closes; null does nothing.
    action: ?zigui.Callback = null,

    /// A heading over the entries after it (a folded bar's menu titles):
    /// drawn as a label, never chosen.
    heading: bool = false,

    /// Reports whether the keys can land on this entry.
    ///
    /// - `self`: the entry.
    /// - Returns: true for an enabled entry that is neither a separator nor a heading.
    pub fn selectable(self: *const Self) bool {
        return self.enabled and self.title.len > 0 and !self.heading;
    }
};

/// One menu of a `MenuBar`: its title in the bar and its entries.
pub const MenuBarMenu = struct {
    const Self = @This();

    /// The title in the bar.
    title: []const u8,

    /// The entries, top to bottom.
    items: []const MenuBarItem,

    /// The open menu's width, in points.
    width: f32 = 260,

    /// An icon drawn in the bar instead of the title (a folded bar's `☰`);
    /// the title still names it for accessibility.
    icon: ?zigui.IconName = null,

    /// Every menu folded into one, as a narrow window shows them: a `☰`
    /// menu that lists each menu's entries under its title as a heading.
    /// The entries' actions are kept, so the folded menu is passed to
    /// `MenuBar` and to `MenuBarState.key` alike.
    ///
    /// - `allocator`: allocates the menu and its entries.
    /// - `menus`: the menus, in the bar's order.
    /// - Returns: one menu; the caller frees its `items`, then the slice
    ///   (`MenuBarMenus.deinit` does both); propagates allocation failure.
    pub fn fold(allocator: std.mem.Allocator, menus: []const Self) ![]const Self {
        var items: std.ArrayList(MenuBarItem) = .empty;
        errdefer items.deinit(allocator);
        var width: f32 = 0;
        for (menus, 0..) |menu, index| {
            if (index > 0) try items.append(allocator, .{});
            try items.append(allocator, .{ .title = menu.title, .heading = true });
            try items.appendSlice(allocator, menu.items);
            width = @max(width, menu.width);
        }
        const folded = try allocator.alloc(Self, 1);
        errdefer allocator.free(folded);
        folded[0] = .{ .title = "Menu", .items = try items.toOwnedSlice(allocator), .width = width, .icon = .menu };
        return folded;
    }

    /// The first entry the keys can land on at or after `from`, going `step`
    /// (1 or -1) and wrapping.
    ///
    /// - `self`: the menu.
    /// - `from`: where to start looking; past the end wraps.
    /// - `step`: 1 to look down, -1 to look up.
    /// - Returns: the entry's index, or null when none can be chosen.
    pub fn nextSelectable(self: *const Self, from: usize, step: isize) ?usize {
        const count = self.items.len;
        if (count == 0) return null;
        var at: isize = @intCast(from % count);
        for (0..count) |_| {
            const index: usize = @intCast(at);
            if (self.items[index].selectable()) return index;
            at = @mod(at + step, @as(isize, @intCast(count)));
        }
        return null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "folding lists every menu's entries under its title, keeping their actions" {
    const Probe = struct {
        const Self = @This();

        fn pick(_: ?*anyopaque) void {}
    };
    const menus = [_]MenuBarMenu{
        .{ .title = "File", .items = &.{.{ .title = "Open", .action = .{ .func = Probe.pick } }} },
        .{ .title = "Help", .items = &.{.{ .title = "Search" }}, .width = 300 },
    };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const folded = try MenuBarMenu.fold(arena.allocator(), &menus);
    try std.testing.expectEqual(1, folded.len);
    try std.testing.expectEqual(zigui.IconName.menu, folded[0].icon.?);
    try std.testing.expectEqual(@as(f32, 300), folded[0].width);
    const items = folded[0].items;
    // File (heading), Open, a separator, Help (heading), Search.
    try std.testing.expectEqual(5, items.len);
    try std.testing.expect(items[0].heading and !items[0].selectable());
    try std.testing.expect(items[1].action != null);
    try std.testing.expectEqualStrings("Help", items[3].title);
    try std.testing.expectEqual(@as(?usize, 1), folded[0].nextSelectable(0, 1));
}

test "a menu's keys skip separators and disabled entries, wrapping" {
    const menu: MenuBarMenu = .{ .title = "File", .items = &.{
        .{ .title = "Open" },
        .{},
        .{ .title = "Save", .enabled = false },
        .{ .title = "Quit" },
    } };
    try std.testing.expectEqual(@as(?usize, 0), menu.nextSelectable(0, 1));
    try std.testing.expectEqual(@as(?usize, 3), menu.nextSelectable(1, 1));
    try std.testing.expectEqual(@as(?usize, 0), menu.nextSelectable(4, 1));
    try std.testing.expectEqual(@as(?usize, 0), menu.nextSelectable(2, -1));
    const empty: MenuBarMenu = .{ .title = "Help", .items = &.{.{}} };
    try std.testing.expectEqual(@as(?usize, null), empty.nextSelectable(0, 1));
}

test "folding frees what it allocated when an allocation fails" {
    const Probe = struct {
        const Self = @This();

        fn foldAndFree(allocator: std.mem.Allocator) !void {
            const menus = [_]MenuBarMenu{
                .{ .title = "File", .items = &.{.{ .title = "Open" }} },
                .{ .title = "Help", .items = &.{.{ .title = "Search" }} },
            };
            const folded = try MenuBarMenu.fold(allocator, &menus);
            allocator.free(folded[0].items);
            allocator.free(folded);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.foldAndFree, .{});
}
