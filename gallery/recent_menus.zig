//! The Menus & Commands section's recent-projects card: a `MenuTable` whose
//! File menu lists the projects opened last (`Entry.listing`, File → Open
//! Recent), drawn as a `MenuBar` here and, on macOS, installed as the menu
//! bar's File menu by `main.zig`, which swaps its Open Recent submenu
//! through `App.replaceSubmenu` as the list changes. A macOS-only Window
//! menu keeps what SDL's own gave (Minimize, Zoom, Close), since installing
//! menus replaces it.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_recent_menus);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The sample projects Open Sample Project opens, one after another.
const projects = [_][]const u8{ "aurora", "borealis", "cirrus", "delta", "ember", "fjord" };

/// What an entry of the recent-projects table does.
pub const RecentMenuAction = enum {
    const Self = @This();

    /// Opens the next sample project, putting it first among the recents.
    openSample,
    /// Minimizes the window (macOS's Window menu).
    minimize,
    /// Zooms the window, or puts it back (macOS's Window menu).
    zoom,
    /// Asks to close the window (macOS's Window menu).
    closeWindow,
};

/// One recent project's entry under Open Recent: what choosing it opens, in
/// the allocator the listing is given.
const RecentChoice = struct {
    const Self = @This();

    /// The card whose recents it lists.
    menus: *RecentMenus,
    /// The project, an index into `projects`.
    project: usize,

    /// Opens the project.
    ///
    /// - `self`: the choice.
    fn fire(self: *Self) void {
        self.menus.open(self.project);
    }
};

/// The recent-projects card's state: the recents, newest first, and the
/// project opened last.
pub const RecentMenus = struct {
    const Self = @This();

    /// The most recents Open Recent lists; opening another drops the oldest.
    pub const max_recents = 4;

    /// The title of the entry that lists the recents, which names macOS's
    /// submenu to `App.replaceSubmenu`.
    pub const open_recent = "Open Recent";

    /// The card's table type.
    pub const Table = ziggui.MenuTable(Self, RecentMenuAction);

    /// The card's menus: File, with Open Recent's listing, everywhere, and
    /// Window on macOS only. A `const`, as `MenuTable` asks.
    pub const table: Table = .{
        .entries = &.{
            .{ .menu = "File", .title = "Open Sample Project", .does = .openSample },
            .{ .menu = "File", .title = open_recent, .listing = Self.recentItems },
            .{ .menu = "Window", .title = "Minimize", .shortcut = "m", .does = .minimize, .only = .mac },
            .{ .menu = "Window", .title = "Zoom", .does = .zoom, .only = .mac },
            .{ .menu = "Window", .only = .mac },
            .{ .menu = "Window", .title = "Close Window", .shortcut = "w", .does = .closeWindow, .only = .mac },
        },
        .mac_titles = &.{ "File", "Window" },
        .other_titles = &.{"File"},
        .width = 240,
        .perform = Self.perform,
    };

    /// The card's drawn bar.
    bar: ziggui.MenuBarState = .{},
    /// The recent projects, newest first, as indices into `projects`; the
    /// first `count` hold.
    order: [max_recents]usize = undefined,
    /// How many recents `order` holds.
    count: usize = 0,
    /// The project Open Sample Project opens next.
    next: usize = 0,
    /// The project opened last; null before any.
    opened: ?usize = null,
    /// The recents changed since `takeChange` last ran: macOS's Open Recent
    /// wants its entries swapped.
    changed: bool = false,
    /// The window hooks the Window menu calls; `main.zig` fills them, and
    /// headless they do nothing.
    platform: gallery.Platform = .{},

    /// The card: the table's drawn bar over the last project opened, a
    /// button that opens the next sample project and one that clears the
    /// recents.
    ///
    /// - `self`: the card's state.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn card(self: *Self, theme: ziggui.Theme) ziggui.View {
        const scope = ziggui.BuildScope.shared();
        // The drawn bar as off macOS, so the card looks the same everywhere.
        const menus = Self.table.barMenus(scope.allocator(), self, false) catch @panic("oom");
        const said = if (self.opened) |project|
            scope.allocator().print("Opened {s}; it leads File → Open Recent now.", .{projects[project]}) catch @panic("oom")
        else
            "Nothing opened yet: open a sample project, then find it under File → Open Recent.";
        return gallery.Card.view(theme, "MenuTable with a list the app refills (File → Open Recent)", "ziggui.MenuTable · Entry.listing · ziggui.ListedMenuItem · App.replaceSubmenu", ziggui.VStack(.{
            ziggui.MenuBar(&self.bar, menus, .{}),
            ziggui.Divider(),
            ziggui.VStack(.{
                ziggui.Text(said).foregroundStyle(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
                ziggui.HStack(.{
                    ziggui.Button("Open Sample Project", ziggui.Callback.init(Self, self, Self.openSample)),
                    ziggui.Button("Clear Recents", ziggui.Callback.init(Self, self, Self.clear)),
                    ziggui.Spacer(),
                }).spacing(8),
                ziggui.WrappedText("On macOS the same table is the menu bar's File menu, its Open Recent submenu swapped through App.replaceSubmenu as the list changes.")
                    .foregroundStyle(theme.colors.secondary_label).frameMaxWidth().frameAlign(.leading),
                ziggui.Spacer(),
            }).spacing(10).alignment(.leading).padding(12).frameHeight(200),
        }).spacing(0).border(theme.colors.separator, 1));
    }

    /// Opens a project: it goes first among the recents, once, the oldest
    /// dropped past `max_recents`.
    ///
    /// - `self`: the card's state.
    /// - `project`: the project, an index into `projects`.
    pub fn open(self: *Self, project: usize) void {
        // Where it was among the recents, else the last slot (dropped when full).
        var from: usize = @min(self.count, max_recents - 1);
        for (self.order[0..self.count], 0..) |recent, index| {
            if (recent == project) from = index;
        }
        if (from == self.count) self.count += 1;
        var index = from;
        while (index > 0) : (index -= 1) self.order[index] = self.order[index - 1];
        self.order[0] = project;
        self.opened = project;
        self.changed = true;
    }

    /// Opens the next sample project (Open Sample Project).
    ///
    /// - `self`: the card's state.
    pub fn openSample(self: *Self) void {
        self.open(self.next);
        self.next = (self.next + 1) % projects.len;
    }

    /// Forgets the recents (Clear Menu, Clear Recents).
    ///
    /// - `self`: the card's state.
    pub fn clear(self: *Self) void {
        self.count = 0;
        self.changed = true;
    }

    /// Reports whether the recents changed since the last call, and forgets
    /// it: `main.zig` swaps macOS's Open Recent when it says so.
    ///
    /// - `self`: the card's state.
    /// - Returns: true when the recents changed.
    pub fn takeChange(self: *Self) bool {
        defer self.changed = false;
        return self.changed;
    }

    /// Open Recent's entries: each recent project, newest first, then Clear
    /// Menu; a disabled line when there are none (`Entry.listing`).
    ///
    /// - `self`: the card's state.
    /// - `allocator`: the menus' allocator, which owns the entries.
    /// - Returns: the entries; propagates allocation failure.
    fn recentItems(self: *Self, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const ziggui.ListedMenuItem {
        if (self.count == 0) return allocator.dupe(ziggui.ListedMenuItem, &.{.{ .title = "No Recent Projects" }});
        const items = try allocator.alloc(ziggui.ListedMenuItem, self.count + 2);
        for (items[0..self.count], self.order[0..self.count]) |*item, project| {
            const choice = try allocator.create(RecentChoice);
            choice.* = .{ .menus = self, .project = project };
            item.* = .{ .title = projects[project], .action = ziggui.Callback.init(RecentChoice, choice, RecentChoice.fire) };
        }
        items[self.count] = .{};
        items[self.count + 1] = .{ .title = "Clear Menu", .action = ziggui.Callback.init(Self, self, Self.clear) };
        return items;
    }

    /// Does what a table entry says (the table's `perform`).
    ///
    /// - `self`: the card's state.
    /// - `action`: the chosen entry's action.
    fn perform(self: *Self, action: RecentMenuAction) void {
        switch (action) {
            .openSample => self.openSample(),
            .minimize => self.platform.minimize(),
            .zoom => self.platform.toggleMaximized(),
            .closeWindow => self.platform.requestClose(),
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "recents keep the newest first, once each, the oldest dropped past the limit" {
    var menus: RecentMenus = .{};
    try std.testing.expect(!menus.takeChange());
    for (0..RecentMenus.max_recents + 1) |_| menus.openSample();
    try std.testing.expect(menus.takeChange());
    try std.testing.expect(!menus.takeChange());
    // Five opened, four kept: ember, the fifth, first; aurora, the first, gone.
    try std.testing.expectEqualSlices(usize, &.{ 4, 3, 2, 1 }, menus.order[0..menus.count]);
    // Opening one already listed moves it to the front without a copy.
    menus.open(2);
    try std.testing.expectEqualSlices(usize, &.{ 2, 4, 3, 1 }, menus.order[0..menus.count]);
    try std.testing.expectEqual(@as(?usize, 2), menus.opened);
    menus.clear();
    try std.testing.expectEqual(0, menus.count);
    try std.testing.expect(menus.takeChange());
}

test "Open Recent lists the recents, chosen from either bar, or a disabled line with none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var menus: RecentMenus = .{};

    // None: the heading over its disabled line.
    const empty = try RecentMenus.table.barMenus(allocator, &menus, false);
    try std.testing.expectEqual(1, empty.len);
    try std.testing.expectEqualStrings(RecentMenus.open_recent, empty[0].items[1].title);
    try std.testing.expect(empty[0].items[1].heading);
    try std.testing.expect(!empty[0].items[2].selectable());

    menus.openSample();
    menus.openSample();
    // The drawn bar: Open Sample Project, the heading, borealis, aurora, a separator, Clear Menu.
    const drawn = try RecentMenus.table.barMenus(allocator, &menus, false);
    try std.testing.expectEqual(6, drawn[0].items.len);
    try std.testing.expectEqualStrings("aurora", drawn[0].items[3].title);
    drawn[0].items[3].action.?.call();
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, menus.order[0..menus.count]);

    // macOS's: File and Window, Open Recent a replaceable submenu.
    const native = try RecentMenus.table.commandMenus(allocator, &menus);
    try std.testing.expectEqual(2, native.len);
    const recent = native[0].items[1];
    try std.testing.expect(recent.replaceable);
    try std.testing.expectEqual(4, recent.submenu.len);
    // What a swap hands macOS: Clear Menu empties the list.
    const swapped = try RecentMenus.Table.listedCommands(RecentMenus.table.find(RecentMenus.open_recent).?, allocator, &menus);
    swapped[3].action.?.call();
    try std.testing.expectEqual(0, menus.count);
    try std.testing.expect(RecentMenus.table.wellFormed());
}
