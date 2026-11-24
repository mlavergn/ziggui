//! Whether a view's text can be selected, as `.textSelection()` takes it.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_selectability);

/// Whether a view's text can be selected and copied (SwiftUI's
/// `TextSelectability`: `.enabled`, `.disabled`).
pub const TextSelectability = enum {
    const Self = @This();

    /// The text can be selected with the mouse and copied.
    enabled,

    /// The text cannot be selected.
    disabled,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
