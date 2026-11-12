//! System tray / menu bar extra, cross-platform via SDL3's native tray API:
//! NSStatusItem on macOS, Shell_NotifyIcon on Windows, StatusNotifierItem on
//! Linux. The icon is an `SDL_Surface`, so it can be drawn with ziggui's own
//! rasterizer and handed over as RGBA pixels. The menu, however, is OS-drawn
//! (labels/checkboxes/submenus/separators only) and *retained*: build it once,
//! then mutate it imperatively; it is not part of the per-frame view tree.
//!
//! Note: SDL may invoke entry callbacks from a non-main thread on some
//! platforms; on macOS they run on the main thread. Keep callbacks simple
//! (flip app-owned state, call show/hide/quit).

const std = @import("std");
const log = std.log.scoped(.ziggui_menu_bar_extra);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// A handle to a single tray menu entry, returned by the `add*` builders so its
/// label / enabled / checked state can be mutated later (the menu is retained
/// and OS-drawn, not rebuilt per frame). SDL copies the label string, so a
/// transient buffer is fine. Call these on the main thread (e.g. a frame hook).
pub const MenuBarExtraEntry = struct {
    const Self = @This();

    /// SDL's entry.
    entry: *sdl_c.SDL_TrayEntry,

    /// Replaces the entry's label.
    ///
    /// - `self`: the entry.
    /// - `label`: the new label.
    pub fn setLabel(self: *const Self, label: [:0]const u8) void {
        sdl_c.SDL_SetTrayEntryLabel(self.entry, label.ptr);
    }

    /// Enables or disables the entry.
    ///
    /// - `self`: the entry.
    /// - `enabled`: true to enable.
    pub fn setEnabled(self: *const Self, enabled: bool) void {
        sdl_c.SDL_SetTrayEntryEnabled(self.entry, enabled);
    }

    /// Checks or unchecks a checkbox entry.
    ///
    /// - `self`: the entry.
    /// - `checked`: true to check.
    pub fn setChecked(self: *const Self, checked: bool) void {
        sdl_c.SDL_SetTrayEntryChecked(self.entry, checked);
    }
};

/// A submenu / menu handle. Entries are appended in order; a button entry fires
/// its `views.Callback` when clicked.
pub const MenuBarExtraMenu = struct {
    const Self = @This();

    /// The tray that keeps the entries' callbacks.
    owner: *MenuBarExtra,

    /// SDL's menu.
    menu: *sdl_c.SDL_TrayMenu,

    /// Appends a button entry.
    ///
    /// - `self`: the menu.
    /// - `label`: the entry's label.
    /// - `callback`: runs when it is clicked.
    /// - Returns: the entry, or null on failure.
    pub fn addItem(self: *const Self, label: [:0]const u8, callback: views.Callback) ?MenuBarExtraEntry {
        const entry = sdl_c.SDL_InsertTrayEntryAt(self.menu, -1, label.ptr, sdl_c.SDL_TRAYENTRY_BUTTON) orelse return null;
        self.owner.bind(entry, callback);
        return .{ .entry = entry };
    }

    /// Appends a non-interactive label row (a disabled button), useful as a
    /// status line.
    ///
    /// - `self`: the menu.
    /// - `label`: the row's text.
    /// - Returns: the entry, or null on failure.
    pub fn addLabel(self: *const Self, label: [:0]const u8) ?MenuBarExtraEntry {
        const entry = sdl_c.SDL_InsertTrayEntryAt(self.menu, -1, label.ptr, sdl_c.SDL_TRAYENTRY_BUTTON) orelse return null;
        sdl_c.SDL_SetTrayEntryEnabled(entry, false);
        return .{ .entry = entry };
    }

    /// Appends a checkbox entry; `callback` fires on toggle (read the new state
    /// from your own model, or keep it in sync with
    /// `MenuBarExtraEntry.setChecked`).
    ///
    /// - `self`: the menu.
    /// - `label`: the entry's label.
    /// - `checked`: whether it starts checked.
    /// - `callback`: runs when it is toggled.
    /// - Returns: the entry, or null on failure.
    pub fn addCheckItem(self: *const Self, label: [:0]const u8, checked: bool, callback: views.Callback) ?MenuBarExtraEntry {
        var flags: u32 = sdl_c.SDL_TRAYENTRY_CHECKBOX;
        if (checked) flags |= sdl_c.SDL_TRAYENTRY_CHECKED;
        const entry = sdl_c.SDL_InsertTrayEntryAt(self.menu, -1, label.ptr, flags) orelse return null;
        self.owner.bind(entry, callback);
        return .{ .entry = entry };
    }

    /// Appends a separator.
    ///
    /// - `self`: the menu.
    pub fn addSeparator(self: *const Self) void {
        _ = sdl_c.SDL_InsertTrayEntryAt(self.menu, -1, null, 0);
    }

    /// Appends a submenu entry.
    ///
    /// - `self`: the menu.
    /// - `label`: the entry's label.
    /// - Returns: the submenu, for nesting, or null on failure.
    pub fn addSubmenu(self: *const Self, label: [:0]const u8) ?MenuBarExtraMenu {
        const entry = sdl_c.SDL_InsertTrayEntryAt(self.menu, -1, label.ptr, sdl_c.SDL_TRAYENTRY_SUBMENU) orelse return null;
        const submenu = sdl_c.SDL_CreateTraySubmenu(entry) orelse return null;
        return .{ .owner = self.owner, .menu = submenu };
    }
};

/// A system-tray icon with a root menu (SwiftUI's `MenuBarExtra`). Create once
/// (after/around `App.run`), keep it alive for the app's lifetime, and
/// `deinit` on exit.
pub const MenuBarExtra = struct {
    const Self = @This();

    /// SDL's tray.
    handle: *sdl_c.SDL_Tray,

    /// The root menu.
    root: *sdl_c.SDL_TrayMenu,

    /// The icon surface SDL shows, owned here.
    icon: ?*sdl_c.SDL_Surface,

    /// Boxes the entries' callbacks.
    allocator: std.mem.Allocator,

    /// The boxed callbacks SDL holds pointers to.
    callbacks: std.ArrayList(*views.Callback) = .empty,

    /// Creates the tray with an RGBA8 icon and a tooltip. SDL is initialized if
    /// it isn't already (idempotent), so this may be called before `App.run`.
    ///
    /// - `allocator`: boxes the entries' callbacks.
    /// - `rgba`: the icon, row-major RGBA8.
    /// - `width`: the icon's width, in pixels.
    /// - `height`: the icon's height, in pixels.
    /// - `tooltip`: the hover text.
    /// - Returns: the tray; `AppError.TrayInit` when SDL cannot make one.
    pub fn init(allocator: std.mem.Allocator, rgba: []const u8, width: c_int, height: c_int, tooltip: [:0]const u8) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        mod.App.shared().beforeSdlInit();
        _ = sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO);
        const pixels = mod.WindowIcon{ .rgba = rgba, .width = width, .height = height };
        const surface = pixels.surface() orelse return mod.AppError.TrayInit;
        const handle = sdl_c.SDL_CreateTray(surface, tooltip.ptr) orelse {
            // On Linux this is usually a missing libayatana-appindicator3 / libappindicator3.
            std.log.warn("SDL_CreateTray failed: {s}", .{sdl_c.SDL_GetError()});
            sdl_c.SDL_DestroySurface(surface);
            return mod.AppError.TrayInit;
        };
        const root = sdl_c.SDL_CreateTrayMenu(handle) orelse {
            sdl_c.SDL_DestroyTray(handle);
            sdl_c.SDL_DestroySurface(surface);
            return mod.AppError.TrayInit;
        };
        if (mod.os_tag == .macos) mod.Cocoa.templateStatusIcons();
        const self = Self{ .handle = handle, .root = root, .icon = surface, .allocator = allocator };
        return self;
    }

    /// Removes the tray and frees the callbacks.
    ///
    /// - `self`: the tray.
    pub fn deinit(self: *Self) void {
        sdl_c.SDL_DestroyTray(self.handle);
        if (self.icon) |surface| sdl_c.SDL_DestroySurface(surface);
        for (self.callbacks.items) |callback| self.allocator.destroy(callback);
        self.callbacks.deinit(self.allocator);
    }

    /// The root menu, to which entries are added.
    ///
    /// - `self`: the tray.
    /// - Returns: the root menu's handle.
    pub fn menu(self: *Self) MenuBarExtraMenu {
        return .{ .owner = self, .menu = self.root };
    }

    /// Removes every entry (and drops their callbacks), for a menu rebuilt from
    /// changed state. Call on the main thread, never from inside a callback.
    ///
    /// - `self`: the tray.
    pub fn clear(self: *Self) void {
        while (true) {
            var count: c_int = 0;
            const entries = sdl_c.SDL_GetTrayEntries(self.root, &count) orelse break;
            if (count == 0) break;
            sdl_c.SDL_RemoveTrayEntry(@constCast(entries[0]));
        }
        for (self.callbacks.items) |callback| self.allocator.destroy(callback);
        self.callbacks.clearRetainingCapacity();
    }

    /// Replaces the icon (e.g. to reflect a status change). Copies `rgba`, so
    /// the caller may free it afterwards.
    ///
    /// - `self`: the tray.
    /// - `rgba`: the icon, row-major RGBA8.
    /// - `width`: the icon's width, in pixels.
    /// - `height`: the icon's height, in pixels.
    pub fn setIcon(self: *Self, rgba: []const u8, width: c_int, height: c_int) void {
        const pixels = mod.WindowIcon{ .rgba = rgba, .width = width, .height = height };
        const surface = pixels.surface() orelse return;
        sdl_c.SDL_SetTrayIcon(self.handle, surface);
        if (self.icon) |old| sdl_c.SDL_DestroySurface(old);
        self.icon = surface;
        if (mod.os_tag == .macos) mod.Cocoa.templateStatusIcons();
    }

    /// Boxes `callback` so it outlives this call (SDL keeps the userdata
    /// pointer), and wires it to `entry` through the C-ABI thunk.
    fn bind(self: *Self, entry: *sdl_c.SDL_TrayEntry, callback: views.Callback) void {
        const boxed = self.allocator.create(views.Callback) catch |err| {
            log.err("tray entry callback not bound: {t}", .{err});
            return;
        };
        boxed.* = callback;
        self.callbacks.append(self.allocator, boxed) catch |err| {
            self.allocator.destroy(boxed);
            log.err("tray entry callback not bound: {t}", .{err});
            return;
        };
        sdl_c.SDL_SetTrayEntryCallback(entry, Self.entryClicked, boxed);
    }

    /// SDL's entry callback: runs the boxed callback.
    fn entryClicked(userdata: ?*anyopaque, entry: ?*sdl_c.SDL_TrayEntry) callconv(.c) void {
        _ = entry;
        const callback: *views.Callback = @ptrCast(@alignCast(userdata orelse return));
        callback.call();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(MenuBarExtra);
}
