//! The gallery sidebar's search: the field over the list, and the sections
//! it keeps, those whose label or components (`Section.names`) hold what was
//! typed, each with what matched.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_section_search);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// One section the search keeps, and what in it matched.
pub const SectionMatch = struct {
    const Self = @This();

    /// The section.
    section: gallery.Section,
    /// What matched, shown under its row (a component, `"ziggui.WebView"`);
    /// null with nothing typed, the whole list showing.
    detail: ?[]const u8 = null,
};

/// The sidebar's search field and the rows it leaves. With nothing typed the
/// rows are every section in sidebar order; with a query, the sections one of
/// whose components (a caption's names, split at ` · `) holds it, case aside,
/// that component their detail, else whose label does, their first component
/// their detail, so every row of a search is two lines tall.
pub const SectionSearch = struct {
    const Self = @This();

    /// The separator between the names on a caption.
    const separator = " · ";

    /// What is typed.
    field: ziggui.TextFieldState,

    /// The rows the list shows, in sidebar order; the first `row_count` are set.
    rows: [gallery.Section.sorted.len]SectionMatch = undefined,

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

    /// Where a section is among the rows.
    ///
    /// - `self`: the search.
    /// - `section`: the section.
    /// - Returns: its row, or null when the search leaves it out.
    pub fn rowOf(self: *const Self, section: gallery.Section) ?usize {
        for (self.shown(), 0..) |row, index| {
            if (row.section == section) return index;
        }
        return null;
    }

    /// A hash of the rows as shown: what the list looks like, so a scroll into
    /// view waits for the list it measures to be the one painted.
    ///
    /// - `self`: the search.
    /// - Returns: the hash.
    pub fn layoutKey(self: *const Self) u64 {
        var hasher = std.hash.Wyhash.init(0);
        for (self.shown()) |row| {
            hasher.update(&[_]u8{ @intCast(@backingInt(row.section)), @intFromBool(row.detail != null) });
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
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(SectionSearch);
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
