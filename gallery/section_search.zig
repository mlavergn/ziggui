//! The gallery sidebar's search: the field over the list, and the rows it
//! keeps. The list shows the sections by label, or every component the cards
//! name (`ziggui.Table`, each with its section under it); what is typed
//! keeps the sections whose label or components (`Section.names`) hold it, or
//! the components whose name does.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_section_search);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// What the sidebar lists.
pub const SidebarListing = enum {
    const Self = @This();

    /// The sections, by label.
    sections,
    /// Every component the cards name, alphabetically.
    components,
};

/// One component the cards name (`ziggui.Table`), and the section its
/// row shows.
pub const SidebarComponent = struct {
    const Self = @This();

    /// The component's name, as its card names it.
    name: []const u8,
    /// The section that shows it: the first, in the gallery's order, whose
    /// names line leads with it, else the first that names it.
    section: gallery.Section,
};

/// One row the search keeps: a section, or a component in its section.
pub const SectionMatch = struct {
    const Self = @This();

    /// The section the row shows.
    section: gallery.Section,
    /// The component the row lists, in the components listing; null in the
    /// sections listing.
    component: ?[]const u8 = null,
    /// What shows under the row: in the sections listing what matched (a
    /// component, `"ziggui.WebView"`), null with nothing typed; in the
    /// components listing, the section's label.
    detail: ?[]const u8 = null,
};

/// The sidebar's search field and the rows it leaves. Listing sections, with
/// nothing typed the rows are every section in sidebar order; with a query,
/// the sections one of whose components (a caption's names, split at ` · `)
/// holds it, case aside, that component their detail, else whose label does,
/// their first component their detail, so every row of a search is two
/// lines tall. Listing components, the rows are every `ziggui.` name the
/// cards show (`components`), alphabetically, those holding the query with
/// one, each its section's label under it.
pub const SectionSearch = struct {
    const Self = @This();

    /// The separator between the names on a caption.
    const separator = " · ";

    /// Every component the cards name, alphabetically, case aside, each with
    /// the section that shows it; made at compile time from `Section.names`.
    pub const components: []const SidebarComponent = Self.catalog();

    /// What is typed.
    field: ziggui.TextFieldState,

    /// What the list shows: the sections or the components.
    listing: SidebarListing = .sections,

    /// The component row last chosen, so a section with several components
    /// keeps the one tapped or stepped to selected; null for none.
    chosen: ?[]const u8 = null,

    /// The rows the list shows, in sidebar order; the first `row_count` are set.
    rows: [@max(gallery.Section.sorted.len, components.len)]SectionMatch = undefined,

    /// How many of `rows` the list shows.
    row_count: usize = 0,

    /// The field's revision the rows were made for, so a change is noticed once.
    revision: u64 = 0,

    /// Constructs an empty search: every section shows.
    ///
    /// - `allocator`: owns the field's text.
    /// - Returns: the search.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        var self = Self{ .field = ziggui.TextFieldState.init(allocator) };
        self.collect();
        self.revision = self.field.revision;
        return self;
    }

    /// Releases the field; it leaves the focus as it goes.
    ///
    /// - `self`: the search.
    pub fn deinit(self: *Self) void {
        self.field.deinit();
    }

    /// What is searched for: the field's text without spaces around it.
    ///
    /// - `self`: the search.
    /// - Returns: the query, empty when nothing is typed.
    pub fn query(self: *const Self) []const u8 {
        return std.mem.trim(u8, self.field.text(), " \t");
    }

    /// Makes the rows again if the field changed since they were made.
    ///
    /// - `self`: the search.
    /// - Returns: true when it changed.
    pub fn refresh(self: *Self) bool {
        if (self.field.revision == self.revision) return false;
        self.revision = self.field.revision;
        self.collect();
        return true;
    }

    /// The rows the list shows.
    ///
    /// - `self`: the search.
    /// - Returns: the rows, in sidebar order.
    pub fn shown(self: *const Self) []const SectionMatch {
        return self.rows[0..self.row_count];
    }

    /// Where a section is among the rows: listing components, the row last
    /// chosen when it is the section's, else the section's first.
    ///
    /// - `self`: the search.
    /// - `section`: the section.
    /// - Returns: its row, or null when the search leaves it out.
    pub fn rowOf(self: *const Self, section: gallery.Section) ?usize {
        if (self.chosen) |name| {
            for (self.shown(), 0..) |row, index| {
                const component = row.component orelse continue;
                if (row.section == section and std.mem.eql(u8, component, name)) return index;
            }
        }
        for (self.shown(), 0..) |row, index| {
            if (row.section == section) return index;
        }
        return null;
    }

    /// Notes the row a tap or a key reached, so it stays the selected one of
    /// its section's rows (`rowOf`).
    ///
    /// - `self`: the search.
    /// - `row`: the row, among those shown.
    pub fn choose(self: *Self, row: usize) void {
        if (row >= self.row_count) return;
        self.chosen = self.rows[row].component;
    }

    /// Lists the sections or the components, keeping what is typed.
    ///
    /// - `self`: the search.
    /// - `listing`: what to list.
    /// - Returns: true when it changed.
    pub fn setListing(self: *Self, listing: SidebarListing) bool {
        if (self.listing == listing) return false;
        self.listing = listing;
        self.chosen = null;
        self.collect();
        return true;
    }

    /// A hash of the rows as shown: what the list looks like, so a scroll into
    /// view waits for the list it measures to be the one painted.
    ///
    /// - `self`: the search.
    /// - Returns: the hash.
    pub fn layoutKey(self: *const Self) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(&[_]u8{@backingInt(self.listing)});
        for (self.shown()) |row| {
            hasher.update(&[_]u8{ @intCast(@backingInt(row.section)), @intFromBool(row.detail != null) });
            if (row.component) |name| hasher.update(name);
        }
        return hasher.final();
    }

    /// Empties the field: every section shows again.
    ///
    /// - `self`: the search.
    pub fn clear(self: *Self) void {
        self.field.setText("") catch |err| log.warn("search not cleared: {s}", .{@errorName(err)});
    }

    /// Makes the rows for the query.
    ///
    /// - `self`: the search.
    fn collect(self: *Self) void {
        const needle = self.query();
        self.row_count = 0;
        if (self.listing == .components) {
            for (components) |entry| {
                if (needle.len > 0 and std.ascii.findIgnoreCase(entry.name, needle) == null) continue;
                self.rows[self.row_count] = .{ .section = entry.section, .component = entry.name, .detail = entry.section.label() };
                self.row_count += 1;
            }
            return;
        }
        for (gallery.Section.sorted) |section| {
            if (needle.len == 0) {
                self.rows[self.row_count] = .{ .section = section };
                self.row_count += 1;
                continue;
            }
            const detail = Self.matchIn(section, needle) orelse continue;
            self.rows[self.row_count] = .{ .section = section, .detail = detail };
            self.row_count += 1;
        }
    }

    /// What in a section holds the query: the first of its components that
    /// does, else its first component when its label does.
    ///
    /// - `section`: the section.
    /// - `needle`: the query, not empty.
    /// - Returns: the component to show under its row, or null when nothing matches.
    fn matchIn(section: gallery.Section, needle: []const u8) ?[]const u8 {
        const lines = section.names();
        for (lines) |line| {
            var names = std.mem.splitSequence(u8, line, separator);
            while (names.next()) |name| {
                if (std.ascii.findIgnoreCase(name, needle) != null) return name;
            }
        }
        if (std.ascii.findIgnoreCase(section.label(), needle) == null) return null;
        // A section with no names yet shows its label under itself.
        if (lines.len == 0) return section.label();
        var first = std.mem.splitSequence(u8, lines[0], separator);
        return first.next();
    }

    /// Makes `components` at compile time: each `ziggui.` name on a names
    /// line, once, with the first section (in the gallery's order) whose line
    /// leads with it, else the first that names it, sorted by name, case aside.
    ///
    /// - Returns: the components.
    fn catalog() []const SidebarComponent {
        comptime {
            @setEvalBranchQuota(2_000_000);
            var found: []const SidebarComponent = &.{};
            var leads: []const bool = &.{};
            for (std.enums.values(gallery.Section)) |section| {
                for (section.names()) |line| {
                    var names = std.mem.splitSequence(u8, line, separator);
                    var first = true;
                    while (names.next()) |name| : (first = false) {
                        if (!std.mem.startsWith(u8, name, "ziggui.")) continue;
                        const known = for (found, 0..) |entry, index| {
                            if (std.mem.eql(u8, entry.name, name)) break @as(?usize, index);
                        } else null;
                        if (known) |index| {
                            // A later section that leads with it wins over one that only names it.
                            if (first and !leads[index]) {
                                var moved = found[0..found.len].*;
                                moved[index].section = section;
                                found = &moved;
                                var led = leads[0..leads.len].*;
                                led[index] = true;
                                leads = &led;
                            }
                            continue;
                        }
                        found = found ++ .{SidebarComponent{ .name = name, .section = section }};
                        leads = leads ++ .{first};
                    }
                }
            }
            // Insertion sort by name, case aside.
            var sorted = found[0..found.len].*;
            for (1..sorted.len) |index| {
                var at = index;
                while (at > 0 and std.ascii.lessThanIgnoreCase(sorted[at].name, sorted[at - 1].name)) : (at -= 1) {
                    const swap = sorted[at];
                    sorted[at] = sorted[at - 1];
                    sorted[at - 1] = swap;
                }
            }
            const result = sorted;
            return &result;
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(SectionSearch);
}

test "the components listing names every ziggui component once, alphabetically, each with its section" {
    const components = SectionSearch.components;
    try std.testing.expect(components.len > 100);
    for (components, 0..) |entry, index| {
        try std.testing.expect(std.mem.startsWith(u8, entry.name, "ziggui."));
        if (index > 0) try std.testing.expect(std.ascii.lessThanIgnoreCase(components[index - 1].name, entry.name));
    }
    // Led by a card in Images & Drawing, and in Windows too: the first section wins.
    for (components) |entry| {
        if (std.mem.eql(u8, entry.name, "ziggui.Canvas")) try std.testing.expectEqual(gallery.Section.images, entry.section);
        if (std.mem.eql(u8, entry.name, "ziggui.Table")) try std.testing.expectEqual(gallery.Section.table, entry.section);
        if (std.mem.eql(u8, entry.name, "ziggui.Toggle")) try std.testing.expectEqual(gallery.Section.controls, entry.section);
    }

    var search = SectionSearch.init(std.testing.allocator);
    defer search.deinit();
    try std.testing.expect(search.setListing(.components));
    try std.testing.expect(!search.setListing(.components));
    try std.testing.expectEqual(components.len, search.shown().len);
    try std.testing.expectEqualStrings(components[0].name, search.shown()[0].component.?);
    try std.testing.expectEqualStrings(components[0].section.label(), search.shown()[0].detail.?);

    // A query keeps the components whose name holds it, case aside.
    try search.field.setText("TABLE");
    _ = search.refresh();
    try std.testing.expect(search.shown().len >= 3);
    for (search.shown()) |row| try std.testing.expect(std.ascii.findIgnoreCase(row.component.?, "table") != null);

    // Of a section's rows, the one chosen stays its row.
    search.clear();
    _ = search.refresh();
    var second: ?usize = null;
    var first: ?usize = null;
    for (search.shown(), 0..) |row, index| {
        if (row.section != gallery.Section.lists) continue;
        if (first == null) first = index else if (second == null) second = index;
    }
    try std.testing.expectEqual(first, search.rowOf(gallery.Section.lists));
    search.choose(second.?);
    try std.testing.expectEqual(second, search.rowOf(gallery.Section.lists));

    // Back to the sections, every one shows again.
    try std.testing.expect(search.setListing(.sections));
    try std.testing.expectEqual(gallery.Section.sorted.len, search.shown().len);
}

test "a search keeps the sections whose components or label hold the query, case aside" {
    var search = SectionSearch.init(std.testing.allocator);
    defer search.deinit();
    try std.testing.expectEqual(gallery.Section.sorted.len, search.shown().len);
    try std.testing.expect(search.shown()[0].detail == null);

    // A component, with or without its prefix, in any case.
    for ([_][]const u8{ "ziggui.WebView", "webview", "  WEBVIEW " }) |typed| {
        try search.field.setText(typed);
        try std.testing.expect(search.refresh());
        try std.testing.expectEqual(@as(usize, 1), search.shown().len);
        try std.testing.expectEqual(gallery.Section.mediaWeb, search.shown()[0].section);
        try std.testing.expectEqualStrings("ziggui.WebView", search.shown()[0].detail.?);
    }
    // Unchanged, nothing to make again.
    try std.testing.expect(!search.refresh());

    // A label alone: its first component goes under it.
    try search.field.setText("presentations");
    _ = search.refresh();
    try std.testing.expectEqual(@as(usize, 1), search.shown().len);
    try std.testing.expectEqual(gallery.Section.presentations, search.shown()[0].section);
    try std.testing.expectEqualStrings(".sheet", search.shown()[0].detail.?);

    // Nothing matches; then cleared, everything shows again.
    try search.field.setText("no such component");
    _ = search.refresh();
    try std.testing.expectEqual(@as(usize, 0), search.shown().len);
    search.clear();
    _ = search.refresh();
    try std.testing.expectEqual(gallery.Section.sorted.len, search.shown().len);
    try std.testing.expectEqual(@as(?usize, 0), search.rowOf(gallery.Section.sorted[0]));
}
