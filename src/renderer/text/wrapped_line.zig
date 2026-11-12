//! One line of word-wrapped text, as `TextShaper.wrapText` returns it.

const std = @import("std");
const log = std.log.scoped(.ziggui_wrapped_line);

/// A byte range of the wrapped text and its width.
pub const WrappedLine = struct {
    const Self = @This();

    /// The first byte of the line.
    start: usize,
    /// One past the last byte of the line.
    end: usize,
    /// The line's advance width in pixels.
    width: f32,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
