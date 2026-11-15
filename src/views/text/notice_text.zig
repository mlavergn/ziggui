//! The last thing an action said: a fixed buffer, so a notice never allocates.

const std = @import("std");
const log = std.log.scoped(.ziggui_notice_text);

/// The last thing an action said, kept for the notice strip (`NoticeBar`).
pub const NoticeText = struct {
    const Self = @This();

    /// The longest notice kept; longer ones are cut.
    pub const capacity: usize = 512;

    /// The text, copied.
    // SAFETY: `set` writes the first `length` bytes before `text` reads them.
    buffer: [capacity]u8 = undefined,
    /// How much of `buffer` is the text.
    length: usize = 0,
    /// It is a refusal or failure: `NoticeBar` draws it in the removed color.
    problem: bool = false,

    /// The text.
    ///
    /// - `self`: the notice.
    /// - Returns: the text, borrowed.
    pub fn text(self: *const Self) []const u8 {
        return self.buffer[0..self.length];
    }

    /// Replaces the text.
    ///
    /// - `self`: the notice.
    /// - `words`: the new text; cut at `capacity`, on a UTF-8 boundary, and its first line only.
    /// - `problem`: whether it is a refusal.
    pub fn set(self: *Self, words: []const u8, problem: bool) void {
        const line = std.mem.trim(u8, words[0 .. std.mem.findScalar(u8, words, '\n') orelse words.len], " \t\r");
        var length = @min(line.len, capacity);
        while (length > 0 and length < line.len and line[length] & 0xc0 == 0x80) length -= 1;
        @memcpy(self.buffer[0..length], line[0..length]);
        self.length = length;
        self.problem = problem;
    }

    /// Empties the notice.
    ///
    /// - `self`: the notice.
    pub fn clear(self: *Self) void {
        self.length = 0;
        self.problem = false;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a notice keeps its first line, cut on a character boundary" {
    var notice: NoticeText = .{};
    notice.set("  profile saved\nsecond line", false);
    try std.testing.expectEqualStrings("profile saved", notice.text());
    var long: [800]u8 = undefined;
    for (0..400) |index| @memcpy(long[index * 2 ..][0..2], "é");
    notice.set(&long, true);
    try std.testing.expect(notice.text().len <= NoticeText.capacity);
    try std.testing.expect(std.unicode.utf8ValidateSlice(notice.text()));
    try std.testing.expect(notice.problem);
    notice.clear();
    try std.testing.expectEqualStrings("", notice.text());
}
