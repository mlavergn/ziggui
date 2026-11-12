//! The window plumbing that needs no SDL: the app's key-up and quit hooks,
//! the window manager's hit test, and desktop-entry values, which
//! the SDL runtime (`src/sdl`) maps to SDL so what they decide is tested headless; and
//! an app-drawn title bar with its window buttons, for a custom-titlebar window.

const std = @import("std");
const log = std.log.scoped(.ziggui_window_module);

/// The key-up and quit handlers the SDL runtime's `App` forwards SDL's events to.
pub const AppHooks = @import("app_hooks.zig").AppHooks;
/// What a press in a window does for the window manager.
pub const WindowHit = @import("window_hit.zig").WindowHit;
/// The window state a `WindowHit` is found from.
pub const WindowHitArea = @import("window_hit_area.zig").WindowHitArea;
/// Escaped values for a freedesktop desktop entry (`.desktop`).
pub const DesktopEntry = @import("desktop_entry.zig").DesktopEntry;
/// What `WindowButtons` do: minimize, maximize or restore, close.
pub const WindowActions = @import("window_actions.zig").WindowActions;
/// A `TitleBar`'s height, in points.
pub const title_bar_height = @import("title_bar.zig").title_bar_height;
/// Which platform's window buttons `WindowButtons` draws.
pub const WindowButtonStyle = @import("title_bar.zig").WindowButtonStyle;
/// An app-drawn title bar: leading content, a centered middle, trailing content.
pub const TitleBar = @import("title_bar.zig").TitleBar;
/// Minimize, maximize or restore, and close, in the platform's look.
pub const WindowButtons = @import("title_bar.zig").WindowButtons;

/// A tap region registered while painting (from the views module).
pub const HitRegion = @import("../module.zig").HitRegion;
/// A read/write handle on a `State` (from the views module).
pub const Binding = @import("../module.zig").Binding;
/// The build arena, published theme and tokens (from the views module).
pub const BuildScope = @import("../module.zig").BuildScope;
/// A tap handler (from the views module).
pub const Callback = @import("../module.zig").Callback;
/// A view that paints itself through a callback (from the views module).
pub const Drawing = @import("../module.zig").Drawing;
/// A view that draws nothing (from the views module).
pub const Empty = @import("../module.zig").Empty;
/// Content built from the size it is laid out at (from the views module).
pub const GeometryReader = @import("../module.zig").GeometryReader;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;
/// A menu bar drawn in the window (from the views module).
pub const MenuBar = @import("../module.zig").MenuBar;
/// One menu of a `MenuBar` (from the views module).
pub const MenuBarMenu = @import("../module.zig").MenuBarMenu;
/// A `MenuBar`'s state (from the views module).
pub const MenuBarState = @import("../module.zig").MenuBarState;
/// What a `Drawing` paints with (from the views module).
pub const Pen = @import("../module.zig").Pen;
/// A filled rectangle (from the views module).
pub const Rectangle = @import("../module.zig").Rectangle;
/// Flexible space in a stack (from the views module).
pub const Spacer = @import("../module.zig").Spacer;
/// Builds stack views from tuples or slices (from the views module).
pub const StackBuilder = @import("../module.zig").StackBuilder;
/// A headless frame for the unit tests (from the views module).
pub const TestCanvas = @import("../module.zig").TestCanvas;
/// One line of text (from the views module).
pub const Text = @import("../module.zig").Text;
/// A node of the view tree (from the views module).
pub const View = @import("../module.zig").View;
/// Children stacked vertically (from the views module).
pub const VStack = @import("../module.zig").VStack;
/// Children layered front to back (from the views module).
pub const ZStack = @import("../module.zig").ZStack;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("app_hooks.zig");
    _ = @import("window_hit.zig");
    _ = @import("window_hit_area.zig");
    _ = @import("desktop_entry.zig");
    _ = @import("window_actions.zig");
    _ = @import("title_bar.zig");
}
