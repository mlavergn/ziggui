//! The bits of AppKit SDL does not expose, reached through the Objective-C
//! runtime: the unified title bar, the menu bar, template tray icons, the
//! status item and the frosted popover panel. macOS only; nothing here is
//! analyzed on other targets, as every call site is behind `os_tag == .macos`.

const std = @import("std");
const log = std.log.scoped(.ziggui_cocoa);
const mod = @import("module.zig");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// An Objective-C object pointer (`id`).
const Id = ?*anyopaque;

/// AppKit's `NSSize`.
const NSSize = extern struct {
    const Self = @This();

    /// The width.
    width: f64,
    /// The height.
    height: f64,
};

/// AppKit's `NSPoint`.
const NSPoint = extern struct {
    const Self = @This();

    /// The x coordinate.
    x: f64,
    /// The y coordinate.
    y: f64,
};

/// AppKit's `NSRect`.
const NSRect = extern struct {
    const Self = @This();

    /// The origin.
    origin: NSPoint,
    /// The size.
    size: NSSize,
};

/// The Objective-C bridge and the AppKit objects it keeps: menu actions and
/// the status item. One per process (`shared`).
pub const Cocoa = struct {
    const Self = @This();

    /// Menu actions, indexed by each item's tag (they live for the process).
    actions: std.ArrayList(views.Callback) = .empty,

    /// The status item, while one exists.
    status_item: Id = null,

    /// The status item button's target object.
    status_target: Id = null,

    /// The status item's click callback.
    status_callback: ?views.Callback = null,

    /// The process's bridge.
    var shared_cocoa: Self = .{};

    extern "objc" fn objc_getClass(name: [*:0]const u8) Id;
    extern "objc" fn sel_registerName(name: [*:0]const u8) Id;
    extern "objc" fn objc_msgSend() void;

    extern "objc" fn objc_allocateClassPair(superclass: Id, name: [*:0]const u8, extra: usize) Id;
    extern "objc" fn objc_registerClassPair(class: Id) void;
    extern "objc" fn class_addMethod(class: Id, name: Id, implementation: *const anyopaque, types: [*:0]const u8) u8;

    /// The process's bridge.
    ///
    /// - Returns: the shared bridge.
    pub fn shared() *Self {
        return &shared_cocoa;
    }

    /// Transparent titlebar + full-size content + hidden title, and an empty
    /// unified toolbar so the titlebar is toolbar-height (the traffic lights
    /// sit inset, centred in a 52pt band).
    ///
    /// - `window`: the main window.
    pub fn unifyTitlebar(window: *sdl_c.SDL_Window) void {
        const ns_window: Id = sdl_c.SDL_GetPointerProperty(sdl_c.SDL_GetWindowProperties(window), sdl_c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
        if (ns_window == null) return;
        const full_size_content: u64 = 1 << 15;
        Self.send(void, ns_window, "setStyleMask:", .{Self.send(u64, ns_window, "styleMask", .{}) | full_size_content});
        Self.send(void, ns_window, "setTitlebarAppearsTransparent:", .{@as(u8, 1)});
        Self.send(void, ns_window, "setTitleVisibility:", .{@as(i64, 1)}); // NSWindowTitleHidden
        const toolbar = Self.send(Id, objc_getClass("NSToolbar"), "new", .{});
        Self.send(void, toolbar, "setShowsBaselineSeparator:", .{@as(u8, 0)});
        Self.send(void, ns_window, "setToolbar:", .{toolbar});
        Self.send(void, ns_window, "setToolbarStyle:", .{@as(i64, 3)}); // NSWindowToolbarStyleUnified
    }

    /// Marks this app's menu-bar icons as template images, so macOS draws them
    /// in the menu bar's own colour (white on a dark bar, black on a light
    /// one) like every native status item. SDL hands AppKit a plain image.
    /// The items live in this process's NSStatusBarWindows; their button is a
    /// public NSStatusBarButton.
    pub fn templateStatusIcons() void {
        const ns_app = Self.send(Id, objc_getClass("NSApplication"), "sharedApplication", .{});
        const windows = Self.send(Id, ns_app, "windows", .{});
        const button_class = objc_getClass("NSStatusBarButton");
        const count: u64 = Self.send(u64, windows, "count", .{});
        for (0..count) |index| {
            const ns_window = Self.send(Id, windows, "objectAtIndex:", .{@as(u64, index)});
            const view = Self.send(Id, ns_window, "contentView", .{}) orelse continue;
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
        const ns_window: Id = sdl_c.SDL_GetPointerProperty(sdl_c.SDL_GetWindowProperties(window), sdl_c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
        if (ns_window == null) return;
        Self.send(void, ns_window, "setOpaque:", .{@as(u8, 0)});
        Self.send(void, ns_window, "setBackgroundColor:", .{Self.send(Id, objc_getClass("NSColor"), "clearColor", .{})});
        const view = Self.send(Id, ns_window, "contentView", .{}) orelse return;
        const bounds = Self.send(NSRect, view, "bounds", .{});

        const container = Self.send(Id, Self.send(Id, objc_getClass("NSView"), "alloc", .{}), "initWithFrame:", .{bounds});
        Self.send(void, container, "setWantsLayer:", .{@as(u8, 1)});
        const layer = Self.send(Id, container, "layer", .{});
        if (layer != null) {
            Self.send(void, layer, "setCornerRadius:", .{radius});
            Self.send(void, layer, "setMasksToBounds:", .{@as(u8, 1)});
        }
        const effect = Self.send(Id, Self.send(Id, objc_getClass("NSVisualEffectView"), "alloc", .{}), "initWithFrame:", .{bounds});
        Self.send(void, effect, "setMaterial:", .{@as(i64, 6)}); // NSVisualEffectMaterialPopover
        Self.send(void, effect, "setBlendingMode:", .{@as(i64, 0)}); // behindWindow
        Self.send(void, effect, "setState:", .{@as(i64, 1)}); // active
        Self.send(void, effect, "setAutoresizingMask:", .{@as(u64, 18)}); // width|height sizable
        Self.send(void, container, "addSubview:", .{effect});
        Self.send(void, view, "removeFromSuperview", .{});
        Self.send(void, view, "setAutoresizingMask:", .{@as(u64, 18)});
        Self.send(void, container, "addSubview:", .{view});
        Self.send(void, ns_window, "setContentView:", .{container});
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
        const representation = Self.bitmapRepresentation(Self.send(Id, objc_getClass("NSBitmapImageRep"), "alloc", .{}), null, pixels_wide, pixels_high, 8, 4, 1, 0, Self.nsString("NSCalibratedRGBColorSpace"), 2, pixels_wide * 4, 32) orelse return false;
        const raw = Self.send([*c]u8, representation, "bitmapData", .{});
        if (raw == null) return false;
        const destination: [*]u8 = @ptrCast(raw);
        @memcpy(destination[0..rgba.len], rgba);
        // The bitmap is a 2x backing store, so the image's point size is half
        // its pixel size. Sized in pixels instead, a 36 px icon would sit in
        // the menu bar as a 36 pt image: twice the bar's height, dwarfing
        // every native status item.
        const size = NSSize{ .width = @as(f64, @floatFromInt(width)) / 2.0, .height = @as(f64, @floatFromInt(height)) / 2.0 };
        const image = Self.send(Id, Self.send(Id, objc_getClass("NSImage"), "alloc", .{}), "initWithSize:", .{size});
        if (image == null) return false;
        Self.send(void, image, "addRepresentation:", .{representation});
        Self.send(void, image, "setTemplate:", .{@as(u8, 1)});
        const bar = Self.send(Id, objc_getClass("NSStatusBar"), "systemStatusBar", .{});
        const item = Self.send(Id, bar, "statusItemWithLength:", .{@as(f64, -1)}); // NSVariableStatusItemLength
        if (item == null) return false;
        const button = Self.send(Id, item, "button", .{});
        if (button == null) return false;
        Self.send(void, button, "setImage:", .{image});
        if (tooltip.len > 0) Self.send(void, button, "setToolTip:", .{Self.nsString(tooltip)});
        const class = objc_allocateClassPair(objc_getClass("NSObject"), "ZigguiStatusItemTarget", 0) orelse return false;
        _ = class_addMethod(class, sel_registerName("click:"), @ptrCast(&Self.statusClick), "v@:@");
        objc_registerClassPair(class);
        const target = Self.send(Id, class, "new", .{});
        Self.send(void, button, "setTarget:", .{target});
        Self.send(void, button, "setAction:", .{sel_registerName("click:")});
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
            const bar = Self.send(Id, objc_getClass("NSStatusBar"), "systemStatusBar", .{});
            Self.send(void, bar, "removeStatusItem:", .{item});
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
        const ns_app = Self.send(Id, objc_getClass("NSApplication"), "sharedApplication", .{});
        const bar = Self.send(Id, ns_app, "mainMenu", .{}) orelse return;
        if (menus.len > 0) {
            while (Self.send(i64, bar, "numberOfItems", .{}) > 1) Self.send(void, bar, "removeItemAtIndex:", .{@as(i64, 1)});
        }
        const target = Self.menuTarget();
        if (settings) |callback| settings: {
            const app_item = Self.send(Id, bar, "itemAtIndex:", .{@as(i64, 0)}) orelse break :settings;
            const app_menu = Self.send(Id, app_item, "submenu", .{}) orelse break :settings;
            self.actions.append(std.heap.page_allocator, callback) catch break :settings;
            const tag: i64 = @intCast(self.actions.items.len - 1);
            // SDL's app menu has a disabled "Preferences… ⌘," (no action):
            // take it over, so there is one item and one ⌘, in its place.
            // Found by its key, not its title: macOS 13+ retitles it "Settings…".
            const preferences = Self.indexOfKey(app_menu, ",");
            const item = if (preferences >= 0)
                Self.send(Id, app_menu, "itemAtIndex:", .{preferences}) orelse break :settings
            else
                Self.send(Id, Self.send(Id, objc_getClass("NSMenuItem"), "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ Self.nsString("Settings…"), sel_registerName("fire:"), Self.nsString(",") });
            Self.send(void, item, "setTitle:", .{Self.nsString("Settings…")});
            Self.send(void, item, "setAction:", .{sel_registerName("fire:")});
            Self.send(void, item, "setTag:", .{tag});
            Self.send(void, item, "setTarget:", .{target});
            if (preferences < 0) {
                // No placeholder: after "About <app>" and a separator, as macOS apps place it.
                const at: i64 = @min(1, Self.send(i64, app_menu, "numberOfItems", .{}));
                Self.send(void, app_menu, "insertItem:atIndex:", .{ Self.send(Id, objc_getClass("NSMenuItem"), "separatorItem", .{}), at });
                Self.send(void, app_menu, "insertItem:atIndex:", .{ item, at + 1 });
            }
        }
        for (menus) |menu| {
            const holder = Self.send(Id, objc_getClass("NSMenuItem"), "new", .{});
            const submenu = Self.send(Id, Self.send(Id, objc_getClass("NSMenu"), "alloc", .{}), "initWithTitle:", .{Self.nsString(menu.title)});
            for (menu.items) |entry| {
                if (entry.title.len == 0) {
                    Self.send(void, submenu, "addItem:", .{Self.send(Id, objc_getClass("NSMenuItem"), "separatorItem", .{})});
                    continue;
                }
                const selector = sel_registerName(if (entry.selector) |name| name else "fire:");
                const item = Self.send(Id, Self.send(Id, objc_getClass("NSMenuItem"), "alloc", .{}), "initWithTitle:action:keyEquivalent:", .{ Self.nsString(entry.title), selector, Self.nsString(entry.key) });
                if (entry.key.len > 0) {
                    var mask: u64 = 1 << 20; // Command
                    if (entry.shift) mask |= 1 << 17;
                    if (entry.control) mask |= 1 << 18;
                    if (entry.option) mask |= 1 << 19;
                    Self.send(void, item, "setKeyEquivalentModifierMask:", .{mask});
                }
                if (entry.action) |callback| {
                    Self.send(void, item, "setTag:", .{@as(i64, @intCast(self.actions.items.len))});
                    self.actions.append(std.heap.page_allocator, callback) catch continue;
                    Self.send(void, item, "setTarget:", .{target});
                }
                Self.send(void, submenu, "addItem:", .{item});
            }
            Self.send(void, holder, "setSubmenu:", .{submenu});
            Self.send(void, bar, "addItem:", .{holder});
        }
    }

    /// Sends an Objective-C message with zero to three arguments.
    fn send(comptime Result: type, target: Id, selector: [*:0]const u8, args: anytype) Result {
        const Function = switch (args.len) {
            0 => fn (Id, Id) callconv(.c) Result,
            1 => fn (Id, Id, @TypeOf(args[0])) callconv(.c) Result,
            2 => fn (Id, Id, @TypeOf(args[0]), @TypeOf(args[1])) callconv(.c) Result,
            3 => fn (Id, Id, @TypeOf(args[0]), @TypeOf(args[1]), @TypeOf(args[2])) callconv(.c) Result,
            else => @compileError("zero to three arguments"),
        };
        const function: *const Function = @ptrCast(&objc_msgSend);
        return @call(.auto, function, .{ target, sel_registerName(selector) } ++ args);
    }

    /// Marks the status-bar buttons under `view` as template images.
    fn templateIn(view: Id, button_class: Id) void {
        if (Self.send(u8, view, "isKindOfClass:", .{button_class}) != 0) {
            const image = Self.send(Id, view, "image", .{}) orelse return;
            Self.send(void, image, "setTemplate:", .{@as(u8, 1)});
            Self.send(void, view, "setImage:", .{image});
            return;
        }
        const subviews = Self.send(Id, view, "subviews", .{});
        const count: u64 = Self.send(u64, subviews, "count", .{});
        for (0..count) |index| Self.templateIn(Self.send(Id, subviews, "objectAtIndex:", .{@as(u64, index)}), button_class);
    }

    /// An `NSString` from UTF-8.
    fn nsString(string: [*:0]const u8) Id {
        return Self.send(Id, objc_getClass("NSString"), "stringWithUTF8String:", .{string});
    }

    /// `fire:` on the one target object: runs the tagged action, then wakes the
    /// loop (a menu click produces no SDL event of its own).
    fn fire(_: Id, _: Id, sender: Id) callconv(.c) void {
        const self = Self.shared();
        const tag = Self.send(i64, sender, "tag", .{});
        if (tag >= 0 and tag < self.actions.items.len) {
            const callback = self.actions.items[@intCast(tag)];
            callback.function(callback.context);
        }
        mod.App.shared().wake();
    }

    /// The object every menu item targets, of a class registered with `fire:`.
    fn menuTarget() Id {
        const class = objc_allocateClassPair(objc_getClass("NSObject"), "ZigguiMenuTarget", 0) orelse return null;
        _ = class_addMethod(class, sel_registerName("fire:"), @ptrCast(&Self.fire), "v@:@");
        objc_registerClassPair(class);
        return Self.send(Id, class, "new", .{});
    }

    /// The status item's `click:`: runs its callback and wakes the loop.
    fn statusClick(_: Id, _: Id, _: Id) callconv(.c) void {
        if (Self.shared().status_callback) |callback| callback.call();
        mod.App.shared().wake();
    }

    /// `initWithBitmapDataPlanes:...` takes eleven arguments; `send` only
    /// covers zero to three, so it gets its own signature.
    fn bitmapRepresentation(target: Id, planes: ?*anyopaque, pixels_wide: i64, pixels_high: i64, bits_per_sample: i64, samples_per_pixel: i64, has_alpha: u8, is_planar: u8, color_space: Id, bitmap_format: u64, bytes_per_row: i64, bits_per_pixel: i64) Id {
        const Function = fn (Id, Id, ?*anyopaque, i64, i64, i64, i64, u8, u8, Id, u64, i64, i64) callconv(.c) Id;
        const function: *const Function = @ptrCast(&objc_msgSend);
        return @call(.auto, function, .{
            target,
            sel_registerName("initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bitmapFormat:bytesPerRow:bitsPerPixel:"),
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
    fn indexOfKey(menu: Id, key: [*:0]const u8) i64 {
        const wanted = Self.nsString(key);
        const count = Self.send(i64, menu, "numberOfItems", .{});
        var index: i64 = 0;
        while (index < count) : (index += 1) {
            const item = Self.send(Id, menu, "itemAtIndex:", .{index}) orelse continue;
            const equivalent = Self.send(Id, item, "keyEquivalent", .{}) orelse continue;
            if (Self.send(bool, equivalent, "isEqualToString:", .{wanted})) return index;
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
