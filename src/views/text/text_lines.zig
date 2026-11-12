//! Line and column geometry over a UTF-8 byte buffer: lines are separated by
//! '\n', and a column counts codepoints from the line start. Shared by
//! `TextFieldState`'s movement and the editor's painting.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_lines);

/// A UTF-8 buffer read as lines and columns.
pub const TextLines = struct {
    const Self = @This();

    /// The text, borrowed.
    bytes: []const u8,

    /// Reads `bytes` as lines.
    ///
    /// - `bytes`: the text, borrowed.
    /// - Returns: the lines.
    pub fn init(bytes: []const u8) Self {
        const self = Self{ .bytes = bytes };
        return self;
    }

    /// The start of the codepoint before byte `index`: the inverse of
    /// `nextCodepointEnd`, so a bad byte is stepped over one byte at a time
    /// either way.
    ///
    /// - `self`: the lines.
    /// - `index`: a byte index.
    /// - Returns: the previous codepoint's first byte (0 at the start).
    pub fn previousCodepointStart(self: *const Self, index: usize) usize {
        var cursor = index;
        if (cursor == 0) return 0;
        cursor -= 1;
        while (cursor > 0 and (self.bytes[cursor] & 0xC0) == 0x80) cursor -= 1; // skip UTF-8 continuation bytes
        // Not one whole sequence ending at `index` (a stray continuation byte): one byte back.
        if (self.nextCodepointEnd(cursor) != index) return index - 1;
        return cursor;
    }

    /// The end of the codepoint at byte `index`: past its whole sequence when
    /// that decodes, else just past the one byte (a stray continuation byte, a
    /// lead byte cut short or followed by a non-continuation), so a step
    /// forward never swallows the valid text after a bad byte.
    ///
    /// - `self`: the lines.
    /// - `index`: a byte index.
    /// - Returns: the next codepoint's first byte (the text's end at the end).
    pub fn nextCodepointEnd(self: *const Self, index: usize) usize {
        if (index >= self.bytes.len) return self.bytes.len;
        const length = std.unicode.utf8ByteSequenceLength(self.bytes[index]) catch return index + 1;
        if (length == 1) return index + 1;
        if (index + length > self.bytes.len) return index + 1;
        _ = std.unicode.utf8Decode(self.bytes[index .. index + length]) catch return index + 1;
        return index + length;
    }

    /// The first byte of the line holding byte `index`.
    ///
    /// - `self`: the lines.
    /// - `index`: a byte index.
    /// - Returns: the line's start.
    pub fn lineStart(self: *const Self, index: usize) usize {
        var cursor = @min(index, self.bytes.len);
        while (cursor > 0 and self.bytes[cursor - 1] != '\n') cursor -= 1;
        return cursor;
    }

    /// The end of the line holding byte `index` (its '\n', or the text's end).
    ///
    /// - `self`: the lines.
    /// - `index`: a byte index.
    /// - Returns: the line's end.
    pub fn lineEnd(self: *const Self, index: usize) usize {
        var cursor = @min(index, self.bytes.len);
        while (cursor < self.bytes.len and self.bytes[cursor] != '\n') cursor += 1;
        return cursor;
    }

    /// The column of byte `index`: codepoints from its line's start.
    ///
    /// - `self`: the lines.
    /// - `index`: a byte index.
    /// - Returns: the 0-based column.
    pub fn column(self: *const Self, index: usize) usize {
        const limit = @min(index, self.bytes.len);
        var count: usize = 0;
        var cursor = self.lineStart(limit);
        while (cursor < limit) : (cursor += 1) {
            if ((self.bytes[cursor] & 0xC0) != 0x80) count += 1; // count non-continuation bytes
        }
        return count;
    }

    /// The line byte `index` is on.
    ///
    /// - `self`: the lines.
    /// - `index`: a byte index.
    /// - Returns: the 0-based line.
    pub fn lineIndex(self: *const Self, index: usize) usize {
        const limit = @min(index, self.bytes.len);
        var count: usize = 0;
        for (self.bytes[0..limit]) |byte| {
            if (byte == '\n') count += 1;
        }
        return count;
    }

    /// How many lines the text has (one more than its newlines).
    ///
    /// - `self`: the lines.
    /// - Returns: the line count.
    pub fn lineCount(self: *const Self) usize {
        var count: usize = 1;
        for (self.bytes) |byte| {
            if (byte == '\n') count += 1;
        }
        return count;
    }

    /// The byte index `target_column` codepoints into the line spanning
    /// [line_start, line_end].
    ///
    /// - `self`: the lines.
    /// - `line_start`: the line's first byte.
    /// - `line_end`: the line's end.
    /// - `target_column`: the column.
    /// - Returns: the byte index, clamped to the line's end.
    pub fn indexForColumn(self: *const Self, line_start: usize, line_end: usize, target_column: usize) usize {
        var cursor = line_start;
        var count: usize = 0;
        while (cursor < line_end and count < target_column) {
            cursor = self.nextCodepointEnd(cursor);
            count += 1;
        }
        return @min(cursor, line_end);
    }

    /// The byte range [start, end) of line `line_index` (0-based), clamped to the last.
    ///
    /// - `self`: the lines.
    /// - `line_index`: the line.
    /// - Returns: its byte range.
    pub fn lineRange(self: *const Self, line_index: usize) struct { start: usize, end: usize } {
        var start: usize = 0;
        var seen: usize = 0;
        var cursor: usize = 0;
        while (cursor < self.bytes.len) : (cursor += 1) {
            if (self.bytes[cursor] == '\n') {
                if (seen == line_index) return .{ .start = start, .end = cursor };
                seen += 1;
                start = cursor + 1;
            }
        }
        return .{ .start = start, .end = self.bytes.len };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "nextCodepointEnd steps a whole valid sequence, one byte of a bad one" {
    const lines = TextLines.init("a\xc3\xa9\xe2ab\x80\xf0\x9f\x98\x80\xe2\x82");
    try std.testing.expectEqual(@as(usize, 1), lines.nextCodepointEnd(0)); // "a"
    try std.testing.expectEqual(@as(usize, 3), lines.nextCodepointEnd(1)); // "é"
    try std.testing.expectEqual(@as(usize, 4), lines.nextCodepointEnd(3)); // a lead byte before "ab"
    try std.testing.expectEqual(@as(usize, 5), lines.nextCodepointEnd(4)); // "a" survives
    try std.testing.expectEqual(@as(usize, 7), lines.nextCodepointEnd(6)); // a stray continuation byte
    try std.testing.expectEqual(@as(usize, 11), lines.nextCodepointEnd(7)); // a four-byte emoji
    try std.testing.expectEqual(@as(usize, 12), lines.nextCodepointEnd(11)); // a lead byte cut short at the end
    try std.testing.expectEqual(@as(usize, 13), lines.nextCodepointEnd(12));
    try std.testing.expectEqual(@as(usize, 13), lines.nextCodepointEnd(13)); // the end stays put
    // Stepping back undoes each step forward.
    var index: usize = lines.bytes.len;
    var steps: [13]usize = undefined;
    var count: usize = 0;
    var forward: usize = 0;
    while (forward < lines.bytes.len) : (count += 1) {
        steps[count] = forward;
        forward = lines.nextCodepointEnd(forward);
    }
    while (count > 0) {
        count -= 1;
        index = lines.previousCodepointStart(index);
        try std.testing.expectEqual(steps[count], index);
    }
    // indexForColumn counts the bad byte as one column, not three.
    try std.testing.expectEqual(@as(usize, 2), TextLines.init("\xe2ab").indexForColumn(0, 3, 2));
}
