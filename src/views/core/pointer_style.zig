//! The pointer's look over a view (SwiftUI's `PointerStyle`), set with
//! `.pointerStyle()`.

const std = @import("std");
const log = std.log.scoped(.ziggui_pointer_style);

/// What the pointer looks like over a view, after SwiftUI's `PointerStyle`
/// (macOS 15): the event loop shows the system cursor the top-most region
/// under the pointer asks for (`PointerInput.pointerStyleAt`). A view takes
/// one with `.pointerStyle()`; text fields, editors and selectable text show
/// `horizontalText` on their own.
pub const PointerStyle = enum {
    const Self = @This();

    /// The arrow.
    default,

    /// The I-beam, over text that can be typed in or selected.
    horizontalText,

    /// A left-right resize, over what moves sideways: a split view's divider,
    /// a table column's edge.
    columnResize,

    /// An up-down resize, over a divider that moves up and down.
    rowResize,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
