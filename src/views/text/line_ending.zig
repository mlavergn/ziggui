//! How a document's lines end on disk. An editor's buffer always holds
//! `\n`: `normalizeAlloc` turns what a file holds into that, and
//! `encodeAlloc` turns it back for saving.

const std = @import("std");
const log = std.log.scoped(.ziggui_line_ending);

/// A document's line ending.
pub const LineEnding = enum {
    const Self = @This();

    /// `\n`, as macOS and Linux write it.
    lf,

    /// `\r\n`, as Windows writes it.
    crlf,

    /// The short name a status bar shows: "LF" or "CRLF".
    ///
    /// - `self`: the ending.
    /// - Returns: the name.
    pub fn label(self: *const Self) []const u8 {
        return switch (self.*) {
            .lf => "LF",
            .crlf => "CRLF",
        };
    }

    /// The bytes that end a line.
    ///
    /// - `self`: the ending.
    /// - Returns: `"\n"` or `"\r\n"`.
    pub fn bytes(self: *const Self) []const u8 {
        return switch (self.*) {
            .lf => "\n",
            .crlf => "\r\n",
        };
    }

    /// The ending most of a text's lines end with: `.crlf` when more lines
    /// end `\r\n` than `\n` alone, else `.lf` (a text with no line breaks too).
    ///
    /// - `text`: the text as read.
    /// - Returns: the ending.
    pub fn detect(text: []const u8) Self {
        var crlf_count: usize = 0;
        var lf_count: usize = 0;
        for (text, 0..) |byte, index| {
            if (byte != '\n') continue;
            if (index > 0 and text[index - 1] == '\r') crlf_count += 1 else lf_count += 1;
        }
        return if (crlf_count > lf_count) .crlf else .lf;
    }

    /// Whether a text holds a `\r` that `normalizeAlloc` would turn into `\n`.
    ///
    /// - `text`: the text.
    /// - Returns: true when it holds one.
    pub fn needsNormalizing(text: []const u8) bool {
        return std.mem.findScalar(u8, text, '\r') != null;
    }

    /// A text with every line break as `\n`: `\r\n` and a lone `\r` alike.
    ///
    /// - `allocator`: where the copy goes.
    /// - `text`: the text as read.
    /// - Returns: the copy, owned; propagates allocation failure.
    pub fn normalizeAlloc(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]u8 {
        var normalized: std.ArrayList(u8) = try .initCapacity(allocator, text.len);
        var index: usize = 0;
        while (index < text.len) : (index += 1) {
            if (text[index] != '\r') {
                normalized.appendAssumeCapacity(text[index]);
                continue;
            }
            normalized.appendAssumeCapacity('\n');
            if (index + 1 < text.len and text[index + 1] == '\n') index += 1;
        }
        return normalized.toOwnedSlice(allocator);
    }

    /// A buffer's text (lines ending `\n`) with this ending, for saving.
    ///
    /// - `self`: the ending.
    /// - `allocator`: where the copy goes.
    /// - `text`: the buffer's text.
    /// - Returns: the copy, owned; propagates allocation failure.
    pub fn encodeAlloc(self: *const Self, allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]u8 {
        if (self.* == .lf) return allocator.dupe(u8, text);
        const breaks = std.mem.countScalar(u8, text, '\n');
        const encoded = try allocator.alloc(u8, text.len + breaks);
        var at: usize = 0;
        for (text) |byte| {
            if (byte == '\n') {
                encoded[at] = '\r';
                at += 1;
            }
            encoded[at] = byte;
            at += 1;
        }
        return encoded;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "line ending: detect takes the majority, normalize and encode round trip" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(LineEnding.crlf, LineEnding.detect("a\r\nb\r\nc\n"));
    try std.testing.expectEqual(LineEnding.lf, LineEnding.detect("a\nb\r\nc\n"));
    try std.testing.expectEqual(LineEnding.lf, LineEnding.detect("no breaks"));
    const normalized = try LineEnding.normalizeAlloc(allocator, "a\r\nb\rc\n");
    defer allocator.free(normalized);
    try std.testing.expectEqualStrings("a\nb\nc\n", normalized);
    try std.testing.expect(!LineEnding.needsNormalizing(normalized));
    const ending: LineEnding = .crlf;
    const encoded = try ending.encodeAlloc(allocator, normalized);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("a\r\nb\r\nc\r\n", encoded);
    const back = try LineEnding.normalizeAlloc(allocator, encoded);
    defer allocator.free(back);
    try std.testing.expectEqualStrings(normalized, back);
}
