//! An image of RGBA pixels.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_image);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// An image, drawn at its native pixel size (`.scaledToFit()` to fit a frame).
///
/// - `image`: the pixels.
/// - Returns: the view.
pub fn Image(image: renderer.Image) mod.View {
    return .{ .kind = .{ .image = .{ .image = image } } };
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
