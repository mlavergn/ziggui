//! How a `MenuBar` is drawn.

const std = @import("std");
const log = std.log.scoped(.ziggui_menu_bar_options);
const renderer = @import("renderer");

/// How a `MenuBar` is drawn.
pub const MenuBarOptions = struct {
    const Self = @This();

    /// The color of the titles, for a bar drawn on a colored title bar
    /// (`renderer.Theme.titleBarForeground`); null for the theme's label color.
    foreground: ?renderer.Color = null,

    /// Fill the width it is given, titles at the left (a row of its own);
    /// false keeps it as wide as its titles, so in a `TitleBar` it never
    /// shares the room the middle needs, nor gets squeezed under its titles.
    fill: bool = true,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
