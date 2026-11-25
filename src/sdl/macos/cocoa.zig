//! The bits of AppKit SDL does not expose, reached through the Objective-C
//! runtime: the unified title bar, the menu bar, template tray icons, the
//! status item and the frosted popover window. macOS only; nothing here is
//! analyzed on other targets, as every call site is behind `os_tag == .macos`.

const std = @import("std");
const log = std.log.scoped(.ziggui_cocoa);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// A menu-bar submenu whose entries the app swaps while it runs
/// (`CommandItem.replaceable`), with the actions of the entries it holds now.
const ReplaceableMenu = struct {
    const Self = @This();

    /// The title of the entry that opens it, which names it; owned.
    title: []const u8,
    /// The `NSMenu`.
    menu: mod.Id,
    /// Its entries' actions, by the low part of each one's tag (`Cocoa.replaceable_tag`).
    actions: std.ArrayList(views.Callback) = .empty,
};

/// The Objective-C bridge and the AppKit objects it keeps: menu actions and
/// the status item. One per process (`shared`).
pub const Cocoa = struct {
    const Self = @This();

    /// Tags at or above this belong to a replaceable submenu's entry:
    /// `replaceable_tag * (menu + 1) + entry`.
    const replaceable_tag: i64 = 1 << 32;

    /// Menu actions, indexed by each item's tag (they live for the process).
    actions: std.ArrayList(views.Callback) = .empty,

    /// The submenus the app can swap the entries of, in the order built.
    replaceables: std.ArrayList(ReplaceableMenu) = .empty,

    /// The one object every menu item targets (`menuTarget`), made once.
    menu_target: mod.Id = null,

    /// The status item, while one exists.
    status_item: mod.Id = null,

    /// The status item button's target object.
    status_target: mod.Id = null,

    /// The status item's click callback.
    status_callback: ?views.Callback = null,

    /// The process's bridge.
    var shared_cocoa: Self = .{};

    /// The process's bridge.
    ///
    /// - Returns: the shared bridge.
    pub fn shared() *Self {
        return &shared_cocoa;
    }

    /// Transparent titlebar + full-size content + hidden title, and an empty
    /// toolbar in the unified compact style, so the titlebar is 40pt tall and
    /// the traffic lights sit centred in it, 20pt from the top: the centre of
    /// the band apps draw (`WindowChrome.top_bar_height`), level with what it
    /// holds. (The unified style's taller titlebar put them 6pt lower.)
    ///
    /// - `window`: the main window.
    pub fn unifyTitlebar(window: *sdl_c.SDL_Window) void {
        const ns_window: mod.Id = sdl_c.SDL_GetPointerProperty(sdl_c.SDL_GetWindowProperties(window), sdl_c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
        if (ns_window == null) return;
        const full_size_content: u64 = 1 << 15;
        mod.ObjectiveC.send(void, ns_window, "setStyleMask:", .{mod.ObjectiveC.send(u64, ns_window, "styleMask", .{}) | full_size_content});
        mod.ObjectiveC.send(void, ns_window, "setTitlebarAppearsTransparent:", .{@as(u8, 1)});
        mod.ObjectiveC.send(void, ns_window, "setTitleVisibility:", .{@as(i64, 1)}); // NSWindowTitleHidden
        const toolbar = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSToolbar"), "new", .{});
        mod.ObjectiveC.send(void, toolbar, "setShowsBaselineSeparator:", .{@as(u8, 0)});
        mod.ObjectiveC.send(void, ns_window, "setToolbar:", .{toolbar});
        mod.ObjectiveC.send(void, ns_window, "setToolbarStyle:", .{@as(i64, 4)}); // NSWindowToolbarStyleUnifiedCompact
    }

    /// Marks this app's menu-bar icons as template images, so macOS draws them
    /// in the menu bar's own colour (white on a dark bar, black on a light
    /// one) like every native status item. SDL hands AppKit a plain image.
    /// The items live in this process's NSStatusBarWindows; their button is a
    /// public NSStatusBarButton.
    pub fn templateStatusIcons() void {
        const ns_app = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSApplication"), "sharedApplication", .{});
        const windows = mod.ObjectiveC.send(mod.Id, ns_app, "windows", .{});
        const button_class = mod.ObjectiveC.class("NSStatusBarButton");
        const count: u64 = mod.ObjectiveC.send(u64, windows, "count", .{});
        for (0..count) |index| {
            const ns_window = mod.ObjectiveC.send(mod.Id, windows, "objectAtIndex:", .{@as(u64, index)});
            const view = mod.ObjectiveC.send(mod.Id, ns_window, "contentView", .{}) orelse continue;
            Self.templateIn(view, button_class);
        }
    }

    /// The system's open or closed hand (`NSCursor.openHandCursor`,
    /// `closedHandCursor`) as an SDL color cursor: its 1x image with a 2x one
    /// for Retina, its hot spot where AppKit puts it. SDL has no grab cursors
    /// of its own (`PointerStyle.grabIdle`, `grabActive`).
    ///
    /// - `closed`: the closed hand, for a drag that is running.
    /// - Returns: the cursor, which the caller destroys (`SDL_DestroyCursor`),
    ///   or null when AppKit or SDL cannot make it.
    pub fn handCursor(closed: bool) ?*sdl_c.SDL_Cursor {
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const cursor = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSCursor"), if (closed) "closedHandCursor" else "openHandCursor", .{}) orelse return null;
        const image = mod.ObjectiveC.send(mod.Id, cursor, "image", .{}) orelse return null;
        const size = mod.ObjectiveC.send(mod.CGSize, image, "size", .{});
        const hot_spot = mod.ObjectiveC.send(mod.CGPoint, cursor, "hotSpot", .{});
        // Written so a NaN fails; a cursor is a few dozen points across.
        if (!(size.width >= 1 and size.width <= 128 and size.height >= 1 and size.height <= 128)) return null;
        if (!(hot_spot.x >= 0 and hot_spot.x <= size.width and hot_spot.y >= 0 and hot_spot.y <= size.height)) return null;
        const base = Self.cursorSurface(image, size, 1) orelse return null;
        defer sdl_c.SDL_DestroySurface(base);
        if (Self.cursorSurface(image, size, 2)) |retina| {
            defer sdl_c.SDL_DestroySurface(retina);
            if (!sdl_c.SDL_AddSurfaceAlternateImage(base, retina)) log.info("no Retina image for the hand cursor: {s}", .{sdl_c.SDL_GetError()});
        }
        return sdl_c.SDL_CreateColorCursor(base, @intFromFloat(hot_spot.x), @intFromFloat(hot_spot.y));
    }

    /// Brings another running app forward, its windows with it
    /// (`AppInstance.activate`). Since macOS 14 only the active app may hand
    /// activation on, so this process (just launched, and so the one the user
    /// chose) first yields it to the other, then asks for it. Works before
    /// SDL starts: `NSApplication` is made here if it was not.
    ///
    /// - `pid`: the other app's process.
    /// - Returns: false when no app runs as `pid` or AppKit refused.
    pub fn activateProcess(pid: i32) bool {
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const other = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSRunningApplication"), "runningApplicationWithProcessIdentifier:", .{@as(c_int, pid)});
        if (other == null) return false;
        const ns_app = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSApplication"), "sharedApplication", .{});
        const yield = mod.ObjectiveC.selectorNamed("yieldActivationToApplication:");
        if (mod.ObjectiveC.send(u8, ns_app, "respondsToSelector:", .{yield}) != 0) {
            mod.ObjectiveC.send(void, ns_app, "yieldActivationToApplication:", .{other});
        }
        const all_windows: u64 = 1 << 0; // NSApplicationActivateAllWindows
        return mod.ObjectiveC.send(u8, other, "activateWithOptions:", .{all_windows}) != 0;
    }

    /// Puts a frosted NSVisualEffectView behind SDL's content view, so the tray
    /// panel reads as translucent glass over the desktop (Swift's
    /// MenuBarExtra window) instead of a flat translucent rectangle. The
    /// container layer clips everything to the panel's rounded corners.
    ///
    /// - `window`: the panel window.
    /// - `radius`: the corner radius, in points.
    pub fn frostWindow(window: *sdl_c.SDL_Window, radius: f64) void {
        const ns_window: mod.Id = sdl_c.SDL_GetPointerProperty(sdl_c.SDL_GetWindowProperties(window), sdl_c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
        if (ns_window == null) return;
        mod.ObjectiveC.send(void, ns_window, "setOpaque:", .{@as(u8, 0)});
        mod.ObjectiveC.send(void, ns_window, "setBackgroundColor:", .{mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSColor"), "clearColor", .{})});
        const view = mod.ObjectiveC.send(mod.Id, ns_window, "contentView", .{}) orelse return;
        const bounds = mod.ObjectiveC.send(mod.CGRect, view, "bounds", .{});

        const container = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSView"), "alloc", .{}), "initWithFrame:", .{bounds});
        mod.ObjectiveC.send(void, container, "setWantsLayer:", .{@as(u8, 1)});
        const layer = mod.ObjectiveC.send(mod.Id, container, "layer", .{});
        if (layer != null) {
            mod.ObjectiveC.send(void, layer, "setCornerRadius:", .{radius});
            mod.ObjectiveC.send(void, layer, "setMasksToBounds:", .{@as(u8, 1)});
        }
        const effect = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSVisualEffectView"), "alloc", .{}), "initWithFrame:", .{bounds});
        mod.ObjectiveC.send(void, effect, "setMaterial:", .{@as(i64, 6)}); // NSVisualEffectMaterialPopover
        mod.ObjectiveC.send(void, effect, "setBlendingMode:", .{@as(i64, 0)}); // behindWindow
        mod.ObjectiveC.send(void, effect, "setState:", .{@as(i64, 1)}); // active
        mod.ObjectiveC.send(void, effect, "setAutoresizingMask:", .{@as(u64, 18)}); // width|height sizable
        mod.ObjectiveC.send(void, container, "addSubview:", .{effect});
        mod.ObjectiveC.send(void, view, "removeFromSuperview", .{});
        mod.ObjectiveC.send(void, view, "setAutoresizingMask:", .{@as(u64, 18)});
        mod.ObjectiveC.send(void, container, "addSubview:", .{view});
        mod.ObjectiveC.send(void, ns_window, "setContentView:", .{container});
    }

    /// Creates a plain menu-bar icon whose click opens the app's own popover
    /// panel, not a native menu.
    ///
    /// - `self`: the bridge.
    /// - `rgba`: the icon, a 2x bitmap in row-major RGBA8.
    /// - `width`: the icon's width, in pixels.
    /// - `height`: the icon's height, in pixels.
    /// - `tooltip`: the hover text.
    /// - `on_click`: runs on a click.
    /// - Returns: false when `rgba` is not `width * height * 4` bytes or
    ///   AppKit refused any step.
    pub fn createStatusItem(self: *Self, rgba: []const u8, width: c_int, height: c_int, tooltip: [:0]const u8, on_click: views.Callback) bool {
        // The bitmap below is filled from `rgba` with one exact-length copy.
        if (!mod.WindowIcon.pixelsMatch(rgba, width, height)) return false;
        const pixels_wide: i64 = width;
        const pixels_high: i64 = height;
        // Alpha last, straight (non-premultiplied): our RGBA buffer's layout
        // (NSAlphaNonpremultipliedBitmapFormat).
        const representation = Self.bitmapRepresentation(mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSBitmapImageRep"), "alloc", .{}), null, pixels_wide, pixels_high, 8, 4, 1, 0, mod.ObjectiveC.string("NSCalibratedRGBColorSpace"), 2, pixels_wide * 4, 32) orelse return false;
        const raw = mod.ObjectiveC.send([*c]u8, representation, "bitmapData", .{});
        if (raw == null) return false;
        const destination: [*]u8 = @ptrCast(raw);
        @memcpy(destination[0..rgba.len], rgba);
        // The bitmap is a 2x backing store, so the image's point size is half
        // its pixel size. Sized in pixels instead, a 36 px icon would sit in
        // the menu bar as a 36 pt image: twice the bar's height, dwarfing
        // every native status item.
        const size = mod.CGSize{ .width = @as(f64, @floatFromInt(width)) / 2.0, .height = @as(f64, @floatFromInt(height)) / 2.0 };
        const image = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSImage"), "alloc", .{}), "initWithSize:", .{size});
        if (image == null) return false;
        mod.ObjectiveC.send(void, image, "addRepresentation:", .{representation});
        mod.ObjectiveC.send(void, image, "setTemplate:", .{@as(u8, 1)});
        const bar = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSStatusBar"), "systemStatusBar", .{});
        const item = mod.ObjectiveC.send(mod.Id, bar, "statusItemWithLength:", .{@as(f64, -1)}); // NSVariableStatusItemLength
        if (item == null) return false;
        const button = mod.ObjectiveC.send(mod.Id, item, "button", .{});
        if (button == null) return false;
        mod.ObjectiveC.send(void, button, "setImage:", .{image});
        if (tooltip.len > 0) mod.ObjectiveC.send(void, button, "setToolTip:", .{mod.ObjectiveC.string(tooltip)});
        const class = mod.ObjectiveC.defineClass("ZigguiStatusItemTarget", "NSObject", &.{.{ .selector = "click:", .implementation = @ptrCast(&Self.statusClick), .types = "v@:@" }});
        if (class == null) return false;
        const target = mod.ObjectiveC.send(mod.Id, class, "new", .{});
        mod.ObjectiveC.send(void, button, "setTarget:", .{target});
        mod.ObjectiveC.send(void, button, "setAction:", .{mod.ObjectiveC.selectorNamed("click:")});
        self.status_item = item;
        self.status_target = target;
        self.status_callback = on_click;
        return true;
    }

    /// Removes the status item.
    ///
    /// - `self`: the bridge.
    pub fn destroyStatusItem(self: *Self) void {
        if (self.status_item) |item| {
            const bar = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSStatusBar"), "systemStatusBar", .{});
            mod.ObjectiveC.send(void, bar, "removeStatusItem:", .{item});
        }
        self.status_item = null;
        self.status_target = null;
        self.status_callback = null;
    }

    /// Keeps SDL's application menu (About / Hide / Quit) and, when `menus` is
    /// non-empty, replaces the rest (SDL's Window menu stays otherwise);
    /// `settings` turns SDL's placeholder "Preferences… ⌘," into a working
    /// "Settings… ⌘,".
    ///
    /// - `self`: the bridge.
    /// - `menus`: the menus after the application menu.
    /// - `settings`: the Settings action, or null for none.
    pub fn setMenuBar(self: *Self, menus: []const mod.CommandMenu, settings: ?views.Callback) void {
        const ns_app = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSApplication"), "sharedApplication", .{});
        const bar = mod.ObjectiveC.send(mod.Id, ns_app, "mainMenu", .{}) orelse return;
        if (menus.len > 0) {
            while (mod.ObjectiveC.send(i64, bar, "numberOfItems", .{}) > 1) mod.ObjectiveC.send(void, bar, "removeItemAtIndex:", .{@as(i64, 1)});
            // Their submenus went with the menus: none is left to swap.
            for (self.replaceables.items) |*replaceable| {
                std.heap.page_allocator.free(replaceable.title);
                replaceable.actions.deinit(std.heap.page_allocator);
            }
            self.replaceables.clearRetainingCapacity();
        }
        const target = self.menuTarget();
        if (settings) |callback| settings: {
            const app_item = mod.ObjectiveC.send(mod.Id, bar, "itemAtIndex:", .{@as(i64, 0)}) orelse break :settings;
            const app_menu = mod.ObjectiveC.send(mod.Id, app_item, "submenu", .{}) orelse break :settings;
            self.actions.append(std.heap.page_allocator, callback) catch break :settings;
            const tag: i64 = @intCast(self.actions.items.len - 1);
            // SDL's app menu has a disabled "Preferences… ⌘," (no action):
            // take it over, so there is one item and one ⌘, in its place.
            // Found by its key, not its title: macOS 13+ retitles it "Settings…".
            const preferences = Self.indexOfKey(app_menu, ",");
            const item = if (preferences >= 0)
                mod.ObjectiveC.send(mod.Id, app_menu, "itemAtIndex:", .{preferences}) orelse break :settings
            else
                mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenuItem"), "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ mod.ObjectiveC.string("Settings…"), mod.ObjectiveC.selectorNamed("fire:"), mod.ObjectiveC.string(",") });
            mod.ObjectiveC.send(void, item, "setTitle:", .{mod.ObjectiveC.string("Settings…")});
            mod.ObjectiveC.send(void, item, "setAction:", .{mod.ObjectiveC.selectorNamed("fire:")});
            mod.ObjectiveC.send(void, item, "setTag:", .{tag});
            mod.ObjectiveC.send(void, item, "setTarget:", .{target});
            if (preferences < 0) {
                // No placeholder: after "About <app>" and a separator, as macOS apps place it.
                const at: i64 = @min(1, mod.ObjectiveC.send(i64, app_menu, "numberOfItems", .{}));
                mod.ObjectiveC.send(void, app_menu, "insertItem:atIndex:", .{ mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenuItem"), "separatorItem", .{}), at });
                mod.ObjectiveC.send(void, app_menu, "insertItem:atIndex:", .{ item, at + 1 });
            }
        }
        for (menus) |menu| {
            const holder = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenuItem"), "new", .{});
            const submenu = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenu"), "alloc", .{}), "initWithTitle:", .{Self.menuString(menu.title)});
            self.addItems(submenu, menu.items, target, null);
            mod.ObjectiveC.send(void, holder, "setSubmenu:", .{submenu});
            mod.ObjectiveC.send(void, bar, "addItem:", .{holder});
            // The bar holds the holder and the holder its submenu, as `addItems` leaves its own.
            mod.ObjectiveC.release(submenu);
            mod.ObjectiveC.release(holder);
        }
    }

    /// Swaps the entries of the replaceable submenu opened by the entry
    /// titled `title` (`CommandItem.replaceable`); the actions of the entries
    /// it held go with them. Nothing happens when no such submenu was built.
    ///
    /// - `self`: the bridge.
    /// - `title`: the opening entry's title.
    /// - `items`: the new entries; their titles are copied, their actions kept.
    pub fn replaceSubmenu(self: *Self, title: []const u8, items: []const mod.CommandItem) void {
        // The app calls this from its own code, outside SDL's event pump and
        // its pool: without one, each swap's autoreleased strings would leak.
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        for (self.replaceables.items, 0..) |*replaceable, owner| {
            if (!std.mem.eql(u8, replaceable.title, title)) continue;
            mod.ObjectiveC.send(void, replaceable.menu, "removeAllItems", .{});
            replaceable.actions.clearRetainingCapacity();
            self.addItems(replaceable.menu, items, self.menuTarget(), owner);
            return;
        }
        // A title no submenu has: the swap is lost, so say so.
        log.warn("no replaceable submenu {s}", .{title});
    }

    /// Adds `items` to `menu`, each entry with a submenu opening one of its own.
    ///
    /// - `self`: the bridge.
    /// - `menu`: the `NSMenu`.
    /// - `items`: the entries.
    /// - `target`: the object the entries' actions go to.
    /// - `owner`: the replaceable submenu `menu` is, whose list keeps the
    ///   actions; null keeps them for the process.
    fn addItems(self: *Self, menu: mod.Id, items: []const mod.CommandItem, target: mod.Id, owner: ?usize) void {
        for (items) |entry| {
            if (entry.title.len == 0) {
                mod.ObjectiveC.send(void, menu, "addItem:", .{mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenuItem"), "separatorItem", .{})});
                continue;
            }
            const opens = entry.submenu.len > 0 or entry.replaceable;
            // An entry that opens a submenu sends nothing itself.
            const selector: mod.Id = if (opens) null else mod.ObjectiveC.selectorNamed(if (entry.selector) |name| name else "fire:");
            const item = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenuItem"), "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ Self.menuString(entry.title), selector, Self.menuString(entry.key) });
            if (entry.key.len > 0) {
                var mask: u64 = 1 << 20; // Command
                if (entry.shift) mask |= 1 << 17;
                if (entry.control) mask |= 1 << 18;
                if (entry.option) mask |= 1 << 19;
                mod.ObjectiveC.send(void, item, "setKeyEquivalentModifierMask:", .{mask});
            }
            if (opens) {
                const submenu = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenu"), "alloc", .{}), "initWithTitle:", .{Self.menuString(entry.title)});
                // Inside a replaceable submenu a replaceable one stays plain:
                // the outer swap frees it, and `replaceables` would keep a
                // dangling pointer (and a new entry each swap).
                const nested: ?usize = if (entry.replaceable and owner == null) self.keepReplaceable(entry.title, submenu) else owner;
                self.addItems(submenu, entry.submenu, target, nested);
                mod.ObjectiveC.send(void, item, "setSubmenu:", .{submenu});
                // The item holds the submenu now (`replaceables` keeps a weak pointer).
                mod.ObjectiveC.release(submenu);
            } else if (entry.action) |callback| keep: {
                const list = if (owner) |at| &self.replaceables.items[at].actions else &self.actions;
                list.append(std.heap.page_allocator, callback) catch |err| {
                    log.warn("cannot keep the action of {s} [{t}]", .{ entry.title, err });
                    break :keep;
                };
                const index: i64 = @intCast(list.items.len - 1);
                const tag = if (owner) |at| replaceable_tag * @as(i64, @intCast(at + 1)) + index else index;
                mod.ObjectiveC.send(void, item, "setTag:", .{tag});
                mod.ObjectiveC.send(void, item, "setTarget:", .{target});
            }
            mod.ObjectiveC.send(void, menu, "addItem:", .{item});
            // The menu holds the item now: a swapped submenu's old entries go with `removeAllItems`.
            mod.ObjectiveC.release(item);
        }
    }

    /// An `NSString` for a menu's title or key, never nil: AppKit raises on a
    /// nil title, and `stringWithUTF8String:` gives nil for text that is not
    /// UTF-8, so such text has each invalid byte replaced (`DisplayText`).
    ///
    /// - `text`: the title or key.
    /// - Returns: the autoreleased string.
    fn menuString(text: [:0]const u8) mod.Id {
        const string = mod.ObjectiveC.string(text);
        if (string != null) return string;
        const cleaned = views.DisplayText.cleanAlloc(std.heap.page_allocator, text) catch |err| {
            log.warn("menu title not cleaned [{t}]", .{err});
            return mod.ObjectiveC.string(views.DisplayText.replacement);
        };
        defer if (cleaned.ptr != text.ptr) std.heap.page_allocator.free(cleaned);
        const terminated = std.heap.page_allocator.dupeSentinel(u8, cleaned, 0) catch |err| {
            log.warn("menu title not copied [{t}]", .{err});
            return mod.ObjectiveC.string(views.DisplayText.replacement);
        };
        defer std.heap.page_allocator.free(terminated);
        const repaired = mod.ObjectiveC.string(terminated);
        return if (repaired != null) repaired else mod.ObjectiveC.string(views.DisplayText.replacement);
    }

    /// Records a replaceable submenu.
    ///
    /// - `self`: the bridge.
    /// - `title`: the title of the entry that opens it.
    /// - `menu`: the `NSMenu`.
    /// - Returns: its index in `replaceables`; null when it cannot be kept,
    ///   its entries' actions then kept for the process.
    fn keepReplaceable(self: *Self, title: []const u8, menu: mod.Id) ?usize {
        const name = std.heap.page_allocator.dupe(u8, title) catch |err| {
            log.warn("cannot keep the submenu {s} [{t}]", .{ title, err });
            return null;
        };
        self.replaceables.append(std.heap.page_allocator, .{ .title = name, .menu = menu }) catch |err| {
            std.heap.page_allocator.free(name);
            log.warn("cannot keep the submenu {s} [{t}]", .{ title, err });
            return null;
        };
        return self.replaceables.items.len - 1;
    }

    /// Marks the status-bar buttons under `view` as template images.
    ///
    /// - `view`: the view to search, its subviews included.
    /// - `button_class`: the `NSStatusBarButton` class.
    fn templateIn(view: mod.Id, button_class: mod.Id) void {
        if (mod.ObjectiveC.send(u8, view, "isKindOfClass:", .{button_class}) != 0) {
            const image = mod.ObjectiveC.send(mod.Id, view, "image", .{}) orelse return;
            mod.ObjectiveC.send(void, image, "setTemplate:", .{@as(u8, 1)});
            mod.ObjectiveC.send(void, view, "setImage:", .{image});
            return;
        }
        const subviews = mod.ObjectiveC.send(mod.Id, view, "subviews", .{});
        const count: u64 = mod.ObjectiveC.send(u64, subviews, "count", .{});
        for (0..count) |index| Self.templateIn(mod.ObjectiveC.send(mod.Id, subviews, "objectAtIndex:", .{@as(u64, index)}), button_class);
    }

    /// `fire:` on the one target object: runs the tagged action, then wakes the
    /// loop (a menu click produces no SDL event of its own).
    ///
    /// - `sender`: the menu item chosen.
    fn fire(_: mod.Id, _: mod.Id, sender: mod.Id) callconv(.c) void {
        const self = Self.shared();
        const tag = mod.ObjectiveC.send(i64, sender, "tag", .{});
        // Copied out first: the action may replace the submenu that holds it.
        const found: ?views.Callback = if (tag >= replaceable_tag) replaceable: {
            const owner: usize = @intCast(@divTrunc(tag, replaceable_tag) - 1);
            const index: usize = @intCast(@mod(tag, replaceable_tag));
            if (owner >= self.replaceables.items.len) break :replaceable null;
            const actions = self.replaceables.items[owner].actions.items;
            break :replaceable if (index < actions.len) actions[index] else null;
        } else if (tag >= 0 and tag < self.actions.items.len) self.actions.items[@intCast(tag)] else null;
        if (found) |callback| callback.function(callback.context);
        mod.App.shared().wake();
    }

    /// The object every menu item targets, of a class registered with
    /// `fire:`: made on first use and kept, so a swapped submenu makes none.
    ///
    /// - `self`: the bridge.
    /// - Returns: the target, or nil when the class could not be registered.
    fn menuTarget(self: *Self) mod.Id {
        if (self.menu_target == null) {
            const class = mod.ObjectiveC.defineClass("ZigguiMenuTarget", "NSObject", &.{.{ .selector = "fire:", .implementation = @ptrCast(&Self.fire), .types = "v@:@" }});
            self.menu_target = mod.ObjectiveC.send(mod.Id, class, "new", .{});
        }
        return self.menu_target;
    }

    /// The status item's `click:`: runs its callback and wakes the loop.
    fn statusClick(_: mod.Id, _: mod.Id, _: mod.Id) callconv(.c) void {
        if (Self.shared().status_callback) |callback| callback.call();
        mod.App.shared().wake();
    }

    /// `initWithBitmapDataPlanes:...` takes eleven arguments; `ObjectiveC.send`
    /// covers zero to four, so it goes through `ObjectiveC.messenger`.
    ///
    /// - `target`: the allocated `NSBitmapImageRep`.
    /// - `planes`: the pixel planes, or null for the representation's own.
    /// - `pixels_wide`: the width, in pixels.
    /// - `pixels_high`: the height, in pixels.
    /// - `bits_per_sample`: bits in each channel.
    /// - `samples_per_pixel`: channels in each pixel.
    /// - `has_alpha`: whether one channel is alpha.
    /// - `is_planar`: whether channels are in separate planes.
    /// - `color_space`: the color space's name.
    /// - `bitmap_format`: the `NSBitmapFormat` flags.
    /// - `bytes_per_row`: the row stride, in bytes.
    /// - `bits_per_pixel`: bits in each pixel.
    /// - Returns: the initialized representation, or nil.
    fn bitmapRepresentation(target: mod.Id, planes: ?*anyopaque, pixels_wide: i64, pixels_high: i64, bits_per_sample: i64, samples_per_pixel: i64, has_alpha: u8, is_planar: u8, color_space: mod.Id, bitmap_format: u64, bytes_per_row: i64, bits_per_pixel: i64) mod.Id {
        const Function = fn (mod.Id, mod.Id, ?*anyopaque, i64, i64, i64, i64, u8, u8, mod.Id, u64, i64, i64) callconv(.c) mod.Id;
        return @call(.auto, mod.ObjectiveC.messenger(Function), .{
            target,
            mod.ObjectiveC.selectorNamed("initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bitmapFormat:bytesPerRow:bitsPerPixel:"),
            planes,
            pixels_wide,
            pixels_high,
            bits_per_sample,
            samples_per_pixel,
            has_alpha,
            is_planar,
            color_space,
            bitmap_format,
            bytes_per_row,
            bits_per_pixel,
        });
    }

    /// An image drawn into a new SDL surface at a scale, in straight RGBA.
    ///
    /// - `image`: the `NSImage`.
    /// - `size`: its size, in points (at most 128 a side).
    /// - `scale`: pixels per point: 1, or 2 for Retina.
    /// - Returns: the surface, which the caller destroys, or null when AppKit
    ///   or SDL cannot make it.
    fn cursorSurface(image: mod.Id, size: mod.CGSize, scale: f64) ?*sdl_c.SDL_Surface {
        const pixels_wide: i64 = @intFromFloat(@ceil(size.width * scale));
        const pixels_high: i64 = @intFromFloat(@ceil(size.height * scale));
        // Premultiplied, the only kind AppKit draws into (NSGraphicsContext).
        const representation = Self.bitmapRepresentation(mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSBitmapImageRep"), "alloc", .{}), null, pixels_wide, pixels_high, 8, 4, 1, 0, mod.ObjectiveC.string("NSDeviceRGBColorSpace"), 0, pixels_wide * 4, 32) orelse return null;
        defer mod.ObjectiveC.release(representation);
        // Sized in points, so the image draws at `scale` pixels a point.
        mod.ObjectiveC.send(void, representation, "setSize:", .{size});
        const context_class = mod.ObjectiveC.class("NSGraphicsContext");
        const context = mod.ObjectiveC.send(mod.Id, context_class, "graphicsContextWithBitmapImageRep:", .{representation}) orelse return null;
        mod.ObjectiveC.send(void, context_class, "saveGraphicsState", .{});
        mod.ObjectiveC.send(void, context_class, "setCurrentContext:", .{context});
        // NSCompositingOperationCopy, at full opacity.
        mod.ObjectiveC.send(void, image, "drawInRect:fromRect:operation:fraction:", .{ mod.CGRect{ .size = size }, mod.CGRect{}, @as(u64, 1), @as(f64, 1) });
        mod.ObjectiveC.send(void, context_class, "restoreGraphicsState", .{});
        const raw = mod.ObjectiveC.send([*c]u8, representation, "bitmapData", .{});
        if (raw == null) return null;
        const source: [*]const u8 = @ptrCast(raw);
        const surface = sdl_c.SDL_CreateSurface(@intCast(pixels_wide), @intCast(pixels_high), sdl_c.SDL_PIXELFORMAT_ABGR8888) orelse return null;
        const destination: [*]u8 = @ptrCast(surface.*.pixels orelse {
            sdl_c.SDL_DestroySurface(surface);
            return null;
        });
        const width: usize = @intCast(pixels_wide);
        const pitch: usize = @intCast(surface.*.pitch);
        for (0..@intCast(pixels_high)) |y| {
            for (0..width) |x| {
                const from = source[(y * width + x) * 4 ..][0..4];
                const to = destination[y * pitch + x * 4 ..][0..4];
                const alpha: u32 = from[3];
                // SDL's surfaces hold straight alpha: undo AppKit's premultiplying.
                for (0..3) |channel| to[channel] = if (alpha == 0) 0 else @intCast(@min(255, @as(u32, from[channel]) * 255 / alpha));
                to[3] = from[3];
            }
        }
        return surface;
    }

    /// The index of `menu`'s item whose key equivalent is `key`, or -1.
    ///
    /// - `menu`: the menu.
    /// - `key`: the key equivalent.
    /// - Returns: the item's index, or -1.
    fn indexOfKey(menu: mod.Id, key: [*:0]const u8) i64 {
        const wanted = mod.ObjectiveC.string(key);
        const count = mod.ObjectiveC.send(i64, menu, "numberOfItems", .{});
        var index: i64 = 0;
        while (index < count) : (index += 1) {
            const item = mod.ObjectiveC.send(mod.Id, menu, "itemAtIndex:", .{index}) orelse continue;
            const equivalent = mod.ObjectiveC.send(mod.Id, item, "keyEquivalent", .{}) orelse continue;
            if (mod.ObjectiveC.send(bool, equivalent, "isEqualToString:", .{wanted})) return index;
        }
        return -1;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a menu title that is not UTF-8 still makes a string, its bad bytes replaced" {
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    const pool = mod.ObjectiveC.pushPool();
    defer mod.ObjectiveC.popPool(pool);
    try std.testing.expectEqualStrings("Recent", mod.ObjectiveC.utf8(Cocoa.menuString("Recent")));
    try std.testing.expectEqualStrings("bad\u{FFFD}", mod.ObjectiveC.utf8(Cocoa.menuString("bad\xff")));
}

test "a replaceable submenu inside another stays plain, so swaps keep one record" {
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    const pool = mod.ObjectiveC.pushPool();
    defer mod.ObjectiveC.popPool(pool);
    var cocoa: Cocoa = .{};
    defer {
        for (cocoa.replaceables.items) |*replaceable| {
            std.heap.page_allocator.free(replaceable.title);
            replaceable.actions.deinit(std.heap.page_allocator);
        }
        cocoa.replaceables.deinit(std.heap.page_allocator);
        cocoa.actions.deinit(std.heap.page_allocator);
    }
    const inner = [_]mod.CommandItem{.{ .title = "Inner", .replaceable = true }};
    const items = [_]mod.CommandItem{.{ .title = "Outer", .submenu = &inner, .replaceable = true }};
    const menu = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenu"), "alloc", .{}), "initWithTitle:", .{mod.ObjectiveC.string("File")});
    defer mod.ObjectiveC.release(menu);
    cocoa.addItems(menu, &items, null, null);
    try std.testing.expectEqual(1, cocoa.replaceables.items.len);
    // Swapping the outer submenu, its new entries holding a replaceable one
    // again, records nothing more.
    cocoa.replaceSubmenu("Outer", &inner);
    cocoa.replaceSubmenu("Outer", &inner);
    try std.testing.expectEqual(1, cocoa.replaceables.items.len);
    try std.testing.expectEqualStrings("Outer", cocoa.replaceables.items[0].title);
    // The inner one is not a swap target: nothing happens, nothing dangles.
    cocoa.replaceSubmenu("Inner", &.{});
}
