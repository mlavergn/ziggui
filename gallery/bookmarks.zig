//! The Web View panel's saved sites, kept in memory: a gallery keeps no
//! files, so they last as long as the window.
//!
//! An app that keeps them on disk reads and writes the list as ZON (a
//! struct with a `bookmarks` list of `.{ .title, .url }`, which a user can
//! edit by hand) through `std.Io`, with `readZon` and `writeZon`:
//!
//! ```zig
//! // Load: a missing file is an empty list; one that will not parse is left
//! // as it is (`readZon` returns `error.ParseZon` and keeps the list).
//! const source = std.Io.Dir.cwd().readFileAllocOptions(io, path, allocator, .limited(1 << 20), .of(u8), 0) catch |err| switch (err) {
//!     error.FileNotFound => return,
//!     else => return err,
//! };
//! defer allocator.free(source);
//! try bookmarks.readZon(source);
//!
//! // Save after each change, through an atomic replace, so a crash
//! // mid-write leaves the old file whole.
//! var text: std.Io.Writer.Allocating = .init(allocator);
//! defer text.deinit();
//! try bookmarks.writeZon(&text.writer);
//! var file = try std.Io.Dir.cwd().createFileAtomic(io, path, .{ .make_path = true, .replace = true });
//! defer file.deinit(io);
//! try file.file.writeStreamingAll(io, text.written());
//! try file.replace(io);
//! ```
//!
//! Ported from zigwebview's browser shell, which kept them in
//! `~/.config/zwebview/bookmarks.zon` this way.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_bookmarks);
const gallery = @import("module.zig");

/// A site the user saved: what to call it and where it is.
pub const Bookmark = struct {
    const Self = @This();

    /// The name shown in the Bookmarks menu: the page's title when it was saved.
    title: []const u8,

    /// The address the bookmark loads.
    url: []const u8,
};

/// The ZON document's shape: one struct, so a later field can join without
/// breaking the files already written.
const BookmarksFile = struct {
    const Self = @This();

    /// The saved sites, in the order they were added.
    bookmarks: []const Bookmark = &.{},
};

/// The saved sites, in memory; `readZon` and `writeZon` move them to and
/// from ZON for an app that keeps them on disk.
pub const Bookmarks = struct {
    const Self = @This();

    /// Owns the list and every title and address.
    allocator: std.mem.Allocator,

    /// The saved sites, in the order they were added; each string owned.
    items: std.ArrayList(Bookmark) = .empty,

    /// An empty list.
    ///
    /// - `allocator`: owns the list and its strings.
    /// - Returns: the list.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Frees the list and its strings.
    ///
    /// - `self`: the list.
    pub fn deinit(self: *Self) void {
        for (self.items.items) |bookmark| self.freeBookmark(bookmark);
        self.items.deinit(self.allocator);
    }

    /// Saves a site, unless its address is saved already.
    ///
    /// - `self`: the list.
    /// - `title`: what to call it.
    /// - `url`: its address.
    /// - Returns: nothing; propagates allocation failure.
    pub fn add(self: *Self, title: []const u8, url: []const u8) std.mem.Allocator.Error!void {
        if (self.contains(url)) return;
        try self.append(title, url);
    }

    /// Forgets the site at `url`, if saved.
    ///
    /// - `self`: the list.
    /// - `url`: its address.
    pub fn remove(self: *Self, url: []const u8) void {
        const index = self.indexOf(url) orelse return;
        self.freeBookmark(self.items.orderedRemove(index));
    }

    /// Reports whether a site is saved.
    ///
    /// - `self`: the list.
    /// - `url`: its address.
    /// - Returns: true when a bookmark has that address.
    pub fn contains(self: *const Self, url: []const u8) bool {
        return self.indexOf(url) != null;
    }

    /// The saved sites, in the order they were added.
    ///
    /// - `self`: the list.
    /// - Returns: the bookmarks, valid until the list next changes.
    pub fn list(self: *const Self) []const Bookmark {
        return self.items.items;
    }

    /// Replaces the list with what a ZON document holds (see the file's
    /// header), every entry as written; one that will not parse leaves the
    /// list as it was.
    ///
    /// - `self`: the list.
    /// - `source`: the document.
    /// - Returns: nothing; fails with `error.ParseZon` (logged, with where) for a
    ///   document that is not a bookmarks list, and propagates allocation failure.
    pub fn readZon(self: *Self, source: [:0]const u8) (std.mem.Allocator.Error || error{ParseZon})!void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var diagnostics: std.zon.parse.Diagnostics = undefined;
        const file = std.zon.parse.fromSlice(BookmarksFile, .{
            .gpa = self.allocator,
            .arena = arena.allocator(),
            .source = source,
            .diagnostics = &diagnostics,
            .ignore_unknown_fields = true,
        }) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ParseZon => {
                log.warn("{f}", .{diagnostics.fmt("bookmarks")});
                return err;
            },
        };
        var replacement: Self = .init(self.allocator);
        errdefer replacement.deinit();
        // Every entry as written, duplicates too: a hand-edited file loses
        // nothing on the next save.
        for (file.bookmarks) |bookmark| try replacement.append(bookmark.title, bookmark.url);
        self.deinit();
        self.* = replacement;
    }

    /// Writes the list as a ZON document (see the file's header), one
    /// bookmark a line, for whoever edits the file by hand.
    ///
    /// - `self`: the list.
    /// - `writer`: where the document goes.
    /// - Returns: nothing; propagates write failure.
    pub fn writeZon(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var serializer: std.zon.Serializer = .{ .writer = writer };
        var document = try serializer.beginStruct(.{});
        var list_field = try document.beginTupleField("bookmarks", .{});
        for (self.items.items) |bookmark| try list_field.field(bookmark, .{});
        try list_field.end();
        try document.end();
        try writer.writeByte('\n');
    }

    /// Appends a copy of a bookmark.
    ///
    /// - `self`: the list.
    /// - `title`: what to call it.
    /// - `url`: its address.
    /// - Returns: nothing; propagates allocation failure.
    fn append(self: *Self, title: []const u8, url: []const u8) std.mem.Allocator.Error!void {
        const owned_title = try self.allocator.dupe(u8, title);
        errdefer self.allocator.free(owned_title);
        const owned_url = try self.allocator.dupe(u8, url);
        errdefer self.allocator.free(owned_url);
        try self.items.append(self.allocator, .{ .title = owned_title, .url = owned_url });
    }

    /// Where a site sits in the list.
    ///
    /// - `self`: the list.
    /// - `url`: its address.
    /// - Returns: its index, or null when it is not saved.
    fn indexOf(self: *const Self, url: []const u8) ?usize {
        for (self.items.items, 0..) |bookmark, index| {
            if (std.mem.eql(u8, bookmark.url, url)) return index;
        }
        return null;
    }

    /// Frees a bookmark's strings.
    ///
    /// - `self`: the list whose allocator owns them.
    /// - `bookmark`: the bookmark.
    fn freeBookmark(self: *const Self, bookmark: Bookmark) void {
        self.allocator.free(bookmark.title);
        self.allocator.free(bookmark.url);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    _ = gallery;
}

test "bookmarks save a site once, find it and forget it" {
    var bookmarks = Bookmarks.init(std.testing.allocator);
    defer bookmarks.deinit();
    try bookmarks.add("Zig", "https://ziglang.org/");
    try bookmarks.add("Zig again", "https://ziglang.org/");
    try bookmarks.add("Docs", "https://ziglang.org/documentation/");
    try std.testing.expectEqual(@as(usize, 2), bookmarks.list().len);
    try std.testing.expect(bookmarks.contains("https://ziglang.org/"));
    bookmarks.remove("https://ziglang.org/");
    try std.testing.expect(!bookmarks.contains("https://ziglang.org/"));
    try std.testing.expectEqualStrings("Docs", bookmarks.list()[0].title);
}

test "bookmarks go to ZON and back, as the header's disk example does" {
    const allocator = std.testing.allocator;
    var bookmarks = Bookmarks.init(allocator);
    defer bookmarks.deinit();
    try bookmarks.add("Zig", "https://ziglang.org/");
    try bookmarks.add("A \"quoted\" title", "https://example.com/?a=1");

    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try bookmarks.writeZon(&text.writer);
    const source = try allocator.dupeSentinel(u8, text.written(), 0);
    defer allocator.free(source);

    var read_back = Bookmarks.init(allocator);
    defer read_back.deinit();
    try read_back.readZon(source);
    try std.testing.expectEqual(@as(usize, 2), read_back.list().len);
    try std.testing.expectEqualStrings("A \"quoted\" title", read_back.list()[1].title);
    try std.testing.expectEqualStrings("https://example.com/?a=1", read_back.list()[1].url);
}

test "bookmarks read every entry a document holds, duplicates too" {
    var bookmarks = Bookmarks.init(std.testing.allocator);
    defer bookmarks.deinit();
    try bookmarks.readZon(".{ .bookmarks = .{ .{ .title = \"A\", .url = \"https://a/\" }, .{ .title = \"A again\", .url = \"https://a/\" } } }");
    try std.testing.expectEqual(@as(usize, 2), bookmarks.list().len);
}

test "bookmarks refuse ZON that will not parse and keep what they had" {
    var bookmarks = Bookmarks.init(std.testing.allocator);
    defer bookmarks.deinit();
    try bookmarks.add("Zig", "https://ziglang.org/");
    try std.testing.expectError(error.ParseZon, bookmarks.readZon(".{ .bookmarks = .{ .{ .title = 1 } } }"));
    try std.testing.expectEqual(@as(usize, 1), bookmarks.list().len);
}
