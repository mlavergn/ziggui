//! Pop-up menus: a button (or arbitrary trigger) that toggles a popover of item
//! views. Built from a `.popover` over an app-owned `State(bool)`: no dedicated
//! overlay style or hit action.

// View constructors are PascalCase functions, as in SwiftUI (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_menu);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// What a menu's trigger does: flip whether the menu is shown.
const MenuToggle = struct {
    const Self = @This();

    /// Flips `open`.
    ///
    /// - `open`: whether the menu is shown.
    fn flip(open: *renderer.State(bool)) void {
        open.set(!open.get());
    }
};

/// A button that toggles a popover menu of `items` (a tuple or `[]const View`).
/// `open` is app-owned `State(bool)` tracking whether the menu is shown; tapping
/// the button toggles it, tapping the scrim dismisses it.
///
/// - `label`: the button's title.
/// - `open`: whether the menu is shown; app-owned.
/// - `items`: the menu's entries.
/// - Returns: the button.
pub fn Menu(label: []const u8, open: *renderer.State(bool), items: anytype) mod.View {
    const content = mod.VStack(items).padding(6);
    return mod.Button(label, mod.Callback.init(renderer.State(bool), open, MenuToggle.flip))
        .popover(open.binding(), content);
}

/// Attaches a popover menu of `items` to an arbitrary `trigger` view: tapping
/// the trigger toggles the menu. The right-click/long-press analogue of `Menu`.
///
/// - `trigger`: the view tapped.
/// - `open`: whether the menu is shown; app-owned.
/// - `items`: the menu's entries.
/// - Returns: the trigger, with the menu.
pub fn ContextMenu(trigger: mod.View, open: *renderer.State(bool), items: anytype) mod.View {
    const content = mod.VStack(items).padding(6);
    return trigger
        .onTap(mod.Callback.init(renderer.State(bool), open, MenuToggle.flip))
        .popover(open.binding(), content);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
