//! The open menu of a menu-style `Picker` (`.pickerStyle(.menu)`), as the
//! theme family's platform opens it (`Theme.menu_picker`): laid over the
//! picker, the chosen option checked and over its title (macOS, KDE Plasma),
//! or below it, the chosen option highlighted (Windows, Material). One is
//! open at a time.
//! The picker that opened it presents it each frame it paints (`present`), as
//! a popover overlay anchored at its frame, so the menu is drawn in that
//! picker's window, over everything, and a tap beside it dismisses it; its
//! options are the picker's this frame, never kept past it. A picker is its
//! selection binding and its place among the menu-style pickers a render
//! paints (`beginRender`), so two bound to one value open apart.

const std = @import("std");
const log = std.log.scoped(.ziggui_picker_menu);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The picker whose menu is open.
const OpenPicker = struct {
    const Self = @This();

    /// The picker's selection: which picker it is, and what a choice sets.
    selection: renderer.Binding(i64),
    /// The picker's place among the menu-style pickers a render paints, or
    /// null for the first bound to `selection` (a menu opened in code).
    ordinal: ?usize = null,
    /// The option the keyboard highlights (↑/↓), or null before a key.
    highlighted: ?usize = null,
    /// The picker's options as it last painted, in that frame's arena: read
    /// between that frame and the next build (keys), never kept past it.
    options: []const []const u8 = &.{},
};

/// What a menu-style picker's tap opens: the menu of the picker bound to
/// `selection`, built in the frame's arena.
const MenuOpener = struct {
    const Self = @This();

    /// The picker's selection.
    selection: renderer.Binding(i64),
    /// The picker's place among the menu-style pickers its render painted.
    ordinal: usize,

    /// Opens the picker's menu.
    ///
    /// - `context`: the `MenuOpener`.
    fn open(context: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        PickerMenu.shared().open_picker = .{ .selection = self.selection, .ordinal = self.ordinal };
    }
};

/// The open pop-up menu, if any.
pub const PickerMenu = struct {
    const Self = @This();

    /// The picker whose menu is open, if any.
    open_picker: ?OpenPicker = null,

    /// How many menu-style pickers the render under way has painted.
    painted: usize = 0,

    /// The open menu was presented during the render under way.
    presented: bool = false,

    /// The menu took the last key-down, so the text that key types goes
    /// nowhere (`takesText`).
    took_key: bool = false,

    /// The current thread's menu.
    threadlocal var shared_menu: Self = .{};

    /// The current thread's pop-up menu.
    ///
    /// - Returns: the shared menu.
    pub fn shared() *Self {
        return &shared_menu;
    }

    /// Whether a menu is open.
    ///
    /// - `self`: the menu.
    /// - Returns: true while one is.
    pub fn isOpen(self: *const Self) bool {
        return self.open_picker != null;
    }

    /// Whether the menu open is the one of the picker bound to `selection`.
    ///
    /// - `self`: the menu.
    /// - `selection`: the picker's selection.
    /// - Returns: true when it is.
    pub fn isOpenFor(self: *const Self, selection: renderer.Binding(i64)) bool {
        const open_picker = self.open_picker orelse return false;
        return open_picker.selection.context == selection.context and open_picker.selection.get_fn == selection.get_fn;
    }

    /// Opens the menu of the first picker bound to `selection` that paints,
    /// closing any other (a tap on a picker opens its own).
    ///
    /// - `self`: the menu.
    /// - `selection`: the picker's selection.
    pub fn open(self: *Self, selection: renderer.Binding(i64)) void {
        self.open_picker = .{ .selection = selection };
    }

    /// Closes the menu.
    ///
    /// - `self`: the menu.
    pub fn close(self: *Self) void {
        self.open_picker = null;
    }

    /// Starts counting the menu-style pickers a render paints; the renderer
    /// calls it as each render starts.
    ///
    /// - `self`: the menu.
    pub fn beginRender(self: *Self) void {
        self.painted = 0;
        self.presented = false;
    }

    /// Ends a render: a menu its picker did not present in the window under
    /// the pointer (the one it opened in) closes, as the picker is gone; the
    /// renderer calls it as each render ends. A render with no pointer over
    /// its window (a popover window drawn in the same loop) closes nothing.
    ///
    /// - `self`: the menu.
    /// - `pointer_over`: whether the pointer is over the rendered window.
    pub fn endRender(self: *Self, pointer_over: bool) void {
        if (self.open_picker != null and !self.presented and pointer_over) self.close();
    }

    /// The next menu-style picker's place in the render under way; its
    /// painter takes one each frame.
    ///
    /// - `self`: the menu.
    /// - Returns: the place, from 0.
    pub fn nextOrdinal(self: *Self) usize {
        const ordinal = self.painted;
        self.painted += 1;
        return ordinal;
    }

    /// Notes whether the menu takes a key-down (the event loop calls it for
    /// each): the text a taken key types is then dropped (`takesText`).
    ///
    /// - `self`: the menu.
    /// - `taken`: whether the menu took the key.
    pub fn noteKey(self: *Self, taken: bool) void {
        self.took_key = taken;
    }

    /// Whether the text that just came belongs to a key the menu took: a
    /// Space that chose, a letter that closed it, never typed elsewhere.
    ///
    /// - `self`: the menu.
    /// - Returns: true to drop the text; it answers once per key.
    pub fn takesText(self: *Self) bool {
        const taken = self.took_key;
        self.took_key = false;
        return taken;
    }
    /// Moves the keyboard highlight by `step` (↑ −1, ↓ +1), from the chosen
    /// option at the first key, and no further than the first or last.
    ///
    /// - `self`: the menu.
    /// - `step`: how many options, up when negative.
    pub fn moveHighlight(self: *Self, step: isize) void {
        if (self.open_picker) |*open_picker| {
            if (open_picker.options.len == 0) return;
            const last: isize = @intCast(open_picker.options.len - 1);
            const from: isize = if (open_picker.highlighted) |index| @intCast(index) else @intCast(std.math.clamp(open_picker.selection.get(), 0, last));
            open_picker.highlighted = @intCast(std.math.clamp(from + step, 0, last));
        }
    }

    /// Highlights the next option whose title starts with `character`, case
    /// aside, after the highlighted (or chosen) one and around: typing the
    /// same letter again steps through the options that start with it, as
    /// the platforms' menus and drop-down lists do.
    ///
    /// - `self`: the menu.
    /// - `character`: the ASCII letter or digit typed.
    pub fn typeSelect(self: *Self, character: u8) void {
        if (self.open_picker) |*open_picker| {
            const count = open_picker.options.len;
            if (count == 0) return;
            const selected = open_picker.selection.get();
            const from: usize = if (open_picker.highlighted) |index| index + 1 else if (selected >= 0 and selected < count) @as(usize, @intCast(selected)) + 1 else 0;
            for (0..count) |step| {
                const index = (from + step) % count;
                const title = open_picker.options[index];
                if (title.len > 0 and std.ascii.toLower(title[0]) == std.ascii.toLower(character)) {
                    open_picker.highlighted = index;
                    return;
                }
            }
        }
    }

    /// Chooses the highlighted option (Return), or keeps the choice when no
    /// key moved the highlight, and closes the menu.
    ///
    /// - `self`: the menu.
    pub fn chooseHighlighted(self: *Self) void {
        const open_picker = self.open_picker orelse return;
        if (open_picker.highlighted) |index| return self.choose(index);
        self.close();
    }

    /// Presents the open menu, when it is this picker's, as an overlay over
    /// the picker's frame; the menu-style picker's painter calls it.
    ///
    /// - `self`: the menu.
    /// - `context`: the paint context.
    /// - `picker`: the picker.
    /// - `rect`: the picker's frame.
    /// - `ordinal`: the picker's place in this render (`nextOrdinal`).
    /// - Returns: nothing; propagates allocation failure.
    pub fn present(self: *Self, context: *const mod.Context, picker: mod.PickerData, rect: renderer.Rect, ordinal: usize) std.mem.Allocator.Error!void {
        if (!self.isOpenFor(picker.selection)) return;
        // A menu opened in code goes to the first picker bound to it; one
        // opened by a tap to the picker tapped.
        if (self.open_picker.?.ordinal) |opened| {
            if (opened != ordinal) return;
        } else self.open_picker.?.ordinal = ordinal;
        const overlays = context.overlays orelse return;
        self.open_picker.?.options = picker.options;
        if (picker.options.len == 0) return self.close();
        // Painting runs after the build ends: the menu's views (and the
        // callbacks they allocate) go in the frame's arena.
        const scope = mod.BuildScope.shared();
        const saved_arena = scope.swapAllocator(context.arena);
        defer _ = scope.swapAllocator(saved_arena);
        const pixel_size = context.theme.typography.body.size;
        const shaper = renderer.TextShaper.init(context.cache.face);
        const row_height = shaper.lineHeight(pixel_size) + 2 * mod.ControlMetrics.popup_row_padding_y;
        // A selection naming no option checks none; the first row lies over the picker.
        const selected = picker.selection.get();
        const chosen: ?usize = if (selected >= 0 and selected < picker.options.len) @intCast(selected) else null;
        var widest: f32 = 0;
        for (picker.options) |option| widest = @max(widest, shaper.measureLineWidth(option, pixel_size));
        const look = context.theme.menu_picker;
        const check_width: f32 = if (look.checks_choice) mod.ControlMetrics.popup_check_width else 0;
        const title_x = mod.ControlMetrics.popup_menu_inset + mod.ControlMetrics.popup_row_padding_x + check_width;
        // Over the picker, the chosen row's title lies over the picker's: the
        // menu starts that far before and above it. Below it, nothing to align.
        const content_anchor: ?renderer.Point = if (look.menu_over_control) .{
            .x = title_x - mod.ControlMetrics.control_horizontal_padding,
            .y = mod.ControlMetrics.popup_menu_inset + @as(f32, @floatFromInt(chosen orelse 0)) * row_height + (row_height - rect.height) / 2,
        } else null;
        // As wide as the widest title, and at least as wide as the picker.
        const reach = if (content_anchor) |point| point.x + rect.width else rect.width;
        const width = @max(title_x + widest + mod.ControlMetrics.popup_row_padding_x + mod.ControlMetrics.popup_menu_inset + mod.ControlMetrics.popup_chevron_size, reach);
        const rows = try context.arena.alloc(mod.View, picker.options.len);
        for (picker.options, 0..) |option, index| rows[index] = self.row(context, look, option, index, index == chosen);
        const content = mod.StackBuilder.fromSlice(.vertical, 0, .leading, rows).padding(mod.ControlMetrics.popup_menu_inset).frameWidth(width);
        try overlays.append(context.arena, .{
            .content = content,
            .style = .popover,
            .anchor = rect,
            .dismiss = self.dismissBinding(),
            .content_anchor = content_anchor,
        });
        self.presented = true;
    }

    /// A tap target opening this picker's menu.
    ///
    /// - `context`: the paint context, whose arena holds it.
    /// - `selection`: the picker's selection.
    /// - `ordinal`: the picker's place in this render (`nextOrdinal`).
    /// - Returns: the callback; propagates allocation failure.
    pub fn opener(context: *const mod.Context, selection: renderer.Binding(i64), ordinal: usize) std.mem.Allocator.Error!mod.Callback {
        const target = try context.arena.create(MenuOpener);
        target.* = .{ .selection = selection, .ordinal = ordinal };
        return .{ .context = target, .function = MenuOpener.open };
    }

    /// One option's row: the title, the chosen one checked or highlighted as
    /// the theme family marks it, filled under the pointer or the keyboard
    /// highlight; a tap chooses it.
    ///
    /// - `self`: the menu.
    /// - `context`: the paint context.
    /// - `look`: the theme family's menu picker.
    /// - `option`: the title.
    /// - `index`: its index.
    /// - `chosen`: whether it is the chosen option.
    /// - Returns: the row.
    fn row(self: *Self, context: *const mod.Context, look: renderer.MenuPickerLook, option: []const u8, index: usize, chosen: bool) mod.View {
        const tokens = mod.BuildScope.shared().tokens();
        const title = mod.Text(mod.DisplayText.clean(context.arena, option));
        const check = if (chosen) mod.Icon(.check, 12, context.theme.colors.label) else mod.Empty();
        const content = if (look.checks_choice) mod.HStack(.{
            check.frameWidth(mod.ControlMetrics.popup_check_width).frameAlign(.leading),
            title,
            mod.Spacer(),
        }) else mod.HStack(.{ title, mod.Spacer() });
        var view = content.spacing(0)
            .paddingInsets(.{ .top = mod.ControlMetrics.popup_row_padding_y, .leading = mod.ControlMetrics.popup_row_padding_x, .bottom = mod.ControlMetrics.popup_row_padding_y, .trailing = mod.ControlMetrics.popup_row_padding_x })
            .frameMaxWidth();
        const highlighted = if (self.open_picker) |open_picker| open_picker.highlighted == index else false;
        if (highlighted) {
            view = view.background(tokens.hover);
        } else if (chosen and !look.checks_choice) {
            view = view.background(tokens.selection.withAlpha(0.28));
        } else {
            view = view.hoverFill(tokens.hover);
        }
        view = view.cornerRadius(4);
        return view.onTap(mod.Callback.tagged(Self, self, Self.choose, index));
    }

    /// Sets the picker's selection to option `index` and closes the menu.
    ///
    /// - `self`: the menu.
    /// - `index`: the option chosen.
    fn choose(self: *Self, index: usize) void {
        const open_picker = self.open_picker orelse return;
        self.close();
        open_picker.selection.set(@intCast(index));
    }

    /// Whether the menu is open, as the overlay's dismiss binding: a tap
    /// beside the menu sets it false, closing it.
    ///
    /// - `self`: the menu.
    /// - Returns: the binding.
    fn dismissBinding(self: *Self) renderer.Binding(bool) {
        return .{ .context = self, .get_fn = Self.boundOpen, .set_fn = Self.bindOpen };
    }

    /// `dismissBinding`'s reader.
    ///
    /// - `context`: the menu.
    /// - Returns: whether it is open.
    fn boundOpen(context: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(context));
        return self.isOpen();
    }

    /// `dismissBinding`'s writer: false closes the menu.
    ///
    /// - `context`: the menu.
    /// - `open_now`: whether it stays open.
    fn bindOpen(context: *anyopaque, open_now: bool) void {
        const self: *Self = @ptrCast(@alignCast(context));
        if (!open_now) self.close();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
