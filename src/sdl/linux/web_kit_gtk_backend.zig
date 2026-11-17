//! The Linux `WebPageBackend`: a WebKitGTK `WebKitWebView` per `WebPage`
//! (the 4.1 API, on GTK 3; see `Gtk` for why), placed by the native-view
//! host (`GtkNativeHost`) where its `WebView` is. GTK is loaded at run time,
//! so an app runs without it; a page then reports that the web view could
//! not be made, as it does where SDL's window is not on X11.
//!
//! Bridges keep the macOS rules: a page posts with
//! `window.webkit.messageHandlers.<name>.postMessage(text)`, heard only from
//! the top frame of the first origin the page loaded. WebKitGTK tells a
//! handler neither the frame nor its address, so the handlers live in an
//! isolated script world (`world`) no page script can reach, and a script
//! injected into the top frame alone carries messages to them: a shim in the
//! page's world posts a DOM event the top document alone hears, and the
//! bridge script in the isolated world hands it to the handler. The page's
//! address is checked against the trusted origin as each message lands.
//! Property notifications report the address and title, the back-forward
//! list's changes the history, and `load-failed` the failures (WebKit's own
//! error page is not shown, as `WKWebView` shows none). Linux only; other
//! targets reach it only behind `os_tag == .linux`.

const std = @import("std");
const log = std.log.scoped(.ziggui_web_kit_gtk_backend);
const mod = @import("module.zig");
const views = @import("views");

/// `WEBKIT_LOAD_COMMITTED`: a load started showing its page.
const load_committed: c_int = 2;

/// `WEBKIT_LOAD_FINISHED`.
const load_finished: c_int = 3;

/// `WEBKIT_NETWORK_ERROR_CANCELLED`: a load the user or a newer load stopped.
const network_error_cancelled: c_int = 302;

/// `WEBKIT_POLICY_ERROR_FRAME_LOAD_INTERRUPTED_BY_POLICY_CHANGE`: a load
/// turned into something else (a download), not a failure either.
const policy_error_interrupted: c_int = 102;

/// `WEBKIT_USER_CONTENT_INJECT_TOP_FRAME`.
const inject_top_frame: c_int = 1;

/// `WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START`.
const inject_at_document_start: c_int = 0;

/// The isolated script world the bridge handlers live in.
const world = "ziggui";

/// The DOM event the shim posts and the bridge script hears.
const bridge_event = "ziggui-bridge";

/// The shim in the page's own world: `window.webkit.messageHandlers.<name>`
/// as on macOS, posting each message as a DOM event on the top document.
const page_script =
    \\(() => {
    \\  if (window.webkit) return;
    \\  const post = (name, body) => document.dispatchEvent(new CustomEvent('
++ bridge_event ++
    \\', { detail: JSON.stringify({ name: name, body: body === undefined ? null : body }) }));
    \\  const handlers = new Proxy({}, { get: (_, name) => typeof name === 'string' ? Object.freeze({ postMessage: (body) => post(name, body) }) : undefined });
    \\  Object.defineProperty(window, 'webkit', { value: Object.freeze({ messageHandlers: handlers }) });
    \\})();
;

/// The bridge script in the isolated world: hands each message to the
/// handler of its name, when there is one.
const bridge_script =
    \\document.addEventListener('
++ bridge_event ++
    \\', (event) => {
    \\  let message;
    \\  try { message = JSON.parse(event.detail); } catch (error) { return; }
    \\  const handlers = window.webkit && window.webkit.messageHandlers;
    \\  const handler = handlers && typeof message.name === 'string' ? handlers[message.name] : undefined;
    \\  if (handler) handler.postMessage(message.body);
    \\});
;

/// One bridge of a page: the name its messages arrive under, and the page.
const Bridge = struct {
    const Self = @This();

    /// The page it reports to.
    native: *NativePage,
    /// The bridge's name, owned.
    name: [:0]u8,
};

/// One `WebPage`'s WebKit objects (each referenced) and what it reports; a
/// node of the list of live pages.
const NativePage = struct {
    const Self = @This();

    /// The page it reports to.
    page: *views.WebPage,
    /// The `WebKitWebView`.
    view: *anyopaque,
    /// Its `WebKitUserContentManager`, where the bridges are registered.
    manager: *anyopaque,
    /// Its back-forward list, owned by the view.
    history: ?*anyopaque,
    /// The bridges registered, each owned.
    bridges: std.ArrayList(*Bridge) = .empty,
    /// The origin the bridges hear (`WebPage` tells it: the first address
    /// the app asked for), owned, or null before it is told, when they hear
    /// none.
    trusted_url: ?[:0]u8 = null,
    /// Why the last load failed, until a load commits.
    failure: [512]u8 = undefined,
    /// How many bytes of `failure` are used.
    failure_length: usize = 0,
    /// The next live page.
    next: ?*Self = null,
    /// The previous live page.
    previous: ?*Self = null,

    /// Tells the page what it shows now: its address, title, history and
    /// failure.
    ///
    /// - `self`: the page.
    /// - `api`: GTK's entry points.
    fn report(self: *Self, api: *const mod.GtkApi) void {
        WebKitGtkBackend.delivering += 1;
        defer WebKitGtkBackend.delivering -= 1;
        self.page.update(.{
            .url = WebKitGtkBackend.spanOf(api.webkit_web_view_get_uri(self.view)),
            .title = WebKitGtkBackend.spanOf(api.webkit_web_view_get_title(self.view)),
            .failure = self.failure[0..self.failure_length],
            .can_go_back = api.webkit_web_view_can_go_back(self.view) != 0,
            .can_go_forward = api.webkit_web_view_can_go_forward(self.view) != 0,
        });
    }
};

/// The WebKitGTK web view behind every `WebPage` on Linux.
pub const WebKitGtkBackend = struct {
    const Self = @This();

    /// The backend `WebPage`s are made with.
    pub const backend: views.WebPageBackend = .{
        .create = Self.create,
        .destroy = Self.destroy,
        .view = Self.view,
        .trust = Self.trust,
        .load = Self.load,
        .go_back = Self.goBack,
        .go_forward = Self.goForward,
        .reload = Self.reload,
        .add_bridge = Self.addBridge,
    };

    /// The first live page, or null.
    var first: ?*NativePage = null;

    /// How many WebKit notifications are being delivered to the app now
    /// (nested): a page destroyed from inside one (an `onChange` or
    /// `onMessage` that frees it) has its WebKit objects released once GLib
    /// is idle, so they outlive the notification WebKit is still in.
    var delivering: u32 = 0;

    /// Makes a `WebKitWebView` with nothing loaded, its bridge scripts and
    /// its notifications.
    ///
    /// - `page`: the page it reports to.
    /// - Returns: the handle, or null where GTK cannot run or WebKit will not
    ///   make a view.
    fn create(page: *views.WebPage) ?*anyopaque {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const api = mod.GtkNativeHost.toolkit() orelse return null;
        const manager = api.webkit_user_content_manager_new() orelse return null;
        const web_view = api.webkit_web_view_new_with_user_content_manager(manager) orelse {
            api.g_object_unref(manager);
            return null;
        };
        // A new widget's reference is floating: this one is the page's.
        _ = api.g_object_ref_sink(web_view);
        const native = std.heap.c_allocator.create(NativePage) catch {
            api.g_object_unref(web_view);
            api.g_object_unref(manager);
            return null;
        };
        native.* = .{ .page = page, .view = web_view, .manager = manager, .history = api.webkit_web_view_get_back_forward_list(web_view), .next = first };
        Self.addScript(api, manager, page_script, null);
        Self.addScript(api, manager, bridge_script, world);
        Self.connect(api, web_view, "notify::uri", &Self.onProperty, native);
        Self.connect(api, web_view, "notify::title", &Self.onProperty, native);
        Self.connect(api, web_view, "load-changed", &Self.onLoadChanged, native);
        Self.connect(api, web_view, "load-failed", &Self.onLoadFailed, native);
        if (native.history) |history| Self.connect(api, history, "changed", &Self.onHistory, native);
        if (first) |head| head.previous = native;
        first = native;
        return native;
    }

    /// Stops the page, takes its view out of the window and frees it.
    ///
    /// - `handle`: the page.
    fn destroy(handle: *anyopaque) void {
        const native = Self.nativeOf(handle);
        const api = mod.Gtk.running() orelse return;
        Self.detach(api, native);
        // Inside a WebKit notification (the app freed the page from a
        // callback), WebKit is still using these: GLib frees them once idle.
        // Outside one, at once.
        if (delivering > 0) {
            _ = api.g_idle_add(Self.unrefLater, native.view);
            _ = api.g_idle_add(Self.unrefLater, native.manager);
        } else {
            api.g_object_unref(native.view);
            api.g_object_unref(native.manager);
        }
        for (native.bridges.items) |bridge| {
            std.heap.c_allocator.free(bridge.name);
            std.heap.c_allocator.destroy(bridge);
        }
        native.bridges.deinit(std.heap.c_allocator);
        if (native.trusted_url) |trusted| std.heap.c_allocator.free(trusted);
        if (native.previous) |previous| previous.next = native.next else first = native.next;
        if (native.next) |next| next.previous = native.previous;
        std.heap.c_allocator.destroy(native);
    }

    /// Stops a page and takes it out of everything that reaches it: its
    /// notifications, its bridges, its load, and the window.
    ///
    /// - `api`: GTK's entry points.
    /// - `native`: the page.
    fn detach(api: *const mod.GtkApi, native: *NativePage) void {
        _ = api.g_signal_handlers_disconnect_matched(native.view, mod.Gtk.signal_match_data, 0, 0, null, null, native);
        if (native.history) |history| _ = api.g_signal_handlers_disconnect_matched(history, mod.Gtk.signal_match_data, 0, 0, null, null, native);
        for (native.bridges.items) |bridge| {
            _ = api.g_signal_handlers_disconnect_matched(native.manager, mod.Gtk.signal_match_data, 0, 0, null, null, bridge);
            api.webkit_user_content_manager_unregister_script_message_handler_in_world(native.manager, bridge.name, world);
        }
        api.webkit_user_content_manager_remove_all_scripts(native.manager);
        // Stopped and blanked now: the native-view host keeps the view until
        // its next frame drops it, and a page left running would keep
        // loading, and playing its sound, until then.
        api.webkit_web_view_stop_loading(native.view);
        api.webkit_web_view_load_uri(native.view, "about:blank");
        // The native-view host drops a view taken out of its window.
        if (api.gtk_widget_get_parent(native.view)) |parent| api.gtk_container_remove(parent, native.view);
    }

    /// The `WebKitWebView`, for the native-view host to place.
    ///
    /// - `handle`: the page.
    /// - Returns: the view.
    fn view(handle: *anyopaque) ?*anyopaque {
        return Self.nativeOf(handle).view;
    }

    /// Sets the origin the bridges hear; a copy that cannot be made leaves
    /// them hearing none.
    ///
    /// - `handle`: the page.
    /// - `url`: the trusted address.
    fn trust(handle: *anyopaque, url: [:0]const u8) void {
        const native = Self.nativeOf(handle);
        if (native.trusted_url) |trusted| std.heap.c_allocator.free(trusted);
        native.trusted_url = std.heap.c_allocator.dupeSentinel(u8, url, 0) catch null;
    }

    /// Loads `url`.
    ///
    /// - `handle`: the page.
    /// - `url`: the address.
    /// - Returns: false when it is not an absolute address.
    fn load(handle: *anyopaque, url: [:0]const u8) bool {
        if (!Self.isAddress(url)) return false;
        const api = mod.Gtk.running() orelse return false;
        api.webkit_web_view_load_uri(Self.nativeOf(handle).view, url);
        return true;
    }

    /// Goes back one page, if the history has one.
    ///
    /// - `handle`: the page.
    fn goBack(handle: *anyopaque) void {
        const api = mod.Gtk.running() orelse return;
        api.webkit_web_view_go_back(Self.nativeOf(handle).view);
    }

    /// Goes forward one page, if the history has one.
    ///
    /// - `handle`: the page.
    fn goForward(handle: *anyopaque) void {
        const api = mod.Gtk.running() orelse return;
        api.webkit_web_view_go_forward(Self.nativeOf(handle).view);
    }

    /// Loads the page showing again.
    ///
    /// - `handle`: the page.
    fn reload(handle: *anyopaque) void {
        const api = mod.Gtk.running() orelse return;
        api.webkit_web_view_reload(Self.nativeOf(handle).view);
    }

    /// Lets the page post messages under `name`, replacing a bridge of that
    /// name.
    ///
    /// - `handle`: the page.
    /// - `name`: the bridge's name.
    fn addBridge(handle: *anyopaque, name: [:0]const u8) void {
        const native = Self.nativeOf(handle);
        const api = mod.Gtk.running() orelse return;
        // Registering a name already taken fails: it goes first.
        api.webkit_user_content_manager_unregister_script_message_handler_in_world(native.manager, name, world);
        if (api.webkit_user_content_manager_register_script_message_handler_in_world(native.manager, name, world) == 0) {
            log.warn("bridge {s} not registered", .{name});
            return;
        }
        for (native.bridges.items) |bridge| {
            if (std.mem.eql(u8, bridge.name, name)) return;
        }
        const bridge = std.heap.c_allocator.create(Bridge) catch return;
        const owned = std.heap.c_allocator.dupeSentinel(u8, name, 0) catch {
            std.heap.c_allocator.destroy(bridge);
            return;
        };
        bridge.* = .{ .native = native, .name = owned };
        native.bridges.append(std.heap.c_allocator, bridge) catch {
            std.heap.c_allocator.free(owned);
            std.heap.c_allocator.destroy(bridge);
            return;
        };
        var signal: [256]u8 = undefined;
        const detailed = std.mem.printSentinel(&signal, "script-message-received::{s}", .{name}, 0) catch {
            log.warn("bridge {s} not heard: its name is too long", .{name});
            return;
        };
        Self.connect(api, native.manager, detailed, &Self.onMessage, bridge);
    }

    /// Adds a script run at the start of every top-frame document.
    ///
    /// - `api`: GTK's entry points.
    /// - `manager`: the page's content manager.
    /// - `source`: the script.
    /// - `world_name`: the isolated world it runs in, or null for the page's own.
    fn addScript(api: *const mod.GtkApi, manager: *anyopaque, source: [:0]const u8, world_name: ?[:0]const u8) void {
        const script = if (world_name) |name|
            api.webkit_user_script_new_for_world(source, inject_top_frame, inject_at_document_start, name, null, null)
        else
            api.webkit_user_script_new(source, inject_top_frame, inject_at_document_start, null, null);
        const made = script orelse {
            log.warn("bridge script not added", .{});
            return;
        };
        api.webkit_user_content_manager_add_script(manager, made);
        api.webkit_user_script_unref(made);
    }

    /// Connects a signal handler, `data` its last argument.
    ///
    /// - `api`: GTK's entry points.
    /// - `instance`: the object.
    /// - `signal`: the signal's (detailed) name.
    /// - `handler`: the C handler.
    /// - `data`: its data.
    fn connect(api: *const mod.GtkApi, instance: *anyopaque, signal: [*:0]const u8, handler: *const anyopaque, data: *anyopaque) void {
        if (api.g_signal_connect_data(instance, signal, handler, data, null, 0) == 0) log.warn("signal {s} not connected", .{signal});
    }

    /// `notify::uri` and `notify::title`: the address or title changed.
    ///
    /// - `object`: the view; unused.
    /// - `property`: the property's `GParamSpec`; unused.
    /// - `data`: the page.
    fn onProperty(object: *anyopaque, property: ?*anyopaque, data: *anyopaque) callconv(.c) void {
        _ = object;
        _ = property;
        const api = mod.Gtk.running() orelse return;
        Self.nativeOf(data).report(api);
    }

    /// `changed` on the back-forward list: the history moved.
    ///
    /// - `list`: the list; unused.
    /// - `added`: the item added, if any; unused.
    /// - `removed`: the items removed; unused.
    /// - `data`: the page.
    fn onHistory(list: *anyopaque, added: ?*anyopaque, removed: ?*anyopaque, data: *anyopaque) callconv(.c) void {
        _ = list;
        _ = added;
        _ = removed;
        const api = mod.Gtk.running() orelse return;
        Self.nativeOf(data).report(api);
    }

    /// `load-changed`: a page started showing (no failure stands), or a load
    /// finished.
    ///
    /// - `web_view`: the view; unused.
    /// - `load_event`: the `WebKitLoadEvent`.
    /// - `data`: the page.
    fn onLoadChanged(web_view: *anyopaque, load_event: c_int, data: *anyopaque) callconv(.c) void {
        _ = web_view;
        const api = mod.Gtk.running() orelse return;
        const native = Self.nativeOf(data);
        if (load_event == load_committed) {
            native.failure_length = 0;
            native.report(api);
        } else if (load_event == load_finished) {
            native.report(api);
        }
    }

    /// `load-failed`: keeps the error's message as the failure; a cancelled
    /// or redirected load is none. WebKit's error page is not shown.
    ///
    /// - `web_view`: the view; unused.
    /// - `load_event`: the `WebKitLoadEvent`; unused.
    /// - `failing_uri`: the address that failed; unused.
    /// - `failure`: the `GError`.
    /// - `data`: the page.
    /// - Returns: true, so WebKit shows no error page of its own.
    fn onLoadFailed(web_view: *anyopaque, load_event: c_int, failing_uri: ?[*:0]const u8, failure: ?*const mod.Gerror, data: *anyopaque) callconv(.c) mod.Gboolean {
        _ = web_view;
        _ = load_event;
        _ = failing_uri;
        const api = mod.Gtk.running() orelse return 1;
        const native = Self.nativeOf(data);
        const reported = failure orelse return 1;
        if (reported.code == network_error_cancelled or reported.code == policy_error_interrupted) return 1;
        const message = Self.spanOf(reported.message);
        const text = if (message.len > 0) message else "The page could not be loaded.";
        const length = Self.cutLength(text, native.failure.len);
        native.failure_length = length;
        @memcpy(native.failure[0..length], text[0..length]);
        native.report(api);
        return 1;
    }

    /// `script-message-received::<name>`: hands the page a string message
    /// posted while it shows its trusted origin; any other is dropped, with
    /// a warning. Only the top frame can post (see the file's doc).
    ///
    /// - `manager`: the content manager; unused.
    /// - `result`: the `WebKitJavascriptResult`.
    /// - `data`: the bridge.
    fn onMessage(manager: *anyopaque, result: *anyopaque, data: *anyopaque) callconv(.c) void {
        _ = manager;
        const api = mod.Gtk.running() orelse return;
        const bridge: *Bridge = @ptrCast(@alignCast(data));
        const native = bridge.native;
        // The view follows links off the first origin: without this whatever
        // site a link led to could reach the app.
        const trusted = native.trusted_url orelse {
            log.warn("bridge ignored a message: no origin is trusted yet", .{});
            return;
        };
        if (!mod.WebOrigin.same(trusted, Self.spanOf(api.webkit_web_view_get_uri(native.view)))) {
            log.warn("bridge ignored a message from outside the loaded origin", .{});
            return;
        }
        const value = api.webkit_javascript_result_get_js_value(result) orelse return;
        if (api.jsc_value_is_string(value) == 0) {
            log.warn("bridge received a non-string body", .{});
            return;
        }
        const body = api.jsc_value_to_string(value) orelse return;
        defer api.g_free(body);
        delivering += 1;
        defer delivering -= 1;
        native.page.receive(.{ .bridge = bridge.name, .body = std.mem.span(body) });
    }

    /// A `g_idle_add` callback: drops a reference once GLib is idle.
    ///
    /// - `object`: the object.
    /// - Returns: false, so it runs once.
    fn unrefLater(object: ?*anyopaque) callconv(.c) mod.Gboolean {
        const api = mod.Gtk.running() orelse return 0;
        if (object) |held| api.g_object_unref(held);
        return 0;
    }

    /// Whether a text is an absolute address WebKit can be asked to load.
    ///
    /// - `url`: the text.
    /// - Returns: true for an address with a scheme.
    fn isAddress(url: []const u8) bool {
        const uri = std.Uri.parse(url) catch return false;
        return uri.scheme.len > 0;
    }

    /// A C string as a slice, empty for null.
    ///
    /// - `text`: the string, or null.
    /// - Returns: the slice.
    fn spanOf(text: ?[*:0]const u8) []const u8 {
        return if (text) |present| std.mem.span(present) else "";
    }

    /// How much of `text` fits in `capacity` bytes, cut on a character, never
    /// inside one.
    ///
    /// - `text`: UTF-8 text.
    /// - `capacity`: the room.
    /// - Returns: the length to keep.
    fn cutLength(text: []const u8, capacity: usize) usize {
        if (text.len <= capacity) return text.len;
        var length = capacity;
        while (length > 0 and (text[length] & 0xC0) == 0x80) length -= 1;
        return length;
    }

    /// The page behind a handle.
    ///
    /// - `handle`: the handle `create` returned.
    /// - Returns: the page.
    fn nativeOf(handle: *anyopaque) *NativePage {
        return @ptrCast(@alignCast(handle));
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

// A view cannot be built here: it needs an X display, which the test runner
// may not have. What is testable is what the view is assembled from.

test {
    std.testing.refAllDecls(@This());
}

test "web kit gtk backend loads only absolute addresses" {
    try std.testing.expect(WebKitGtkBackend.isAddress("https://example.com/"));
    try std.testing.expect(WebKitGtkBackend.isAddress("data:text/html;base64,PHA+"));
    try std.testing.expect(WebKitGtkBackend.isAddress("file:///tmp/index.html"));
    try std.testing.expect(!WebKitGtkBackend.isAddress("example.com"));
    try std.testing.expect(!WebKitGtkBackend.isAddress(""));
}

test "web kit gtk backend cuts a long failure on a character" {
    // "é" is two bytes: room for one byte more than "ab" keeps "ab", not half of it.
    try std.testing.expectEqual(@as(usize, 2), WebKitGtkBackend.cutLength("abé", 3));
    try std.testing.expectEqual(@as(usize, 4), WebKitGtkBackend.cutLength("abé", 4));
}

test "web kit gtk backend scripts carry the bridge event" {
    try std.testing.expect(std.mem.find(u8, page_script, "'" ++ bridge_event ++ "'") != null);
    try std.testing.expect(std.mem.find(u8, bridge_script, "'" ++ bridge_event ++ "'") != null);
    try std.testing.expect(std.mem.find(u8, page_script, "messageHandlers") != null);
}
