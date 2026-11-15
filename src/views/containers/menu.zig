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

/// One entry of a pop-up menu: its title across the menu's width, filled
/// under the pointer; a tap calls `on_tap`. The app closes the menu in it.
///
/// - `title`: the entry's title; cleaned for drawing.
/// - `on_tap`: what choosing it does.
/// - Returns: the entry.
pub fn MenuItem(title: []const u8, on_tap: mod.Callback) mod.View {
    const tokens = mod.BuildScope.shared().tokens();
    const allocator = mod.BuildScope.shared().allocator();
    return mod.HStack(.{ mod.Text(mod.DisplayText.clean(allocator, title)).font(.callout), mod.Spacer() })
        .paddingInsets(.{ .top = 4, .leading = 10, .bottom = 4, .trailing = 10 }).frameMaxWidth()
        .hoverFill(tokens.hover).onTap(on_tap);
}

/// A pop-up menu's panel: its entries (`MenuItem`s, `Divider`s) stacked at a
/// fixed width, for a `.popover` on the view it belongs to (a row's right-click).
///
/// - `items`: the entries, in order.
/// - `width`: the panel's width, in points.
/// - Returns: the panel.
pub fn MenuList(items: []const mod.View, width: f32) mod.View {
    return mod.StackBuilder.fromSlice(.vertical, 2, .leading, items).padding(4).frameWidth(width);
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "menu list stacks its entries at its width" {
    const items = [_]mod.View{ mod.Text("Open"), mod.Text("Remove…") };
    const panel = MenuList(&items, 170);
    try std.testing.expect(panel.modifiers.frame != null);
}
