//! A menu bar drawn in the window, for systems without a global one (Windows,
//! Linux): a row of titles, the open one with a popover of its entries, keys
//! right-aligned. Pure composition over zigui's stacks, text and popover,
//! with zigui's `onHover` (pointing at another title while one is open
//! switches to it) and `popoverPassthrough` (a click on another title reaches
//! it rather than only closing the open menu). The state is the app's
//! `MenuBarState`; the menus are `MenuBarMenu`s.

// View constructors are PascalCase functions, as in zigui (see CLAUDE.md).
// zlint-disable case-convention

const std = @import("std");
const log = std.log.scoped(.ziggui_menu_bar);
const mod = @import("module.zig");
const zigui = @import("zigui");

/// The bar's height, in points.
pub const menu_bar_height: f32 = 28;

/// A title or an entry's place in the bar, in the build arena: what its
/// callbacks act on.
const Spot = struct {
    const Self = @This();

    /// The bar's state.
    state: *mod.MenuBarState,

    /// The bar's menus.
    menus: []const mod.MenuBarMenu,

    /// The menu.
    menu: usize,

    /// The entry, for an entry's callbacks.
    item: usize = 0,

    /// A click on the title: opens or closes its menu.
    ///
    /// - `self`: the title.
    fn toggle(self: *Self) void {
        self.state.toggle(self.menu);
    }

    /// The pointer crossed the title: entering it switches an open bar to its menu.
    ///
    /// - `context`: the title's `Spot`.
    /// - `inside`: it entered.
    fn hoverTitle(context: ?*anyopaque, inside: bool) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        if (inside) self.state.hover(self.menu);
    }

    /// A click on the entry: closes the menu, then runs the entry.
    ///
    /// - `self`: the entry.
    fn choose(self: *Self) void {
        self.state.choose(self.menus, self.menu, self.item);
    }

    /// The pointer crossed the entry: it is highlighted while the pointer is on it.
    ///
    /// - `context`: the entry's `Spot`.
    /// - `inside`: it entered.
    fn hoverItem(context: ?*anyopaque, inside: bool) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        if (self.state.menu != self.menu) return;
        if (inside) {
            self.state.item = self.item;
        } else if (self.state.item == self.item) {
            self.state.item = null;
        }
    }
};

/// The popover's binding: shown while a menu is open; the click-to-close layer closes it.
const Shown = struct {
    const Self = @This();

    /// The binding over `state`.
    ///
    /// - `state`: the bar's state.
    /// - Returns: the binding.
    fn binding(state: *mod.MenuBarState) zigui.Binding(bool) {
        return .{ .ctx = state, .getFn = Self.get, .setFn = Self.set };
    }

    /// Reports whether the popover shows: a menu is open.
    ///
    /// - `context`: the bar's `MenuBarState`.
    /// - Returns: true while a menu is open.
    fn get(context: *anyopaque) bool {
        const state: *mod.MenuBarState = @ptrCast(@alignCast(context));
        return state.isOpen();
    }

    /// Hides the popover by closing the menu; showing it is the titles' job.
    ///
    /// - `context`: the bar's `MenuBarState`.
    /// - `shown`: whether the popover should show.
    fn set(context: *anyopaque, shown: bool) void {
        const state: *mod.MenuBarState = @ptrCast(@alignCast(context));
        if (!shown) state.close();
    }
};

/// An open menu's entries, as its popover shows them.
const Entries = struct {
    const Self = @This();

    /// Menu `index`'s entries, as the popover shows them.
    ///
    /// - `state`: the bar's state.
    /// - `menus`: the bar's menus.
    /// - `index`: the open menu.
    /// - Returns: the popover's content.
    fn view(state: *mod.MenuBarState, menus: []const mod.MenuBarMenu, index: usize) zigui.View {
        const t = mod.buildTokens();
        const alloc = zigui.buildAlloc();
        const menu = menus[index];
        const rows = alloc.alloc(zigui.View, menu.items.len) catch @panic("oom");
        for (rows, menu.items, 0..) |*row, item, at| {
            if (item.title.len == 0) {
                row.* = zigui.Divider().paddingInsets(.{ .top = 3, .bottom = 3 });
                continue;
            }
            if (item.heading) {
                row.* = zigui.Text(item.title).font(.footnote).weight(.semibold).foreground(t.secondary_label)
                    .paddingInsets(.{ .top = 4, .leading = 10, .bottom = 2, .trailing = 10 });
                continue;
            }
            const spot = alloc.create(Spot) catch @panic("oom");
            spot.* = .{ .state = state, .menus = menus, .menu = index, .item = at };
            const color = if (item.enabled) t.label else t.secondary_label;
            const line = zigui.HStack(.{
                zigui.Text(item.title).font(.callout).foreground(color),
                zigui.Spacer(),
                zigui.Text(item.key_text).font(.footnote).mono().foreground(t.secondary_label),
            }).spacing(12).paddingInsets(.{ .top = 4, .leading = 10, .bottom = 4, .trailing = 10 }).frameMaxWidth();
            const lit = item.enabled and state.item == at;
            const styled = if (lit) line.background(t.hover) else if (item.enabled) line.hoverFill(t.hover) else line;
            row.* = styled
                .onTap(zigui.actionCtx(Spot, spot, Spot.choose))
                .onHover(.{ .ctx = spot, .func = Spot.hoverItem })
                .disabled(!item.enabled);
        }
        return zigui.view.makeStackFromSlice(.vertical, 0, .leading, rows)
            .frameWidth(menu.width)
            .paddingInsets(.{ .top = 4, .bottom = 4 });
    }
};

/// A menu bar: a row of `menus`' titles; the open one (`state.menu`) shows
/// its entries in a popover below it, each with its key right-aligned. A
/// click on a title opens or closes its menu; with one open, pointing at or
/// clicking another title switches to it, and a click anywhere else closes
/// it. Choosing an entry closes the menu, then runs its action. A disabled
/// bar (`.disabled(true)`, as under a modal) takes no clicks and no hovers.
/// A narrow window passes `MenuBarMenu.fold`'s one `☰` menu instead.
///
/// - `state`: the bar's state; must outlive the frame.
/// - `menus`: the menus, in the bar's order; must outlive the frame.
/// - `options`: how it is drawn (`.{}` for the theme's colors).
/// - Returns: the bar, `menu_bar_height` tall; as wide as it is given, or with
///   `.fill = false` as wide as its titles.
pub fn MenuBar(state: *mod.MenuBarState, menus: []const mod.MenuBarMenu, options: mod.MenuBarOptions) zigui.View {
    const t = mod.buildTokens();
    const alloc = zigui.buildAlloc();
    const fg = options.foreground orelse t.label;
    // On a colored bar the theme's hover gray may not show: a wash of the text color does.
    const wash = if (options.foreground) |color| color.withAlpha(0.14) else t.hover;
    const titles = alloc.alloc(zigui.View, menus.len + @intFromBool(options.fill)) catch @panic("oom");
    for (menus, 0..) |menu, index| {
        const spot = alloc.create(Spot) catch @panic("oom");
        spot.* = .{ .state = state, .menus = menus, .menu = index };
        const open = state.menu == index;
        const face = if (menu.icon) |icon| zigui.Icon(icon, 16, fg).accessibilityLabel(menu.title) else zigui.Text(menu.title).font(.callout).foreground(fg);
        const label = face.paddingInsets(.{ .top = 3, .leading = 9, .bottom = 3, .trailing = 9 });
        const styled = if (open) label.background(wash).cornerRadius(5) else label.hoverFill(wash).cornerRadius(5);
        const title = styled
            .onTap(zigui.actionCtx(Spot, spot, Spot.toggle))
            .onHover(.{ .ctx = spot, .func = Spot.hoverTitle })
            .popoverPassthrough();
        titles[index] = if (open) title.popover(Shown.binding(state), Entries.view(state, menus, index)) else title;
    }
    if (options.fill) titles[menus.len] = zigui.Spacer();
    const bar = zigui.view.makeStackFromSlice(.horizontal, 2, .center, titles)
        .paddingInsets(.{ .leading = 6, .trailing = 6 })
        .frameHeight(menu_bar_height);
    return if (options.fill) bar.frameMaxWidth() else bar;
}

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

const TestBar = struct {
    const Self = @This();

    /// Draws a bar of `mod.TestMenus` over an empty window.
    ///
    /// - `canvas`: draws the frame and keeps its tap and hover regions.
    /// - `state`: the bar's state.
    /// - Returns: the frame, owned by the caller; propagates allocation failure.
    fn draw(canvas: *mod.TestCanvas, state: *mod.MenuBarState) !zigui.Framebuffer {
        canvas.begin(zigui.macos.light);
        const view = zigui.VStack(.{ MenuBar(state, &mod.TestMenus.menus, .{}), zigui.Spacer() }).frameMaxWidth().frameMaxHeight();
        canvas.end();
        return canvas.render(view, 400, 300);
    }
};

test "a tap on a title opens its menu; with one open, a tap on another switches" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var state: mod.MenuBarState = .{};

    var frame = try TestBar.draw(canvas, &state);
    frame.deinit();
    // "File" is the first title, "Edit" right after it, both in the bar's row.
    try std.testing.expect(canvas.tap(.{ .x = 20, .y = menu_bar_height / 2 }));
    try std.testing.expectEqual(@as(?usize, 0), state.menu);

    frame = try TestBar.draw(canvas, &state);
    frame.deinit();
    try std.testing.expect(canvas.tap(.{ .x = 70, .y = menu_bar_height / 2 }));
    try std.testing.expectEqual(@as(?usize, 1), state.menu);

    // A tap elsewhere closes it.
    frame = try TestBar.draw(canvas, &state);
    frame.deinit();
    try std.testing.expect(canvas.tap(.{ .x = 390, .y = 290 }));
    try std.testing.expect(!state.isOpen());
}

test "pointing at another title while a menu is open switches to it" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var state: mod.MenuBarState = .{};

    var frame = try TestBar.draw(canvas, &state);
    frame.deinit();
    // Closed, pointing opens nothing.
    _ = canvas.hover(.{ .x = 390, .y = 290 }, .{ .x = 70, .y = menu_bar_height / 2 });
    try std.testing.expect(!state.isOpen());
    state.open(0);
    frame = try TestBar.draw(canvas, &state);
    frame.deinit();
    try std.testing.expect(canvas.hover(.{ .x = 20, .y = menu_bar_height / 2 }, .{ .x = 70, .y = menu_bar_height / 2 }));
    try std.testing.expectEqual(@as(?usize, 1), state.menu);
}

test "an entry runs and closes the menu; a disabled one does nothing" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var state: mod.MenuBarState = .{};
    mod.TestMenus.chosen = 0;

    state.open(0);
    var frame = try TestBar.draw(canvas, &state);
    frame.deinit();
    // The popover sits below the bar: Open, a separator, Save (disabled), Quit.
    const top = menu_bar_height + 4 + 4;
    try std.testing.expect(canvas.tap(.{ .x = 40, .y = top + 12 }));
    try std.testing.expectEqual(@as(u32, 1), mod.TestMenus.chosen);
    try std.testing.expect(!state.isOpen());

    state.open(0);
    frame = try TestBar.draw(canvas, &state);
    frame.deinit();
    const save = canvas.hits.items[canvas.hits.items.len - 2];
    try std.testing.expect(save.disabled);
    _ = canvas.tap(.{ .x = save.rect.x + 10, .y = save.rect.y + save.rect.height / 2 });
    try std.testing.expectEqual(@as(u32, 1), mod.TestMenus.chosen);
}

test "the keys highlight and choose an entry, and the highlight is drawn" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var state: mod.MenuBarState = .{};
    mod.TestMenus.chosen = 0;

    state.open(0);
    var plain = try TestBar.draw(canvas, &state);
    defer plain.deinit();
    try std.testing.expect(state.key(&mod.TestMenus.menus, .down));
    try std.testing.expect(state.key(&mod.TestMenus.menus, .down));
    try std.testing.expectEqual(@as(?usize, 3), state.item);
    var lit = try TestBar.draw(canvas, &state);
    defer lit.deinit();
    // Quit's row is shaded once highlighted.
    const quit = canvas.hits.items[canvas.hits.items.len - 1].rect;
    const x: u32 = @intFromFloat(quit.x + quit.width - 4);
    const y: u32 = @intFromFloat(quit.y + quit.height / 2);
    try std.testing.expect(lit.at(x, y).luminance() < plain.at(x, y).luminance());
    try std.testing.expect(state.key(&mod.TestMenus.menus, .enter));
    try std.testing.expectEqual(@as(u32, 1), mod.TestMenus.chosen);
    try std.testing.expect(!state.isOpen());
}

test "a disabled bar takes no taps and no hovers" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var state: mod.MenuBarState = .{};

    canvas.begin(zigui.macos.light);
    const view = zigui.VStack(.{ MenuBar(&state, &mod.TestMenus.menus, .{}).disabled(true), zigui.Spacer() }).frameMaxWidth().frameMaxHeight();
    canvas.end();
    var frame = try canvas.render(view, 400, 300);
    frame.deinit();
    try std.testing.expect(!canvas.tap(.{ .x = 20, .y = menu_bar_height / 2 }));
    try std.testing.expect(!state.isOpen());
    state.open(0);
    try std.testing.expect(!canvas.hover(.{ .x = 20, .y = menu_bar_height / 2 }, .{ .x = 70, .y = menu_bar_height / 2 }));
    try std.testing.expectEqual(@as(?usize, 0), state.menu);
}

test "a folded bar is one ☰ title whose menu lists every entry under headings" {
    const canvas = try mod.TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const folded = try mod.MenuBarMenu.fold(arena.allocator(), &mod.TestMenus.menus);
    var state: mod.MenuBarState = .{};
    mod.TestMenus.chosen = 0;

    canvas.begin(zigui.macos.light);
    var view = zigui.VStack(.{ MenuBar(&state, folded, .{}), zigui.Spacer() }).frameMaxWidth().frameMaxHeight();
    canvas.end();
    var frame = try canvas.render(view, 400, 400);
    frame.deinit();
    try std.testing.expect(canvas.tap(.{ .x = 15, .y = menu_bar_height / 2 }));
    try std.testing.expectEqual(@as(?usize, 0), state.menu);
    // The keys skip the headings: down lands on Open, ←→ stay put.
    try std.testing.expect(state.key(folded, .down));
    try std.testing.expectEqual(@as(?usize, 1), state.item);
    try std.testing.expect(state.key(folded, .right));
    try std.testing.expectEqual(@as(?usize, 1), state.item);

    canvas.begin(zigui.macos.light);
    view = zigui.VStack(.{ MenuBar(&state, folded, .{}), zigui.Spacer() }).frameMaxWidth().frameMaxHeight();
    canvas.end();
    frame = try canvas.render(view, 400, 400);
    frame.deinit();
    // Headings take no taps: the regions are the title, the dismiss pieces,
    // then Open, Save (disabled), Quit, Undo (disabled) and Copy.
    const last = canvas.hits.items[canvas.hits.items.len - 1].rect;
    try std.testing.expect(canvas.tap(.{ .x = last.x + 10, .y = last.y + last.height / 2 }));
    try std.testing.expectEqual(@as(u32, 1), mod.TestMenus.chosen);
    try std.testing.expect(!state.isOpen());
}
