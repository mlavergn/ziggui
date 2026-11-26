//! A find's matches and what they were found for, shared by `TextFindState`
//! (a document's ranges) and `DiffFindState` (a diff's rows): the list,
//! kept until what was searched, the query or the options change; the
//! search that fills it, stopping at `limit`; and which query a match was
//! last chosen for, so typing finds as it goes.

const std = @import("std");
const log = std.log.scoped(.ziggui_find_matches);
const mod = @import("module.zig");

/// What a find's matches were found for.
pub const FindMatchesKey = struct {
    const Self = @This();

    /// What was searched: a document's address, a diff's key.
    source: u64,
    /// Which version of it: a document's revision (0 for a diff, whose key
    /// names its rows already).
    version: u64 = 0,
    /// The query's revision.
    query: u64,
    /// How the query matched.
    options: mod.TextSearchOptions,

    /// Whether two keys name the same search.
    ///
    /// - `self`: the key.
    /// - `other`: the other key.
    /// - Returns: true when every part agrees.
    pub fn eql(self: *const Self, other: Self) bool {
        return self.source == other.source and self.version == other.version and self.query == other.query and std.meta.eql(self.options, other.options);
    }
};

/// The matches of a find whose match type is `Match`.
///
/// - `Match`: one match (`TextRange`, `DiffMatch`).
/// - Returns: the type.
pub fn FindMatches(comptime Match: type) type {
    return struct {
        const Self = @This();

        /// The most matches kept, counted and marked; past it `more` is set.
        pub const limit: usize = 10_000;

        /// Where the list grows.
        allocator: std.mem.Allocator,
        /// The matches, in order.
        items: std.ArrayList(Match) = .empty,
        /// Whether the list stopped at `limit` (or could not grow).
        more: bool = false,
        /// What `items` was found for; null before the first search.
        key: ?FindMatchesKey = null,
        /// The query's revision a match was last chosen for.
        followed_query: u64 = 0,

        /// No matches yet, none searched for.
        ///
        /// - `allocator`: where the list grows.
        /// - Returns: the matches.
        pub fn init(allocator: std.mem.Allocator) Self {
            log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
            const self = Self{ .allocator = allocator };
            return self;
        }

        /// Frees the list.
        ///
        /// - `self`: the matches.
        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        /// Whether the list is `key`'s; when it is not, empties it and takes
        /// `key`, for the caller to fill with `collect`.
        ///
        /// - `self`: the matches.
        /// - `key`: what the caller searches now.
        /// - Returns: true when the list is already `key`'s.
        pub fn holds(self: *Self, key: FindMatchesKey) bool {
            if (self.key) |held| {
                if (held.eql(key)) return true;
            }
            self.items.clearRetainingCapacity();
            self.more = false;
            self.key = key;
            return false;
        }

        /// Searches `text` for `query`, appending each match as `make(range, tag)`.
        ///
        /// - `self`: the matches.
        /// - `text`: what is searched.
        /// - `query`: what is looked for; empty finds nothing.
        /// - `options`: how it matches.
        /// - `tag`: handed to `make` (a diff's row).
        /// - `make`: the match a range in `text` is.
        /// - Returns: false once the list is full or could not grow (`more`
        ///   is then set): the caller searches no further.
        pub fn collect(self: *Self, text: []const u8, query: []const u8, options: mod.TextSearchOptions, tag: usize, comptime make: fn (range: mod.TextRange, tag: usize) Match) bool {
            const search = mod.TextSearch.init(text, query, options);
            var from: usize = 0;
            while (search.next(from)) |range| {
                if (self.items.items.len == limit) {
                    self.more = true;
                    return false;
                }
                self.items.append(self.allocator, make(range, tag)) catch |err| {
                    log.warn("matches cut short: {s}", .{@errorName(err)});
                    self.more = true;
                    return false;
                };
                from = range.end;
            }
            return true;
        }

        /// Whether the query changed since a match was last chosen for it,
        /// noting it as chosen: a find follows the query as it is typed.
        ///
        /// - `self`: the matches.
        /// - `revision`: the query's revision now.
        /// - Returns: true once per change.
        pub fn takeQueryChange(self: *Self, revision: u64) bool {
            if (revision == self.followed_query) return false;
            self.followed_query = revision;
            return true;
        }

        /// The bar's count over the list.
        ///
        /// - `self`: the matches.
        /// - `current`: the current match's index, if any.
        /// - Returns: the count.
        pub fn count(self: *const Self, current: ?usize) mod.FindCount {
            return .{ .current = current, .total = self.items.items.len, .more = self.more };
        }
    };
}

// -----------------------------------------------------------------------------
// Unit Tests

/// The match a range is, for the tests: the range itself.
const RangeMatch = struct {
    const Self = @This();

    /// The range.
    ///
    /// - `range`: the range found.
    /// - `tag`: ignored.
    /// - Returns: the range.
    fn of(range: mod.TextRange, tag: usize) mod.TextRange {
        _ = tag;
        return range;
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "find matches: kept for their key, found again for another, and stopped at the limit" {
    const allocator = std.testing.allocator;
    var found = FindMatches(mod.TextRange).init(allocator);
    defer found.deinit();
    const key: FindMatchesKey = .{ .source = 1, .version = 7, .query = 3, .options = .{} };
    try std.testing.expect(!found.holds(key));
    try std.testing.expect(found.collect("a b a", "a", .{}, 0, RangeMatch.of));
    try std.testing.expectEqual(@as(usize, 2), found.items.items.len);
    try std.testing.expect(found.holds(key));
    try std.testing.expectEqual(mod.FindCount{ .current = 1, .total = 2 }, found.count(1));
    // Another version: emptied, for the caller to fill.
    try std.testing.expect(!found.holds(.{ .source = 1, .version = 8, .query = 3, .options = .{} }));
    try std.testing.expectEqual(@as(usize, 0), found.items.items.len);
    try std.testing.expect(found.collect("", "a", .{}, 0, RangeMatch.of));
    // The limit.
    const many = try allocator.alloc(u8, FindMatches(mod.TextRange).limit + 5);
    defer allocator.free(many);
    @memset(many, 'x');
    try std.testing.expect(!found.collect(many, "x", .{}, 0, RangeMatch.of));
    try std.testing.expect(found.more);
    try std.testing.expectEqual(FindMatches(mod.TextRange).limit, found.items.items.len);
}

test "find matches: a query change is taken once" {
    var found = FindMatches(mod.TextRange).init(std.testing.allocator);
    defer found.deinit();
    try std.testing.expect(found.takeQueryChange(4));
    try std.testing.expect(!found.takeQueryChange(4));
    try std.testing.expect(found.takeQueryChange(5));
}
