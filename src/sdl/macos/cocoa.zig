//! The bits of AppKit SDL does not expose, reached through the Objective-C
//! runtime: the unified title bar, the menu bar, template tray icons, the
//! status item and the frosted popover panel. macOS only; nothing here is
//! analyzed on other targets, as every call site is behind `os_tag == .macos`.

const std = @import("std");
const log = std.log.scoped(.ziggui_cocoa);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// The Objective-C bridge and the AppKit objects it keeps: menu actions and
/// the status item. One per process (`shared`).
pub const Cocoa = struct {
    const Self = @This();

    /// Menu actions, indexed by each item's tag (they live for the process).
    actions: std.ArrayList(views.Callback) = .empty,

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
        }
        const target = Self.menuTarget();
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
            const submenu = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenu"), "alloc", .{}), "initWithTitle:", .{mod.ObjectiveC.string(menu.title)});
            for (menu.items) |entry| {
                if (entry.title.len == 0) {
                    mod.ObjectiveC.send(void, submenu, "addItem:", .{mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenuItem"), "separatorItem", .{})});
                    continue;
                }
                const selector = mod.ObjectiveC.selectorNamed(if (entry.selector) |name| name else "fire:");
                const item = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSMenuItem"), "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ mod.ObjectiveC.string(entry.title), selector, mod.ObjectiveC.string(entry.key) });
                if (entry.key.len > 0) {
                    var mask: u64 = 1 << 20; // Command
                    if (entry.shift) mask |= 1 << 17;
                    if (entry.control) mask |= 1 << 18;
                    if (entry.option) mask |= 1 << 19;
                    mod.ObjectiveC.send(void, item, "setKeyEquivalentModifierMask:", .{mask});
                }
                if (entry.action) |callback| {
                    mod.ObjectiveC.send(void, item, "setTag:", .{@as(i64, @intCast(self.actions.items.len))});
                    self.actions.append(std.heap.page_allocator, callback) catch continue;
                    mod.ObjectiveC.send(void, item, "setTarget:", .{target});
                }
                mod.ObjectiveC.send(void, submenu, "addItem:", .{item});
            }
            mod.ObjectiveC.send(void, holder, "setSubmenu:", .{submenu});
            mod.ObjectiveC.send(void, bar, "addItem:", .{holder});
        }
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
        if (tag >= 0 and tag < self.actions.items.len) {
            const callback = self.actions.items[@intCast(tag)];
            callback.function(callback.context);
        }
        mod.App.shared().wake();
    }

    /// The object every menu item targets, of a class registered with `fire:`.
    ///
    /// - Returns: the target, or nil when the class could not be registered.
    fn menuTarget() mod.Id {
        const class = mod.ObjectiveC.defineClass("ZigguiMenuTarget", "NSObject", &.{.{ .selector = "fire:", .implementation = @ptrCast(&Self.fire), .types = "v@:@" }});
        return mod.ObjectiveC.send(mod.Id, class, "new", .{});
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
