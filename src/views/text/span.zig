//! One styled run of a `RichText` paragraph.

const std = @import("std");
const log = std.log.scoped(.ziggui_span);
const renderer = @import("renderer");

/// One run of a rich paragraph: its text and how it differs from the
/// paragraph's base style (weight, italic, mono, color, background,
/// underline, link).
pub const Span = struct {
    const Self = @This();

    /// The run's text.
    text: []const u8,

    /// The weight, or null for the paragraph's base weight.
    weight: ?renderer.FontWeight = null,

    /// Drawn in the italic face.
    italic: bool = false,

    /// Drawn in the monospace face (inline code).
    mono: bool = false,

    /// Struck through.
    strike: bool = false,

    /// Underlined.
    underline: bool = false,

    /// The text color, or null for the paragraph's.
    color: ?renderer.Color = null,

    /// Painted behind the run (inline code ground).
    background: ?renderer.Color = null,

    /// Tappable target; also underlined.
    link: ?[]const u8 = null,

    /// Multiplies the paragraph's base size (inline code is a touch smaller).
    size_scale: f32 = 1,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
