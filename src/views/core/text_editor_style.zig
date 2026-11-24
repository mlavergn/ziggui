//! How the `TextEditor`s in a subtree draw their chrome, as `.textEditorStyle()` sets it.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_editor_style);

/// How a `TextEditor` draws its chrome (SwiftUI's `TextEditorStyle`): set for a
/// subtree and inherited, as `.toggleStyle()` is.
pub const TextEditorStyle = enum {
    const Self = @This();

    /// The theme's field: its ground, border and focus ring.
    automatic,

    /// No chrome of its own: the text alone, on whatever its container draws.
    plain,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
