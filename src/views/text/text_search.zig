//! Plain-text search over a buffer: every match of a query, optionally
//! ignoring case and only whole words, as byte ranges a find highlights.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_search);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// How a search matches.
pub const TextSearchOptions = struct {
    const Self = @This();

    /// Whether letters must match in case ("Aa").
    case_sensitive: bool = false,

    /// Whether a match must be a whole word: no letter, digit, `_` or
    /// non-ASCII character just before or after it.
    whole_word: bool = false,
};

/// Finds a query in a text. Case folding covers ASCII, Latin-1, Latin
/// Extended-A, Greek and Cyrillic letters (simple one-to-one folds); other
/// scripts match as written. A byte that does not decode matches only itself.
pub const TextSearch = struct {
    const Self = @This();

    /// The text searched.
    text: []const u8,

    /// What is looked for.
    query: []const u8,

    /// How it matches.
    options: TextSearchOptions,

    /// A search of `text` for `query`.
    ///
    /// - `text`: the text searched.
    /// - `query`: what is looked for.
    /// - `options`: how it matches.
    /// - Returns: the search.
    pub fn init(text: []const u8, query: []const u8, options: TextSearchOptions) Self {
        const self = Self{ .text = text, .query = query, .options = options };
        return self;
    }

    /// The first match starting at or after a byte.
    ///
    /// - `self`: the search.
    /// - `from`: the byte to start at.
    /// - Returns: the match, or null when there is none (or the query is empty).
    pub fn next(self: *const Self, from: usize) ?mod.TextRange {
        if (self.query.len == 0) return null;
        const lines = mod.TextLines.init(self.text);
        var at = @min(from, self.text.len);
        while (at < self.text.len) {
            if (self.options.case_sensitive) {
                const index = std.mem.findPos(u8, self.text, at, self.query) orelse return null;
                const range: mod.TextRange = .{ .start = index, .end = index + self.query.len };
                if (self.accepts(range)) return range;
                at = lines.nextCodepointEnd(index);
                continue;
            }
            if (self.foldedMatchAt(at)) |stop| {
                const range: mod.TextRange = .{ .start = at, .end = stop };
                if (self.accepts(range)) return range;
            }
            at = lines.nextCodepointEnd(at);
        }
        return null;
    }

    /// Every match, each found past the one before it.
    ///
    /// - `self`: the search.
    /// - `allocator`: where the list goes.
    /// - `limit`: the most matches to find.
    /// - Returns: the matches, owned; propagates allocation failure.
    pub fn allAlloc(self: *const Self, allocator: std.mem.Allocator, limit: usize) std.mem.Allocator.Error![]mod.TextRange {
        var found: std.ArrayList(mod.TextRange) = .empty;
        errdefer found.deinit(allocator);
        var from: usize = 0;
        while (found.items.len < limit) {
            const range = self.next(from) orelse break;
            try found.append(allocator, range);
            from = range.end;
        }
        return found.toOwnedSlice(allocator);
    }

    /// Whether a byte belongs to a word, as the whole-word option reads it.
    ///
    /// - `byte`: the byte.
    /// - Returns: true for letters, digits, `_` and any non-ASCII byte.
    pub fn isWordByte(byte: u8) bool {
        return byte >= 0x80 or std.ascii.isAlphanumeric(byte) or byte == '_';
    }

    /// A codepoint's simple lowercase fold.
    ///
    /// - `codepoint`: the codepoint.
    /// - Returns: its fold, or itself where none is known.
    pub fn fold(codepoint: u21) u21 {
        return switch (codepoint) {
            'A'...'Z' => codepoint + 32,
            // Latin-1, less × (U+00D7).
            0xC0...0xD6, 0xD8...0xDE => codepoint + 32,
            // Latin Extended-A: pairs of upper then lower, but for the odd runs.
            0x100...0x12F, 0x132...0x137, 0x14A...0x177 => codepoint | 1,
            0x139...0x148, 0x179...0x17E => if (codepoint % 2 == 1) codepoint + 1 else codepoint,
            // Greek, less the gap at U+03A2.
            0x391...0x3A1, 0x3A3...0x3AB => codepoint + 32,
            // Cyrillic.
            0x400...0x40F => codepoint + 80,
            0x410...0x42F => codepoint + 32,
            else => codepoint,
        };
    }

    /// Whether a match stands as the options want (whole words only, when asked).
    ///
    /// - `self`: the search.
    /// - `range`: the match.
    /// - Returns: true when it counts.
    fn accepts(self: *const Self, range: mod.TextRange) bool {
        if (!self.options.whole_word) return true;
        if (range.start > 0 and Self.isWordByte(self.text[range.start - 1]) and Self.isWordByte(self.text[range.start])) return false;
        if (range.end < self.text.len and Self.isWordByte(self.text[range.end]) and Self.isWordByte(self.text[range.end - 1])) return false;
        return true;
    }

    /// Whether the query matches at a byte, case folded, codepoint by codepoint.
    ///
    /// - `self`: the search.
    /// - `start`: the byte to match at.
    /// - Returns: the byte just past the match, or null for none.
    fn foldedMatchAt(self: *const Self, start: usize) ?usize {
        const text_lines = mod.TextLines.init(self.text);
        const query_lines = mod.TextLines.init(self.query);
        var at = start;
        var query_at: usize = 0;
        while (query_at < self.query.len) {
            if (at >= self.text.len) return null;
            const text_end = text_lines.nextCodepointEnd(at);
            const query_end = query_lines.nextCodepointEnd(query_at);
            const text_piece = self.text[at..text_end];
            const query_piece = self.query[query_at..query_end];
            if (!std.mem.eql(u8, text_piece, query_piece)) {
                const text_codepoint = Self.decode(text_piece) orelse return null;
                const query_codepoint = Self.decode(query_piece) orelse return null;
                if (Self.fold(text_codepoint) != Self.fold(query_codepoint)) return null;
            }
            at = text_end;
            query_at = query_end;
        }
        return at;
    }

    /// The codepoint a sequence encodes.
    ///
    /// - `bytes`: one codepoint's bytes, as `TextLines` steps them.
    /// - Returns: the codepoint, or null for a byte that does not decode.
    fn decode(bytes: []const u8) ?u21 {
        if (bytes.len == 1) return if (bytes[0] < 0x80) bytes[0] else null;
        return renderer.TextShaper.decodeSequence(bytes) catch null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "search: case folds unless asked, and whole words skip parts of words" {
    const allocator = std.testing.allocator;
    const text = "Find the find, refind FIND; Ärger ärger";
    const all = try TextSearch.init(text, "find", .{}).allAlloc(allocator, 100);
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 4), all.len);
    const cased = try TextSearch.init(text, "find", .{ .case_sensitive = true }).allAlloc(allocator, 100);
    defer allocator.free(cased);
    try std.testing.expectEqual(@as(usize, 2), cased.len);
    const words = try TextSearch.init(text, "find", .{ .whole_word = true }).allAlloc(allocator, 100);
    defer allocator.free(words);
    try std.testing.expectEqual(@as(usize, 3), words.len);
    try std.testing.expectEqualStrings("FIND", text[words[2].start..words[2].end]);
    const umlauts = try TextSearch.init(text, "ÄRGER", .{}).allAlloc(allocator, 100);
    defer allocator.free(umlauts);
    try std.testing.expectEqual(@as(usize, 2), umlauts.len);
}

test "search: a bad byte matches only itself, and an empty query finds nothing" {
    const allocator = std.testing.allocator;
    const text = "a\xe2b a\xe2b ab";
    const bad = try TextSearch.init(text, "a\xe2b", .{}).allAlloc(allocator, 100);
    defer allocator.free(bad);
    try std.testing.expectEqual(@as(usize, 2), bad.len);
    try std.testing.expect(TextSearch.init(text, "", .{}).next(0) == null);
    // The limit stops the list.
    const limited = try TextSearch.init("aaaa", "a", .{}).allAlloc(allocator, 3);
    defer allocator.free(limited);
    try std.testing.expectEqual(@as(usize, 3), limited.len);
}
