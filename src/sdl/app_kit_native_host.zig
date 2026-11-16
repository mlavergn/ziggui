//! The macOS native-view host: each app `NSView` a `NativeView` shows sits in
//! a clipping container placed *above* SDL's Metal view in the window's
//! content view, framed each frame from its `NativeRegion`. Being above the
//! surface, nothing ziggui draws can cover it, so while an overlay is open
//! every container is hidden, and the view that held the keyboard gets it
//! back when the overlay closes.
//!
//! Clicks on a container reach its view through AppKit's hit testing and
//! never become SDL button events: the container absorbs any mouse event its
//! view passes up the responder chain (`absorb`), and the loop ignores any
//! that slip through (`contains`). Keys still reach SDL while a view holds the keyboard, because
//! `SDL3Application sendEvent:` feeds every key event to SDL before AppKit
//! routes it, so the loop offers ⌘ keys to the app's key handler and drops
//! the rest (`hasFocus`). SDL's text input is stopped while a view holds the
//! keyboard: with it on, SDL runs `interpretKeyEvents:` on every key, which
//! inserts through the first responder's input context, and the view then
//! gets the key again from AppKit, so every character would land twice. The
//! container's class (`ZigguiNativeContainer`) overrides `hitTest:` to stop it
//! the moment a press lands in a view, before the view takes the keyboard;
//! `release` starts it again, which puts SDL's text field back as first
//! responder. macOS only; nothing here is analyzed on other
//! targets, as `NativeBackend` reaches it only behind `os_tag == .macos`.

const std = @import("std");
const log = std.log.scoped(.ziggui_app_kit_native_host);
const mod = @import("module.zig");
const renderer = @import("renderer");
const views = @import("views");
const sdl_c = @import("sdl_c");

/// `NSWindowAbove`, for `addSubview:positioned:relativeTo:`.
const window_above: i64 = 1;

/// The runtime's `struct objc_super`, for a message to a superclass's method.
const Super = extern struct {
    const Self = @This();

    /// The object the message is to.
    receiver: mod.Id,
    /// The class whose method answers it.
    super_class: mod.Id,
};

/// How many platform views one window places at once.
const max_hosts = 16;

/// One app view and the container that places and clips it.
const Host = struct {
    const Self = @This();

    /// The app's `NSView`, retained while placed: the app may take it out and
    /// release it between frames, and `present` still asks for its superview.
    view: mod.Id,
    /// The clipping `NSView`, in the window's content view above SDL's.
    container: mod.Id,
    /// The corner radius last set.
    corner_radius: f64 = 0,
    /// The container is hidden.
    hidden: bool = true,
    /// The part on screen last placed, in the window's points (top-left origin).
    visible: renderer.Rect = .{},
    /// The frame (`AppKitNativeHost.frame_number`) it was last shown in.
    shown_in_frame: u64 = 0,
};

/// The macOS host behind every `NativeView`.
pub const AppKitNativeHost = struct {
    const Self = @This();

    /// The host places views over the window's surface.
    pub const presents = true;

    /// The views placed so far, in the order they first appeared.
    var hosts: [max_hosts]Host = undefined;

    /// How many of `hosts` are live.
    var host_count: usize = 0;

    /// Counts `present` calls, so a view not shown in the latest is hidden.
    var frame_number: u64 = 0;

    /// The window the views are placed in, once one was.
    var ns_window: mod.Id = null;

    /// The content view's resizes, after which frames keep coming until a
    /// transition has settled.
    var settle: mod.ResizeSettle = .{};

    /// Every container is hidden for an open overlay.
    var suppressed: bool = false;

    /// The SDL window the views are placed in, whose text input `claim` stops and `release` starts.
    var sdl_window: ?*sdl_c.SDL_Window = null;

    /// SDL's text input is stopped for a placed view holding the keyboard.
    var text_input_stopped: bool = false;

    /// The mouse messages a container absorbs rather than pass up to SDL.
    const absorbed_events = [_][:0]const u8{
        "mouseDown:",      "mouseUp:",      "mouseDragged:",
        "rightMouseDown:", "rightMouseUp:", "rightMouseDragged:",
        "otherMouseDown:", "otherMouseUp:", "otherMouseDragged:",
        "scrollWheel:",
    };

    extern "objc" fn objc_allocateClassPair(superclass: mod.Id, name: [*:0]const u8, extra: usize) mod.Id;
    extern "objc" fn objc_registerClassPair(class: mod.Id) void;
    extern "objc" fn class_addMethod(class: mod.Id, name: mod.Id, implementation: *const anyopaque, types: [*:0]const u8) u8;
    extern "objc" fn objc_msgSendSuper() void;

    /// The view that held the keyboard when an overlay hid it, to refocus when
    /// the overlay closes; retained while held (`keepRefocus`).
    var refocus: mod.Id = null;

    /// Puts each region's view where its `NativeView` is, and hides every view
    /// no `NativeView` showed this frame, or all of them while an overlay is
    /// open. Runs on the main thread after the view tree painted.
    ///
    /// - `window`: the main window.
    /// - `regions`: the frame's `NativeView` regions, in points.
    /// - `overlay_open`: a sheet, alert, popover or menu is drawn this frame.
    pub fn present(window: *sdl_c.SDL_Window, regions: []const views.NativeRegion, overlay_open: bool) void {
        frame_number += 1;
        if (regions.len == 0 and host_count == 0) return;
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        sdl_window = window;
        ns_window = sdl_c.SDL_GetPointerProperty(sdl_c.SDL_GetWindowProperties(window), sdl_c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
        const content = mod.ObjectiveC.send(mod.Id, ns_window, "contentView", .{});
        if (content == null) return;
        // A full-screen transition moves the views as it animates: frames
        // keep coming until it has settled, so they are placed after it.
        const size = mod.ObjectiveC.send(mod.CGRect, content, "bounds", .{}).size;
        _ = settle.note(size.width, size.height, views.FrameClock.shared().time());

        // An overlay opening takes the keyboard from the view, to give back
        // when it closes.
        if (overlay_open and !suppressed) {
            suppressed = true;
            Self.keepRefocus(Self.focusedResponder());
            if (refocus != null) Self.release();
        }
        const reopening = !overlay_open and suppressed;
        if (reopening) suppressed = false;

        mod.ObjectiveC.send(void, mod.ObjectiveC.class("CATransaction"), "begin", .{});
        mod.ObjectiveC.send(void, mod.ObjectiveC.class("CATransaction"), "setDisableActions:", .{@as(u8, 1)});
        for (regions) |region| {
            const host = Self.hostFor(content, region.handle) orelse continue;
            host.shown_in_frame = frame_number;
            if (!suppressed) Self.place(host, content, region);
        }
        var index: usize = 0;
        while (index < host_count) {
            const host = &hosts[index];
            // The app took its view out of the container: the host goes too.
            if (mod.ObjectiveC.send(mod.Id, host.view, "superview", .{}) != host.container) {
                Self.drop(index);
                continue;
            }
            if (suppressed or host.shown_in_frame != frame_number) Self.hide(host);
            index += 1;
        }
        mod.ObjectiveC.send(void, mod.ObjectiveC.class("CATransaction"), "commit", .{});

        if (reopening) {
            if (refocus) |responder| if (Self.holds(responder)) {
                Self.claim();
                _ = mod.ObjectiveC.send(u8, ns_window, "makeFirstResponder:", .{responder});
            };
            Self.keepRefocus(null);
        }
        // A view that took the keyboard some other way (a script, the Tab key)
        // still must not have SDL insert its keys a second time; and a press
        // on a view that never took it (a plain view, a map) leaves SDL's text
        // input stopped, which goes back on here.
        if (Self.focusedResponder() != null) {
            Self.claim();
        } else if (text_input_stopped and !suppressed) {
            Self.release();
        }
    }

    /// Reports whether one of the placed views, or a view inside one, is the
    /// window's first responder.
    ///
    /// - Returns: true while a placed view holds the keyboard.
    pub fn hasFocus() bool {
        return Self.focusedResponder() != null;
    }

    /// Hands the keyboard back to SDL: starts its text input again, which
    /// makes SDL's text field first responder, or else gives it to the
    /// content view (SDL's). Does nothing while no placed view holds it and
    /// SDL's text input runs.
    pub fn release() void {
        const focused = Self.focusedResponder() != null;
        if (!focused and !text_input_stopped) return;
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        if (text_input_stopped) {
            text_input_stopped = false;
            if (sdl_window) |window| _ = sdl_c.SDL_StartTextInput(window);
        }
        if (Self.focusedResponder() == null) return;
        _ = mod.ObjectiveC.send(u8, ns_window, "makeFirstResponder:", .{mod.ObjectiveC.send(mod.Id, ns_window, "contentView", .{})});
    }

    /// Reports whether a point falls on a shown view.
    ///
    /// - `point`: the point, in the window's points.
    /// - Returns: true over a shown view.
    pub fn contains(point: renderer.Point) bool {
        for (hosts[0..host_count]) |*host| {
            if (!host.hidden and host.visible.contains(point)) return true;
        }
        return false;
    }

    /// Takes every container out of the window: the loop is ending, and the
    /// window goes before the app's views do.
    pub fn detachAll() void {
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        while (host_count > 0) Self.drop(host_count - 1);
        if (text_input_stopped) if (sdl_window) |window| {
            _ = sdl_c.SDL_StartTextInput(window);
        };
        text_input_stopped = false;
        ns_window = null;
        sdl_window = null;
        Self.keepRefocus(null);
        suppressed = false;
    }

    /// Stops SDL's text input for a placed view taking the keyboard, so SDL
    /// does not insert its keys a second time, and unfocuses ziggui's field.
    /// Runs before the view is first responder when a press lands in it.
    fn claim() void {
        if (text_input_stopped) return;
        const window = sdl_window orelse return;
        text_input_stopped = true;
        _ = sdl_c.SDL_StopTextInput(window);
        // The press never reached ziggui, so its field would keep a caret, and
        // the keys, once the view gives the keyboard back.
        views.Focus.shared().clear();
    }

    /// The container class: an `NSView` whose `hitTest:` claims the keyboard
    /// for its view when a press lands in it. Registered on first use.
    ///
    /// - Returns: the class, or null when the runtime will not register it.
    fn containerClass() mod.Id {
        const existing = mod.ObjectiveC.class("ZigguiNativeContainer");
        if (existing != null) return existing;
        const class = objc_allocateClassPair(mod.ObjectiveC.class("NSView"), "ZigguiNativeContainer", 0);
        if (class == null) return null;
        _ = class_addMethod(class, mod.ObjectiveC.selectorNamed("hitTest:"), @ptrCast(&Self.hitTest), "@@:{CGPoint=dd}");
        for (absorbed_events) |name| _ = class_addMethod(class, mod.ObjectiveC.selectorNamed(name), @ptrCast(&Self.absorb), "v@:@");
        objc_registerClassPair(class);
        return class;
    }

    /// `-[ZigguiNativeContainer hitTest:]`: AppKit's hit test, which on a
    /// mouse press inside the view stops SDL's text input before the view
    /// takes the keyboard.
    ///
    /// - `self_object`: the container.
    /// - `selector`: `hitTest:`.
    /// - `point`: the point, in the container's superview's coordinates.
    /// - Returns: the view hit, or null.
    fn hitTest(self_object: mod.Id, selector: mod.Id, point: mod.CGPoint) callconv(.c) mod.Id {
        const receiver = Super{ .receiver = self_object, .super_class = mod.ObjectiveC.class("NSView") };
        const send_super: *const fn (*const Super, mod.Id, mod.CGPoint) callconv(.c) mod.Id = @ptrCast(&objc_msgSendSuper);
        const hit = send_super(&receiver, selector, point);
        if (hit == null) return hit;
        // A press is what hit-tests with a button down; hovering and cursor
        // updates hit-test too, with none, and must leave SDL's typing alone.
        if (mod.ObjectiveC.send(u64, mod.ObjectiveC.class("NSEvent"), "pressedMouseButtons", .{}) != 0) Self.claim();
        return hit;
    }

    /// `-[ZigguiNativeContainer mouseDown:]` and the other `absorbed_events`:
    /// drops a mouse event the view passed up its responder chain, since a
    /// press on a placed view is the view's alone, handled or not.
    ///
    /// - `self_object`: the container.
    /// - `selector`: the message.
    /// - `event`: the `NSEvent`.
    fn absorb(self_object: mod.Id, selector: mod.Id, event: mod.Id) callconv(.c) void {
        // `WKWebView` hands an event its page did not consume to its next
        // responder, late, once the web content has answered. Passed on to
        // SDL's view, that press arrives as a new SDL button-down with no
        // button-up after it, and SDL drops the next real press (on a ziggui
        // field) as a repeat.
        _ = self_object;
        _ = selector;
        _ = event;
    }

    /// The host placing `view`, made on its first frame.
    ///
    /// - `content`: the window's content view.
    /// - `view`: the app's `NSView`.
    /// - Returns: the host, or null when every slot is taken.
    fn hostFor(content: mod.Id, view: *anyopaque) ?*Host {
        for (hosts[0..host_count]) |*host| {
            if (host.view == @as(mod.Id, view)) return host;
        }
        if (host_count == max_hosts) {
            log.warn("native view not placed: {d} are already shown", .{max_hosts});
            return null;
        }
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const class = Self.containerClass();
        const container = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, if (class != null) class else mod.ObjectiveC.class("NSView"), "alloc", .{}), "initWithFrame:", .{mod.CGRect{}});
        mod.ObjectiveC.send(void, container, "setWantsLayer:", .{@as(u8, 1)});
        mod.ObjectiveC.send(void, mod.ObjectiveC.send(mod.Id, container, "layer", .{}), "setMasksToBounds:", .{@as(u8, 1)});
        mod.ObjectiveC.send(void, container, "setHidden:", .{@as(u8, 1)});
        mod.ObjectiveC.send(void, container, "addSubview:", .{@as(mod.Id, view)});
        mod.ObjectiveC.send(void, content, "addSubview:positioned:relativeTo:", .{ container, window_above, @as(mod.Id, null) });
        hosts[host_count] = .{ .view = mod.ObjectiveC.retain(view), .container = container };
        host_count += 1;
        return &hosts[host_count - 1];
    }

    /// Frames a host's container to the region's visible part and its view to
    /// the whole region inside it, then shows it.
    ///
    /// - `host`: the host.
    /// - `content`: the window's content view.
    /// - `region`: where its `NativeView` is this frame.
    fn place(host: *Host, content: mod.Id, region: views.NativeRegion) void {
        if (mod.ObjectiveC.send(mod.Id, host.container, "superview", .{}) != content) {
            mod.ObjectiveC.send(void, host.container, "removeFromSuperview", .{});
            mod.ObjectiveC.send(void, content, "addSubview:positioned:relativeTo:", .{ host.container, window_above, @as(mod.Id, null) });
        }
        const visible = region.visible;
        if (visible.width <= 0 or visible.height <= 0) {
            Self.hide(host);
            return;
        }
        host.visible = visible;
        const bounds = mod.ObjectiveC.send(mod.CGRect, content, "bounds", .{});
        const flipped = mod.ObjectiveC.send(u8, content, "isFlipped", .{}) != 0;
        const top: f64 = if (flipped) visible.y else bounds.size.height - visible.y - visible.height;
        const container_frame = mod.CGRect{ .origin = .{ .x = visible.x, .y = top }, .size = .{ .width = visible.width, .height = visible.height } };
        // Compared with the frame AppKit holds: a full-screen transition
        // moves the views behind our back.
        if (!container_frame.eql(mod.ObjectiveC.send(mod.CGRect, host.container, "frame", .{}))) {
            mod.ObjectiveC.send(void, host.container, "setFrame:", .{container_frame});
        }
        // The container is bottom-up: the region's top sits `rect.y - visible.y` below its top edge.
        const view_frame = mod.CGRect{
            .origin = .{ .x = region.rect.x - visible.x, .y = visible.height - (region.rect.y - visible.y) - region.rect.height },
            .size = .{ .width = region.rect.width, .height = region.rect.height },
        };
        if (!view_frame.eql(mod.ObjectiveC.send(mod.CGRect, host.view, "frame", .{}))) {
            mod.ObjectiveC.send(void, host.view, "setFrame:", .{view_frame});
        }
        const radius: f64 = region.corner_radius;
        if (radius != host.corner_radius) {
            mod.ObjectiveC.send(void, mod.ObjectiveC.send(mod.Id, host.container, "layer", .{}), "setCornerRadius:", .{radius});
            host.corner_radius = radius;
        }
        if (host.hidden) {
            mod.ObjectiveC.send(void, host.container, "setHidden:", .{@as(u8, 0)});
            host.hidden = false;
        }
    }

    /// Hides a host's container, handing the keyboard back to SDL first when
    /// its view held it.
    ///
    /// - `host`: the host.
    fn hide(host: *Host) void {
        if (host.hidden) return;
        if (Self.inside(Self.firstResponder(), host.container)) Self.release();
        mod.ObjectiveC.send(void, host.container, "setHidden:", .{@as(u8, 1)});
        host.hidden = true;
        host.visible = .{};
    }

    /// Takes a host's container out of the window and frees its slot. The
    /// app's view leaves with the container, and stays the app's.
    ///
    /// - `index`: the host's slot.
    fn drop(index: usize) void {
        const host = &hosts[index];
        if (Self.inside(Self.firstResponder(), host.container)) Self.release();
        if (mod.ObjectiveC.send(mod.Id, host.view, "superview", .{}) == host.container) mod.ObjectiveC.send(void, host.view, "removeFromSuperview", .{});
        mod.ObjectiveC.send(void, host.container, "removeFromSuperview", .{});
        mod.ObjectiveC.release(host.container);
        mod.ObjectiveC.release(host.view);
        hosts[index] = hosts[host_count - 1];
        host_count -= 1;
    }

    /// Holds `responder` as the view to refocus, retained, releasing the one
    /// held before.
    ///
    /// - `responder`: the responder, or null to hold none.
    fn keepRefocus(responder: mod.Id) void {
        const previous = refocus;
        refocus = mod.ObjectiveC.retain(responder);
        mod.ObjectiveC.release(previous);
    }

    /// The window's first responder, or null with no window.
    ///
    /// - Returns: the responder.
    fn firstResponder() mod.Id {
        if (ns_window == null) return null;
        return mod.ObjectiveC.send(mod.Id, ns_window, "firstResponder", .{});
    }

    /// The first responder when it is a placed view or inside one.
    ///
    /// - Returns: the responder, or null when SDL (or nothing) holds the keyboard.
    fn focusedResponder() mod.Id {
        const responder = Self.firstResponder();
        if (responder == null) return null;
        for (hosts[0..host_count]) |*host| {
            if (Self.inside(responder, host.container)) return responder;
        }
        return null;
    }

    /// Reports whether a responder still sits inside one of the placed views.
    ///
    /// - `responder`: the responder.
    /// - Returns: true when a container holds it.
    fn holds(responder: mod.Id) bool {
        for (hosts[0..host_count]) |*host| {
            if (Self.inside(responder, host.container)) return true;
        }
        return false;
    }

    /// Reports whether a responder is a view inside `container`.
    ///
    /// - `responder`: the responder (a view, the window, or null).
    /// - `container`: the container.
    /// - Returns: true for a view in the container's tree.
    fn inside(responder: mod.Id, container: mod.Id) bool {
        if (responder == null) return false;
        if (mod.ObjectiveC.send(u8, responder, "isKindOfClass:", .{mod.ObjectiveC.class("NSView")}) == 0) return false;
        return mod.ObjectiveC.send(u8, responder, "isDescendantOf:", .{container}) != 0;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "with nothing placed the host holds no focus and no point" {
    // Asking for focus messages the Objective-C runtime, which only macOS links.
    if (mod.os_tag != .macos) return error.SkipZigTest;
    try std.testing.expect(AppKitNativeHost.presents);
    try std.testing.expect(!AppKitNativeHost.hasFocus());
    try std.testing.expect(!AppKitNativeHost.contains(.{ .x = 10, .y = 10 }));
}
