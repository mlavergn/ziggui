//! An app's menus as one table: the drawn menu bar off macOS and the native
//! menu bar on macOS are both built from it, and a choice comes back as the
//! app's own action.

const std = @import("std");
const log = std.log.scoped(.ziggui_menu_table);
const mod = @import("module.zig");

/// Which systems a menu entry shows on.
pub const MenuOnly = enum {
    const Self = @This();

    /// macOS and the rest.
    all,
    /// macOS only.
    mac,
    /// Everything but macOS (macOS's application menu holds Settings and Quit).
    other,
};

/// An app's menus, as a table of entries that each name one of the app's `Action`s.
///
/// The app writes its entries once, menu by menu (an entry with no title is a
/// separator), with the titles of its menus on macOS and elsewhere. From
/// that the table builds the window's drawn menu bar (`barMenus`), macOS's
/// menu bar (`commandMenus`), and finds the ⌘ / Ctrl shortcut a key is
/// (`chooseShortcut`); every choice calls `perform(context, action)`, where
/// the app decides what runs (and what a modal holds back). Keep the table a
/// `const` the app declares once: the menus' callbacks point back at it.
///
/// - `Context`: what `perform` acts on (the app).
/// - `Action`: what an entry does (the app's union or enum).
/// - Returns: the table type.
pub fn MenuTable(comptime Context: type, comptime Action: type) type {
    return struct {
        const Self = @This();

        /// One entry; a separator when `title` is empty.
        pub const Entry = struct {
            /// The menu it is in, as the titles name it.
            menu: []const u8,
            /// Its title, or empty for a separator.
            title: []const u8 = "",
            /// The key the app's status line names for it, shown beside the title, or empty.
            hint: []const u8 = "",
            /// The ⌘ (Ctrl off macOS) shortcut, one character, or empty.
            shortcut: [:0]const u8 = "",
            /// What choosing it does; null for a separator.
            does: ?Action = null,
            /// Where it shows.
            only: MenuOnly = .all,

            /// Whether the entry shows on this system.
            ///
            /// - `self`: the entry.
            /// - `mac`: this is macOS.
            /// - Returns: true when it shows.
            pub fn shows(self: *const Entry, mac: bool) bool {
                return switch (self.only) {
                    .all => true,
                    .mac => mac,
                    .other => !mac,
                };
            }
        };

        /// What a built menu's entry calls: the table, the context and the entry, in the menus' allocator.
        const Choice = struct {
            /// The table.
            table: *const Self,
            /// What the entry acts on.
            context: *Context,
            /// The entry.
            entry: *const Entry,

            /// Chooses the entry.
            ///
            /// - `self`: the choice.
            fn fire(self: *Choice) void {
                self.table.choose(self.context, self.entry);
            }
        };

        /// Every entry, menu by menu, in order.
        entries: []const Entry,
        /// The menus on macOS, after the application menu, in order.
        mac_titles: []const []const u8,
        /// The drawn menus elsewhere, in order.
        other_titles: []const []const u8,
        /// A drawn menu's width, in points.
        width: f32,
        /// Does an entry's action.
        perform: *const fn (context: *Context, action: Action) void,

        /// The menus on this system, in order.
        ///
        /// - `self`: the table.
        /// - `mac`: this is macOS.
        /// - Returns: the titles.
        pub fn titlesFor(self: *const Self, mac: bool) []const []const u8 {
            return if (mac) self.mac_titles else self.other_titles;
        }

        /// Does what an entry says; a separator does nothing.
        ///
        /// - `self`: the table.
        /// - `context`: what the action acts on.
        /// - `entry`: the entry chosen.
        pub fn choose(self: *const Self, context: *Context, entry: *const Entry) void {
            log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

            const action = entry.does orelse return;
            self.perform(context, action);
        }

        /// Chooses the entry whose shortcut is `char` on this system: Ctrl+<char> off macOS, where no native menu takes it.
        ///
        /// - `self`: the table.
        /// - `context`: what the action acts on.
        /// - `char`: the key typed with the command modifier.
        /// - `mac`: this is macOS.
        /// - Returns: true when an entry took it.
        pub fn chooseShortcut(self: *const Self, context: *Context, char: u21, mac: bool) bool {
            for (self.entries) |*entry| {
                if (entry.shortcut.len != 1 or entry.shortcut[0] != char or !entry.shows(mac)) continue;
                self.choose(context, entry);
                return true;
            }
            return false;
        }

        /// The entry titled `title`, for a test or a key that names one.
        ///
        /// - `self`: the table.
        /// - `title`: the entry's title.
        /// - Returns: the entry, or null.
        pub fn find(self: *const Self, title: []const u8) ?*const Entry {
            for (self.entries) |*entry| if (std.mem.eql(u8, entry.title, title)) return entry;
            return null;
        }

        /// The window's drawn menu bar: each menu with the entries shown on this system, keyed as `WindowChrome.keyText` spells them.
        ///
        /// - `self`: the table; a `const` that outlives the menus.
        /// - `allocator`: owns the menus; they live as long as the app keeps them.
        /// - `context`: what the entries act on; it must not move afterwards.
        /// - `mac`: this is macOS (a headless check draws the bar there too).
        /// - Returns: the menus; propagates allocation failure.
        pub fn barMenus(self: *const Self, allocator: std.mem.Allocator, context: *Context, mac: bool) ![]const mod.MenuBarMenu {
            const titles = self.titlesFor(mac);
            const menus = try allocator.alloc(mod.MenuBarMenu, titles.len);
            for (menus, titles) |*menu, title| {
                var items: std.ArrayList(mod.MenuBarItem) = .empty;
                for (self.entries) |*entry| {
                    if (!std.mem.eql(u8, entry.menu, title) or !entry.shows(mac)) continue;
                    if (entry.title.len == 0) {
                        try items.append(allocator, .{});
                        continue;
                    }
                    const choice = try allocator.create(Choice);
                    choice.* = .{ .table = self, .context = context, .entry = entry };
                    try items.append(allocator, .{
                        .title = entry.title,
                        .key_text = try mod.WindowChrome.keyText(allocator, entry.hint, entry.shortcut),
                        .action = mod.Callback.init(Choice, choice, Choice.fire),
                    });
                }
                menu.* = .{ .title = title, .items = try items.toOwnedSlice(allocator), .width = self.width };
            }
            return menus;
        }

        /// macOS's menu bar after the application menu: each entry shown there,
        /// its hint beside its title when it has no ⌘ shortcut (which macOS draws itself).
        ///
        /// - `self`: the table; a `const` that outlives the menus.
        /// - `allocator`: owns the menus, for the process's life.
        /// - `context`: what the entries act on; it must not move afterwards.
        /// - Returns: the menus; propagates allocation failure.
        pub fn commandMenus(self: *const Self, allocator: std.mem.Allocator, context: *Context) ![]const mod.CommandMenu {
            const titles = self.titlesFor(true);
            const menus = try allocator.alloc(mod.CommandMenu, titles.len);
            for (menus, titles) |*menu, title| {
                var items: std.ArrayList(mod.CommandItem) = .empty;
                for (self.entries) |*entry| {
                    if (!std.mem.eql(u8, entry.menu, title) or !entry.shows(true)) continue;
                    if (entry.title.len == 0) {
                        try items.append(allocator, .{});
                        continue;
                    }
                    const shown = if (entry.hint.len > 0 and entry.shortcut.len == 0) try allocator.print("{s}    {s}", .{ entry.title, entry.hint }) else entry.title;
                    const choice = try allocator.create(Choice);
                    choice.* = .{ .table = self, .context = context, .entry = entry };
                    try items.append(allocator, .{
                        .title = try allocator.dupeSentinel(u8, shown, 0),
                        .key = entry.shortcut,
                        .action = mod.Callback.init(Choice, choice, Choice.fire),
                    });
                }
                menu.* = .{ .title = try allocator.dupeSentinel(u8, title, 0), .items = try items.toOwnedSlice(allocator) };
            }
            return menus;
        }

        /// Whether every entry shown on a system belongs to one of that system's menus: an app's tests call it.
        ///
        /// - `self`: the table.
        /// - Returns: true when none is orphaned.
        pub fn wellFormed(self: *const Self) bool {
            for (self.entries) |entry| {
                for ([_]bool{ true, false }) |mac| {
                    if (!entry.shows(mac)) continue;
                    var known = false;
                    for (self.titlesFor(mac)) |title| known = known or std.mem.eql(u8, title, entry.menu);
                    if (!known) return false;
                }
            }
            return true;
        }
    };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(TestMenus.Table);
}

/// A small app's menus, for the tests.
const TestMenus = struct {
    const Self = @This();

    /// What the test app's entries do.
    const Action = enum { open, refresh, quit };
    /// The test app: what was done last.
    const App = struct {
        /// The last action performed.
        last: ?Action = null,
    };
    /// The table type.
    const Table = MenuTable(App, Action);

    /// Notes the action.
    ///
    /// - `app`: the test app.
    /// - `action`: what the entry does.
    fn perform(app: *App, action: Action) void {
        app.last = action;
    }

    /// The table.
    const table = Table{
        .entries = &.{
            .{ .menu = "File", .title = "Open…", .shortcut = "o", .does = .open },
            .{ .menu = "File", .only = .other },
            .{ .menu = "File", .title = "Quit", .shortcut = "q", .does = .quit, .only = .other },
            .{ .menu = "Go", .title = "Refresh", .hint = "r", .does = .refresh },
        },
        .mac_titles = &.{ "File", "Go" },
        .other_titles = &.{ "File", "Go" },
        .width = 200,
        .perform = perform,
    };
};

test "menu table builds both menu bars from one table, and routes a choice to the app's action" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var app: TestMenus.App = .{};
    try std.testing.expect(TestMenus.table.wellFormed());

    // Off macOS: Quit and its separator show; the hint becomes the key text.
    const drawn = try TestMenus.table.barMenus(allocator, &app, false);
    try std.testing.expectEqual(@as(usize, 3), drawn[0].items.len);
    try std.testing.expectEqualStrings("ctrl+O", drawn[0].items[0].key_text);
    try std.testing.expectEqualStrings("r", drawn[1].items[0].key_text);
    drawn[1].items[0].action.?.call();
    try std.testing.expectEqual(@as(?TestMenus.Action, .refresh), app.last);

    // On macOS: no Quit (the application menu has it); a hint with no ⌘ shortcut goes beside the title.
    const native = try TestMenus.table.commandMenus(allocator, &app);
    try std.testing.expectEqual(@as(usize, 1), native[0].items.len);
    try std.testing.expectEqualStrings("Refresh    r", native[1].items[0].title);
    native[0].items[0].action.?.call();
    try std.testing.expectEqual(@as(?TestMenus.Action, .open), app.last);

    // Ctrl+Q off macOS; ⌘Q on macOS is the application menu's, not the table's.
    try std.testing.expect(TestMenus.table.chooseShortcut(&app, 'q', false));
    try std.testing.expectEqual(@as(?TestMenus.Action, .quit), app.last);
    try std.testing.expect(!TestMenus.table.chooseShortcut(&app, 'q', true));
    try std.testing.expect(TestMenus.table.find("Open…") != null);
}
