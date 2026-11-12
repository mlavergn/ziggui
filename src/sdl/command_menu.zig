//! The app's native menu-bar menus (macOS), SwiftUI's `CommandMenu`.

const std = @import("std");
const log = std.log.scoped(.ziggui_command_menu);
const views = @import("views");

/// One menu-bar entry. An empty title is a separator. `action` runs on the UI
/// thread; `selector` instead sends a standard Cocoa action down the responder
/// chain ("performMiniaturize:"). `key` + modifiers is the key equivalent
/// (Command is implied).
pub const CommandItem = struct {
    const Self = @This();

    /// The entry's title; empty for a separator.
    title: [:0]const u8 = "",

    /// The key equivalent, with Command implied; empty for none.
    key: [:0]const u8 = "",

    /// Shift is part of the key equivalent.
    shift: bool = false,

    /// Control is part of the key equivalent.
    control: bool = false,

    /// Option is part of the key equivalent.
    option: bool = false,

    /// Runs on the UI thread when the entry is chosen.
    action: ?views.Callback = null,

    /// A standard Cocoa action sent down the responder chain instead.
    selector: ?[:0]const u8 = null,
};

/// One menu in the macOS menu bar, after the application menu (see
/// `AppConfig.menus`).
pub const CommandMenu = struct {
    const Self = @This();

    /// The menu's title in the bar.
    title: [:0]const u8,

    /// Its entries, top to bottom.
    items: []const CommandItem,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
