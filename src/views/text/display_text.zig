//! Text made safe to draw: every byte that is not part of valid UTF-8 becomes
//! U+FFFD, so a file name, a key or a log line from outside never reaches the
//! text painter as bad UTF-8.

const std = @import("std");
const log = std.log.scoped(.ziggui_display_text);

/// Cleans text for drawing, as an app's views do with every string from outside.
///
/// Valid text is returned as it is, with no copy; control characters are left
/// alone (the painter draws them as it can). Only invalid bytes are replaced,
/// one replacement character each.
pub const DisplayText = struct {
    const Self = @This();

    /// What an invalid byte becomes.
    pub const replacement = "\u{FFFD}";

    /// The text, or a copy with each invalid byte replaced.
    ///
    /// Like every allocation a view constructor makes, a copy that cannot be
    /// made panics (`oom`): a view cannot fail.
    ///
    /// - `allocator`: owns a copy when one is made; typically the build arena.
    /// - `text`: the text.
    /// - Returns: `text` itself when it is valid UTF-8, else the cleaned copy.
    pub fn clean(allocator: std.mem.Allocator, text: []const u8) []const u8 {
        return Self.cleanAlloc(allocator, text) catch @panic("oom");
    }

    /// The text, or a copy with each invalid byte replaced, for code that can
    /// fail rather than panic (a menu built outside a view).
    ///
    /// - `allocator`: owns a copy when one is made; the caller frees it only
    ///   when the result is not `text` itself.
    /// - `text`: the text.
    /// - Returns: `text` itself when it is valid UTF-8, else the cleaned copy;
    ///   propagates allocation failure.
    pub fn cleanAlloc(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
        if (std.unicode.utf8ValidateSlice(text)) return text;
        return Self.copy(allocator, text);
    }

    /// How much of `text` fits in `capacity` bytes, cut on a character,
    /// never inside one (a fixed buffer's failure, a message cut to a line).
    ///
    /// - `text`: UTF-8 text.
    /// - `capacity`: the room, in bytes.
    /// - Returns: the length to keep: all of `text` when it fits.
    pub fn fitLength(text: []const u8, capacity: usize) usize {
        if (text.len <= capacity) return text.len;
        var length = capacity;
        while (length > 0 and (text[length] & 0xC0) == 0x80) length -= 1;
        return length;
    }

    /// Copies `text`, each byte that does not start a valid sequence replaced.
    ///
    /// - `allocator`: owns the copy.
    /// - `text`: the text.
    /// - Returns: the copy; propagates allocation failure.
    fn copy(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        var index: usize = 0;
        while (index < text.len) {
            const length = std.unicode.utf8ByteSequenceLength(text[index]) catch 0;
            if (length > 0 and index + length <= text.len and std.unicode.utf8ValidateSlice(text[index..][0..length])) {
                try out.appendSlice(allocator, text[index..][0..length]);
                index += length;
            } else {
                try out.appendSlice(allocator, replacement);
                index += 1;
            }
        }
        return out.toOwnedSlice(allocator);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(DisplayText);
    // Nothing here does I/O to trace.
    _ = log;
}

test "display text's copy is exactly as long as it says, for an allocator that frees" {
    const cleaned = try DisplayText.copy(std.testing.allocator, "a\xffb");
    defer std.testing.allocator.free(cleaned);
    try std.testing.expectEqualStrings("a\u{FFFD}b", cleaned);
}

test "display text keeps valid text and replaces each bad byte" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const fine = "src/é.zig";
    try std.testing.expectEqual(fine.ptr, DisplayText.clean(allocator, fine).ptr);
    try std.testing.expectEqualStrings("a\u{FFFD}b\u{FFFD}", DisplayText.clean(allocator, "a\xffb\xc3"));
    try std.testing.expectEqualStrings("\x1b[0m", DisplayText.clean(allocator, "\x1b[0m"));
}

test "display text fits a fixed buffer on a character" {
    // "é" is two bytes: room for one byte more than "ab" keeps "ab", not half of it.
    try std.testing.expectEqual(@as(usize, 2), DisplayText.fitLength("abé", 3));
    try std.testing.expectEqual(@as(usize, 4), DisplayText.fitLength("abé", 4));
    try std.testing.expectEqual(@as(usize, 4), DisplayText.fitLength("abé", 10));
    try std.testing.expectEqual(@as(usize, 0), DisplayText.fitLength("é", 1));
}
