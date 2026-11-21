//! A run of a text's bytes, as `HighlightedText` marks them.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_range);

/// The bytes `[start, end)` of a text, cut from the text it indexes, never
/// re-encoded. Its ends belong on UTF-8 character boundaries; an end inside
/// a character `HighlightedText` widens to the whole character.
pub const TextRange = struct {
    const Self = @This();

    /// The first byte of the range.
    start: usize,

    /// One past the last byte of the range.
    end: usize,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
