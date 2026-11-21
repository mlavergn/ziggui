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

/// Whether this build targets macOS (`main.zig`'s Media Native sample is an AppKit view).
pub const is_macos = builtin.os.tag == .macos;

/// One page of the gallery, in sidebar order.
pub const Section = @import("gallery.zig").Section;
/// The component gallery: its state and the view tree it builds each frame.
pub const Gallery = @import("gallery.zig").Gallery;
/// What the gallery asks of the window it runs in; `main.zig` fills it from `ziggui.App`.
pub const Platform = @import("platform.zig").Platform;
/// What a system file dialog left: nothing yet, a cancel, or the path picked.
pub const FileDialogOutcome = @import("platform.zig").FileDialogOutcome;
/// The panels folded in from zigui's showcase, and their state.
pub const Showcase = @import("showcase.zig").Showcase;
/// A plain-text editor with a find bar and a path dialog, folded in from zigui's edit example.
pub const Editor = @import("editor.zig").Editor;
/// The design-kit panels (badges, key caps, keyed buttons, segmented controls, forms, rows), and their state.
pub const Kit = @import("kit.zig").Kit;
/// The Media Video panel: a `VideoPlayer` and its player.
pub const Media = @import("media.zig").Media;
/// The Pickers panel: menu-style pickers in a form, and outside one.
pub const Pickers = @import("pickers.zig").Pickers;
/// The Settings panel: an app's settings (`ziggui.Settings`), and their state.
pub const SettingsPanel = @import("settings_panel.zig").SettingsPanel;
/// The Media Web panel: a `WebPage` under a browser's toolbar, and its bookmarks.
pub const WebPanel = @import("web_panel.zig").WebPanel;
/// A saved site of the Media Web panel.
pub const Bookmark = @import("bookmarks.zig").Bookmark;
/// The Media Web panel's saved sites, in memory (`readZon`/`writeZon` for a file).
pub const Bookmarks = @import("bookmarks.zig").Bookmarks;
/// A gallery card: a headline over a rounded group, the names line under it.
pub const Card = @import("card.zig").Card;
/// The line under each card naming what it shows: selectable, with a copy button.
pub const CardName = @import("card_name.zig").CardName;
/// Where names lines are collected while the tests check the search index.
pub const CardNameRecording = @import("card_name.zig").CardNameRecording;
/// The sidebar's search: its field and the sections it leaves.
pub const SectionSearch = @import("section_search.zig").SectionSearch;
/// One section the sidebar's search keeps, and what in it matched.
pub const SectionMatch = @import("section_search.zig").SectionMatch;

// -----------------------------------------------------------------------------
// Test Fixtures

/// The width, in points, the tests draw the gallery at.
pub const test_width: u32 = 480;

/// The height, in points, the tests draw the gallery at.
pub const test_height: u32 = 320;

/// The folder the Files section opens: `fixtures/file_browser`, whose
/// fixed contents keep that section's screenshot the same on every run.
pub const fixtures_path: []const u8 = @import("gallery_config").fixtures_path;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
