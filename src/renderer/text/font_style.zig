//! The style a view's text asks a `FontSet` for: weight, italic, monospace.

const std = @import("std");
const log = std.log.scoped(.ziggui_font_style);
const mod = @import("module.zig");

/// A text style's face selection.
pub const FontStyle = struct {
    const Self = @This();

    /// The weight.
    weight: mod.FontWeight = .regular,
    /// Whether the text is italic.
    italic: bool = false,
    /// Whether the text is monospaced.
    mono: bool = false,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
