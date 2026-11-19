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
/// Where the running executable's freedesktop entry stands.
pub const DesktopEntryState = @import("desktop_entry_state.zig").DesktopEntryState;
/// What an app's platform layer answers with no window: tests and headless runs.
pub const HeadlessPlatform = @import("headless_platform.zig").HeadlessPlatform;
/// A window's frame: its measures, its top band and drawn title bar, and how its menu bar spells a key.
pub const WindowChrome = @import("window_chrome.zig").WindowChrome;
/// Where a window was and how big: what an app saves to reopen it there.
pub const WindowPlace = @import("window_place.zig").WindowPlace;
/// Holds a window's place and its dragged dividers for the app to save once they rest.
pub const WindowMemory = @import("window_memory.zig").WindowMemory;
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

/// Where a split view's divider sits (from the views module).
pub const SplitState = @import("../module.zig").SplitState;
/// A tap region registered while painting (from the views module).
pub const HitRegion = @import("../module.zig").HitRegion;
/// A read/write handle on a `State` (from the views module).
pub const Binding = @import("../module.zig").Binding;
/// The build arena, published theme and tokens (from the views module).
pub const BuildScope = @import("../module.zig").BuildScope;
/// A tap handler (from the views module).
pub const Callback = @import("../module.zig").Callback;
/// A view that paints itself through a callback (from the views module).
pub const Canvas = @import("../module.zig").Canvas;
/// A view that draws nothing (from the views module).
pub const Empty = @import("../module.zig").Empty;
/// An image view of pixels (from the views module).
pub const Image = @import("../module.zig").Image;
/// Text made safe to draw (from the views module).
pub const DisplayText = @import("../module.zig").DisplayText;
/// Content built from the size it is laid out at (from the views module).
pub const GeometryReader = @import("../module.zig").GeometryReader;
/// Children side by side (from the views module).
pub const HStack = @import("../module.zig").HStack;
/// A segmented control of icons (from the views module).
pub const IconSegmentedControl = @import("../module.zig").IconSegmentedControl;
/// One segment of an `IconSegmentedControl` (from the views module).
pub const IconSegment = @import("../module.zig").IconSegment;
/// A menu bar drawn in the window (from the views module).
pub const MenuBar = @import("../module.zig").MenuBar;
/// One menu of a `MenuBar` (from the views module).
pub const MenuBarMenu = @import("../module.zig").MenuBarMenu;
/// A `MenuBar`'s state (from the views module).
pub const MenuBarState = @import("../module.zig").MenuBarState;
/// What a `Canvas` draws with (from the views module).
pub const GraphicsContext = @import("../module.zig").GraphicsContext;
/// A filled rectangle (from the views module).
pub const Rectangle = @import("../module.zig").Rectangle;
/// Flexible space in a stack (from the views module).
pub const Spacer = @import("../module.zig").Spacer;
/// Builds stack views from tuples or slices (from the views module).
pub const StackBuilder = @import("../module.zig").StackBuilder;
/// A headless window for the unit tests (from the views module).
pub const TestWindow = @import("../module.zig").TestWindow;
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
    _ = @import("window_memory.zig");
    _ = @import("window_place.zig");
    _ = @import("window_hit.zig");
    _ = @import("window_hit_area.zig");
    _ = @import("desktop_entry.zig");
    _ = @import("window_actions.zig");
    _ = @import("title_bar.zig");
    _ = @import("desktop_entry_state.zig");
    _ = @import("headless_platform.zig");
    _ = @import("window_chrome.zig");
}
