//! Gallery barrel for the ziggui demo window.
//!
//! Re-exports every public type in `gallery/` so the entry point and sibling
//! files import through this module rather than reaching for each other
//! directly. Everything here builds on the `ziggui` module alone, so the gallery's
//! views render and test headless; only `main.zig` links SDL.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_module);
const builtin = @import("builtin");

/// Whether this is a debug build.
pub const is_debug = builtin.mode == .debug;

/// One page of the gallery, in sidebar order.
pub const Section = @import("gallery.zig").Section;
/// The component gallery: its state and the view tree it builds each frame.
pub const Gallery = @import("gallery.zig").Gallery;
/// What the gallery asks of the window it runs in; `main.zig` fills it from `ziggui.App`.
pub const Platform = @import("platform.zig").Platform;
/// The panels folded in from zigui's showcase, and their state.
pub const Showcase = @import("showcase.zig").Showcase;
/// A plain-text editor with a find bar and a path dialog, folded in from zigui's edit example.
pub const Editor = @import("editor.zig").Editor;

// -----------------------------------------------------------------------------
// Test Fixtures

/// The width, in points, the tests draw the gallery at.
pub const test_width: u32 = 480;

/// The height, in points, the tests draw the gallery at.
pub const test_height: u32 = 320;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
