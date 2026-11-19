//! A menu bar drawn in the window, for systems without a global one: its menus,
//! options and state, and the SDL keys it reads (mirrored, so it tests headless).

const std = @import("std");
const log = std.log.scoped(.ziggui_menu_bar_module);

/// The SDL3 keycodes and modifier bits ziggui's key handlers pass, mirrored so key handling stays headless.
pub const SdlKey = @import("sdl_key.zig").SdlKey;
/// One key press as an app's screens read it.
pub const Key = @import("key.zig").Key;
/// A key that is not a character.
pub const KeyName = @import("key.zig").KeyName;
/// An SDL key-down as ziggui's key handler passes it.
pub const SdlKeyEvent = @import("key.zig").SdlKeyEvent;
/// One native (macOS) menu-bar entry.
pub const CommandItem = @import("command_menu.zig").CommandItem;
/// One native (macOS) menu-bar menu.
pub const CommandMenu = @import("command_menu.zig").CommandMenu;
/// Which systems a menu entry shows on.
pub const MenuOnly = @import("menu_table.zig").MenuOnly;
/// An app's menus as one table, built into either menu bar.
pub const MenuTable = @import("menu_table.zig").MenuTable;
/// One entry of a `MenuBarMenu`.
pub const MenuBarItem = @import("menu_bar_menu.zig").MenuBarItem;
/// One menu of a `MenuBar`: a title and its entries (`fold` makes the narrow bar's `☰`).
pub const MenuBarMenu = @import("menu_bar_menu.zig").MenuBarMenu;
/// How a `MenuBar` is drawn (the titles' color on a colored title bar).
pub const MenuBarOptions = @import("menu_bar_options.zig").MenuBarOptions;
/// A menu bar's menus, every one and folded into one `☰`, picked by width (`MenuBarState.shown`).
pub const MenuBarMenus = @import("menu_bar_menus.zig").MenuBarMenus;
/// A key an open `MenuBar` reads (`fromKeycode` reads an SDL key event, `toKeycode` makes one).
pub const MenuBarKey = @import("menu_bar_state.zig").MenuBarKey;
/// A `MenuBar`'s state: the open menu, the highlighted entry, an Alt tap under way; takes the app's raw key and mouse events.
pub const MenuBarState = @import("menu_bar_state.zig").MenuBarState;
/// A `MenuBar`'s height, in points.
pub const menu_bar_height = @import("menu_bar.zig").menu_bar_height;
/// A menu bar drawn in the window, for systems without a global one.
pub const MenuBar = @import("menu_bar.zig").MenuBar;

// -----------------------------------------------------------------------------
// From the views module

/// The build arena, published theme and tokens, viewport, wrap cache and link handler (`BuildScope.shared()`), from the views module.
pub const BuildScope = @import("../module.zig").BuildScope;
/// A window's frame and how its menu bar spells a key (from the views module).
pub const WindowChrome = @import("../module.zig").WindowChrome;
/// A tap handler (`init` wraps a method, `action` a function, `select` a selection), from the views module.
pub const Callback = @import("../module.zig").Callback;
/// A hairline across a stack (from the views module).
pub const Divider = @import("../module.zig").Divider;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;
/// An icon from the icon font (from the views module).
pub const Icon = @import("../module.zig").Icon;
/// The icon font's glyph names (from the views module).
pub const IconName = @import("../module.zig").IconName;
/// Flexible space in a stack (from the views module).
pub const Spacer = @import("../module.zig").Spacer;
/// Builds stack views from tuples or slices (`fromSlice` keeps its slice), from the views module.
pub const StackBuilder = @import("../module.zig").StackBuilder;
/// A headless window for the unit tests (from the views module).
pub const TestWindow = @import("../module.zig").TestWindow;
/// One line of text (from the views module).
pub const Text = @import("../module.zig").Text;
/// Children stacked vertically (from the views module).
pub const VStack = @import("../module.zig").VStack;
/// A node of the view tree (from the views module).
pub const View = @import("../module.zig").View;

// -----------------------------------------------------------------------------
// Test Fixtures

/// Two menus for the menu bar's unit tests, counting their choices.
pub const TestMenus = @import("test_menus.zig").TestMenus;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("sdl_key.zig");
    _ = @import("key.zig");
    _ = @import("command_menu.zig");
    _ = @import("menu_table.zig");
    _ = @import("menu_bar_menu.zig");
    _ = @import("menu_bar_options.zig");
    _ = @import("menu_bar_menus.zig");
    _ = @import("menu_bar_state.zig");
    _ = @import("menu_bar.zig");
    _ = @import("test_menus.zig");
}
