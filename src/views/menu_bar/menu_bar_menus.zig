//! A menu bar's menus in both forms: every menu, and the one `☰` a narrow window shows.

const std = @import("std");
const log = std.log.scoped(.ziggui_menu_bar_menus);
const mod = @import("module.zig");

/// A menu bar's menus in both forms: every menu, and the one `☰` a window
/// narrower than `fold_below` shows (`MenuBarMenu.fold`).
/// `MenuBarState.shown` picks the form for the window's width.
pub const MenuBarMenus = struct {
    const Self = @This();

    /// Allocates the folded form, and frees it in `deinit`.
    allocator: std.mem.Allocator,

    /// Every menu, in the bar's order; borrowed.
    all: []const mod.MenuBarMenu,

    /// The same menus folded into one `☰`; owned.
    folded: []const mod.MenuBarMenu,

    /// The window width, in points, below which the menus fold.
    fold_below: f32,

    /// Makes both forms.
    ///
    /// - `allocator`: allocates the folded form; must outlive the result.
    /// - `all`: every menu; must outlive the result.
    /// - `fold_below`: the width below which the menus fold.
    /// - Returns: the menus; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator, all: []const mod.MenuBarMenu, fold_below: f32) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        const self = Self{
            .allocator = allocator,
            .all = all,
            .folded = try mod.MenuBarMenu.fold(allocator, all),
            .fold_below = fold_below,
        };
        return self;
    }

    /// Frees the folded form.
    ///
    /// - `self`: the menus; invalid afterwards.
    pub fn deinit(self: *Self) void {
        for (self.folded) |menu| self.allocator.free(menu.items);
        self.allocator.free(self.folded);
        self.* = undefined;
    }

    /// Reports whether a window `width` wide shows the folded form.
    ///
    /// - `self`: the menus.
    /// - `width`: the window's width.
    /// - Returns: true below `fold_below`.
    pub fn foldsAt(self: *const Self, width: f32) bool {
        return width < self.fold_below;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "both forms are made and freed" {
    const menus = [_]mod.MenuBarMenu{
        .{ .title = "File", .items = &.{.{ .title = "Open" }} },
        .{ .title = "Help", .items = &.{.{ .title = "Search" }} },
    };
    var both = try MenuBarMenus.init(std.testing.allocator, &menus, 640);
    defer both.deinit();
    try std.testing.expectEqual(2, both.all.len);
    try std.testing.expectEqual(1, both.folded.len);
    try std.testing.expect(both.foldsAt(639) and !both.foldsAt(640));
}
