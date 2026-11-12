//! The text-field context menu (right-click → Cut / Copy / Paste / Select All).
//! Drawn by ziggui (not a native OS menu) as a top-level popup in
//! `ViewRenderer.render`, so it works for every app and reuses the hit-region
//! machinery. Cut/Copy/Paste need the clipboard, which lives in the SDL layer;
//! the app registers function pointers with `setClipboardOperations` so this core
//! code stays platform-free.

const std = @import("std");
const log = std.log.scoped(.ziggui_text_context_menu);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Clipboard operations the app injects so the context menu can copy/paste.
pub const ClipboardOperations = struct {
    const Self = @This();

    /// Put the field's current selection on the system clipboard.
    copy: *const fn (*mod.TextFieldState) void,

    /// Insert the clipboard's text at the field's caret (replacing any selection).
    paste: *const fn (*mod.TextFieldState) void,
};

/// What a menu row does.
const MenuAction = enum {
    const Self = @This();

    /// Copy the selection, then delete it.
    cut,
    /// Copy the selection.
    copy,
    /// Paste at the caret.
    paste,
    /// Select the whole field.
    selectAll,

    /// Whether `hovered` is this action.
    ///
    /// - `self`: the action.
    /// - `hovered`: the hovered action, if any.
    /// - Returns: whether they match.
    fn isHovered(self: *const Self, hovered: ?Self) bool {
        return if (hovered) |action| action == self.* else false;
    }
};

/// One menu row's target: the field and what the row does to it.
const MenuItem = struct {
    const Self = @This();

    /// The field the menu edits.
    field: *mod.TextFieldState,

    /// What the row does.
    action: MenuAction,

    /// Does the row's action, then closes the menu.
    ///
    /// - `context`: the `MenuItem`.
    fn perform(context: ?*anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(context.?));
        const field = self.field;
        switch (self.action) {
            .cut => {
                if (TextContextMenu.clipboard_operations) |operations| operations.copy(field);
                _ = field.deleteSelection();
            },
            .copy => if (TextContextMenu.clipboard_operations) |operations| operations.copy(field),
            .paste => if (TextContextMenu.clipboard_operations) |operations| operations.paste(field),
            .selectAll => field.selectAll(),
        }
        TextContextMenu.shared().close();
    }
};

/// The open menu: its field, where it opened, and the hovered row.
const OpenMenu = struct {
    const Self = @This();

    /// The field the menu edits.
    field: *mod.TextFieldState,

    /// Where it opened, in layout points.
    position: renderer.Point,

    /// The row under the pointer.
    hover: ?MenuAction = null,
};

/// The text-field context menu: whether it is open, for which field, and the
/// clipboard it copies to and pastes from.
pub const TextContextMenu = struct {
    const Self = @This();

    /// The open menu, if any.
    open_menu: ?OpenMenu = null,

    /// The current thread's menu.
    threadlocal var shared_menu: Self = .{};

    /// The clipboard the app registered.
    var clipboard_operations: ?ClipboardOperations = null;

    /// The current thread's text context menu.
    ///
    /// - Returns: the shared menu.
    pub fn shared() *Self {
        return &shared_menu;
    }

    /// Registers the clipboard Cut/Copy/Paste go through.
    ///
    /// - `self`: the menu.
    /// - `operations`: the app's clipboard operations.
    pub fn setClipboardOperations(self: *Self, operations: ClipboardOperations) void {
        _ = self;
        clipboard_operations = operations;
    }

    /// Whether the menu is open.
    ///
    /// - `self`: the menu.
    /// - Returns: true while it is open.
    pub fn isOpen(self: *const Self) bool {
        return self.open_menu != null;
    }

    /// Closes the menu.
    ///
    /// - `self`: the menu.
    pub fn close(self: *Self) void {
        self.open_menu = null;
    }

    /// Drops every reference to `field`: a menu open on it closes. Its
    /// `TextFieldState.deinit` calls this, so a freed field is never edited.
    ///
    /// - `self`: the menu.
    /// - `field`: the field going away.
    pub fn forget(self: *Self, field: *const mod.TextFieldState) void {
        if (self.open_menu) |menu| if (menu.field == field) self.close();
    }

    /// The top-most editable field whose hit region contains `point`, or null. The
    /// app's right-click handler calls this to decide whether to pop the text menu.
    ///
    /// - `self`: the menu.
    /// - `regions`: the frame's hit regions.
    /// - `point`: the click.
    /// - Returns: the field, or null.
    pub fn fieldAt(self: *const Self, regions: []const mod.HitRegion, point: renderer.Point) ?*mod.TextFieldState {
        _ = self;
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (region.disabled or !region.rect.contains(point)) continue;
            switch (region.action) {
                .focus => |field| return field, // single-line TextField
                .textClick => |click| return click.state, // multi-line TextEditor
                else => {},
            }
        }
        return null;
    }

    /// Opens the menu for `field` at layout point `point`. Focuses the field so
    /// the menu's actions (and a follow-up paste) target it.
    ///
    /// - `self`: the menu.
    /// - `field`: the field.
    /// - `point`: where it opens.
    pub fn open(self: *Self, field: *mod.TextFieldState, point: renderer.Point) void {
        mod.Focus.shared().set(field);
        self.open_menu = .{ .field = field, .position = point };
    }

    /// Updates which menu item the cursor is over (for the hover highlight). The
    /// app calls this on mouse motion while the menu is open; `regions` are the
    /// current frame's hit regions (which include the menu's item rows). A no-op
    /// if closed.
    ///
    /// - `self`: the menu.
    /// - `regions`: the frame's hit regions.
    /// - `point`: the pointer.
    pub fn hover(self: *Self, regions: []const mod.HitRegion, point: renderer.Point) void {
        if (self.open_menu == null) return;
        var found: ?MenuAction = null;
        var index = regions.len;
        while (index > 0) {
            index -= 1;
            const region = regions[index];
            if (region.disabled or !region.rect.contains(point)) continue;
            // The first (top-most) region under the cursor decides: a menu item row
            // sets the hover; anything else (e.g. the dismiss region) clears it.
            switch (region.action) {
                .callback => |callback| if (callback.function == &MenuItem.perform) {
                    const item: *MenuItem = @ptrCast(@alignCast(callback.context.?));
                    found = item.action;
                },
                else => {},
            }
            break;
        }
        if (self.open_menu) |*menu| menu.hover = found;
    }

    /// Draws the open menu (if any) as a top-level popup: a full-frame dismiss
    /// region, then a positioned panel of items. Called by `ViewRenderer.render`
    /// after the app's overlays so it sits on top and wins tap dispatch.
    ///
    /// - `self`: the menu.
    /// - `context`: the paint context.
    /// - `root`: the frame.
    /// - `canvas`: where it draws.
    /// - Returns: nothing; propagates allocation failure.
    pub fn draw(self: *const Self, context: *const mod.Context, root: renderer.Rect, canvas: *renderer.Canvas) std.mem.Allocator.Error!void {
        const menu = self.open_menu orelse return;
        // Dismiss region beneath the menu: a tap anywhere not on an item closes it.
        // Appended before the items (added by renderInto below), so back-to-front
        // dispatch gives the items priority.
        try context.hit_regions.append(context.arena, .{ .rect = root, .action = .{ .callback = .{ .function = Self.dismiss } }, .disabled = false });

        // The framework calls `render` after the build ends, so the build arena is
        // closed. Re-open it (saving/restoring) just long enough to construct the
        // menu's views.
        const scope = mod.BuildScope.shared();
        const saved_arena = scope.swapAllocator(context.arena);
        defer _ = scope.swapAllocator(saved_arena);

        const content = self.build(context, menu.field);
        const menu_width: f32 = 210;
        const size = mod.ViewRenderer.measure(context, content, .{ .width = menu_width, .height = null }) catch |err| {
            log.err("text context menu not drawn: {t}", .{err});
            return;
        };
        var x = menu.position.x;
        if (x + size.width > root.maxX()) x = root.maxX() - size.width;
        if (x < root.x) x = root.x;
        var y = menu.position.y;
        if (y + size.height > root.maxY()) y = root.maxY() - size.height;
        if (y < root.y) y = root.y;
        const target = renderer.Rect{ .x = x, .y = y, .width = size.width, .height = size.height };

        const radius = context.theme.metrics.corner_radius;
        try context.theme.painter.panel(context.surface(canvas), target, radius, .popover);
        try mod.ViewRenderer.renderInto(context, content, target, canvas);
    }

    /// One menu row: a label and its shortcut, highlighted while hovered.
    ///
    /// - `self`: the menu.
    /// - `context`: the paint context.
    /// - `field`: the field the menu edits.
    /// - `label`: the row's title.
    /// - `shortcut`: its key equivalent.
    /// - `action`: what it does.
    /// - `enabled`: whether it takes taps.
    /// - `hovered`: whether the pointer is over it.
    /// - Returns: the row.
    fn row(self: *const Self, context: *const mod.Context, field: *mod.TextFieldState, label: []const u8, shortcut: []const u8, action: MenuAction, enabled: bool, hovered: bool) mod.View {
        _ = self;
        // A hovered (always enabled) row paints an accent highlight with inverted text;
        // disabled rows stay dimmed and un-highlighted.
        const label_color = if (hovered) context.theme.colors.on_accent else if (enabled) context.theme.colors.label else context.theme.colors.tertiary_label;
        const shortcut_color = if (hovered) context.theme.colors.on_accent else context.theme.colors.tertiary_label;
        var view = mod.HStack(.{
            mod.Text(label).foreground(label_color),
            mod.Spacer(),
            mod.Text(shortcut).font(.caption).foreground(shortcut_color),
        }).spacing(20).paddingInsets(.{ .top = 5, .leading = 10, .bottom = 5, .trailing = 10 }).frameMaxWidth();
        if (hovered) view = view.background(context.theme.colors.accent).cornerRadius(5);
        if (enabled) {
            const item = context.arena.create(MenuItem) catch @panic("oom");
            item.* = .{ .field = field, .action = action };
            view = view.onTap(.{ .context = item, .function = MenuItem.perform });
        }
        return view;
    }

    /// The menu's rows.
    ///
    /// - `self`: the menu.
    /// - `context`: the paint context.
    /// - `field`: the field the menu edits.
    /// - Returns: the menu's content.
    fn build(self: *const Self, context: *const mod.Context, field: *mod.TextFieldState) mod.View {
        const has_selection = field.hasSelection();
        const hovered: ?MenuAction = if (self.open_menu) |menu| menu.hover else null;
        const rows = context.arena.alloc(mod.View, 5) catch @panic("oom");
        rows[0] = self.row(context, field, "Cut", "⌘X", .cut, has_selection, MenuAction.cut.isHovered(hovered));
        rows[1] = self.row(context, field, "Copy", "⌘C", .copy, has_selection, MenuAction.copy.isHovered(hovered));
        rows[2] = self.row(context, field, "Paste", "⌘V", .paste, true, MenuAction.paste.isHovered(hovered));
        rows[3] = mod.Divider();
        rows[4] = self.row(context, field, "Select All", "⌘A", .selectAll, field.text().len > 0, MenuAction.selectAll.isHovered(hovered));
        return mod.VStack(rows).spacing(2).paddingInsets(.{ .top = 5, .leading = 6, .bottom = 5, .trailing = 6 }).frameMaxWidth();
    }

    /// The dismiss region's tap: closes the menu.
    fn dismiss(_: ?*anyopaque) void {
        Self.shared().close();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "view: text context menu — fieldAt, render, actions, clipboard hook" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    var context = environment.context();

    var field = mod.TextFieldState.init(std.testing.allocator);
    defer field.deinit();
    defer mod.Focus.shared().clear(); // opening the menu focuses the field
    try field.setText("hello world");

    // Record clipboard calls routed through the injected ops.
    const Recorder = struct {
        const Self = @This();
        var copied: bool = false;
        var pasted: bool = false;
        fn copy(target: *mod.TextFieldState) void {
            _ = target;
            copied = true;
        }
        fn paste(target: *mod.TextFieldState) void {
            _ = target;
            pasted = true;
        }
    };
    Recorder.copied = false;
    Recorder.pasted = false;
    const menu = TextContextMenu.shared();
    menu.setClipboardOperations(.{ .copy = Recorder.copy, .paste = Recorder.paste });
    defer TextContextMenu.clipboard_operations = null;
    defer menu.close(); // never leak menu state into later tests, even on failure

    // fieldAt finds the single-line TextField under a point (it registers a
    // `textClick` region).
    var canvas = renderer.Canvas.init(std.testing.allocator);
    defer canvas.deinit();
    try mod.ViewRenderer.render(&context, mod.TextField("ph", &field), .{ .x = 0, .y = 0, .width = 400, .height = 300 }, &canvas);
    try std.testing.expect(menu.fieldAt(environment.hits.items, .{ .x = 20, .y = 15 }) == &field);

    // Open the menu and re-render. Crucially, build the arg view, then end the
    // build BEFORE render — exactly as the framework does — so this guards the bug
    // where the menu's own views were constructed after the build arena had closed.
    environment.hits.clearRetainingCapacity();
    field.selectAll(); // a selection enables Cut/Copy so they register hit regions
    menu.open(&field, .{ .x = 10, .y = 10 });
    try std.testing.expect(menu.isOpen());
    const menu_argument = mod.TextField("ph", &field);
    mod.BuildScope.shared().end();
    defer mod.BuildScope.shared().begin(environment.arena_state.allocator()); // restore for environment.deinit()'s end()
    try mod.ViewRenderer.render(&context, menu_argument, .{ .x = 0, .y = 0, .width = 400, .height = 300 }, &canvas);
    try std.testing.expect(environment.hits.items.len >= 4); // field + dismiss + enabled items

    // Hover: pointing at the Copy item's region sets the menu's hovered action.
    var copy_rect: ?renderer.Rect = null;
    for (environment.hits.items) |region| switch (region.action) {
        .callback => |callback| if (callback.function == &MenuItem.perform) {
            const item: *MenuItem = @ptrCast(@alignCast(callback.context.?));
            if (item.action == .copy) copy_rect = region.rect;
        },
        else => {},
    };
    try std.testing.expect(copy_rect != null);
    menu.hover(environment.hits.items, .{ .x = copy_rect.?.x + 5, .y = copy_rect.?.y + 5 });
    try std.testing.expect(MenuAction.copy.isHovered(menu.open_menu.?.hover));
    // Pointing at empty space (the dismiss region) clears the hover.
    menu.hover(environment.hits.items, .{ .x = 380, .y = 280 });
    try std.testing.expect(menu.open_menu.?.hover == null);

    // Copy fires the hook (no mutation) and closes the menu.
    var copy_item = MenuItem{ .field = &field, .action = .copy };
    MenuItem.perform(&copy_item);
    try std.testing.expect(Recorder.copied);
    try std.testing.expect(!menu.isOpen());
    try std.testing.expectEqualStrings("hello world", field.text());

    // Select All then Cut copies and clears the buffer.
    field.selectAll();
    try std.testing.expect(field.hasSelection());
    var cut_item = MenuItem{ .field = &field, .action = .cut };
    MenuItem.perform(&cut_item);
    try std.testing.expect(Recorder.copied);
    try std.testing.expectEqual(@as(usize, 0), field.text().len);
}
