//! The macOS `WebPageBackend`: a `WKWebView` per `WebPage`, placed by the
//! native-view host (`AppKitNativeHost`) where its `WebView` is. Pages post
//! to bridges through `WKScriptMessageHandler`s, heard only from the main
//! frame of the first origin the page loaded; key-value observing reports
//! the address, title and history, and a navigation delegate the failures.
//! macOS only; nothing here is analyzed on other targets, as `WebBackend`
//! reaches it only behind `os_tag == .macos`. Ported from zigwebview.

const std = @import("std");
const log = std.log.scoped(.ziggui_wk_web_view_backend);
const mod = @import("module.zig");
const views = @import("views");

/// `NSURLErrorCancelled`: a load the user or a newer load stopped, not a failure.
const url_error_cancelled: i64 = -999;

/// One `WebPage`'s WebKit objects (each owned, +1) and what it reports; a
/// node of the list of live pages.
const NativePage = struct {
    const Self = @This();

    /// The page it reports to.
    page: *views.WebPage,
    /// The `WKWebView`.
    view: mod.Id,
    /// Its content controller, where the bridges are registered.
    controller: mod.Id,
    /// The handler every bridge of this page is registered with.
    handler: mod.Id,
    /// The key-value observer of the view's address, title and history.
    observer: mod.Id,
    /// The navigation delegate (the view holds it weakly).
    navigation: mod.Id,
    /// The origin the bridges hear (`WebPage` tells it: the first address
    /// the app asked for), or nil before it is told, when they hear none.
    trusted_url: mod.Id = null,
    /// Why the last load failed, until a load commits.
    failure: [512]u8 = undefined,
    /// How many bytes of `failure` are used.
    failure_length: usize = 0,
    /// The next live page.
    next: ?*Self = null,
    /// The previous live page.
    previous: ?*Self = null,

    /// Tells the page what it shows now: its address, title, history and
    /// failure. Called from WebKit's notifications only, inside the run
    /// loop's autorelease pool, which holds the strings it reads (a pool of
    /// its own would drain before the notification returns, and with it what
    /// a page destroyed in `onChange` handed over: see `destroy`).
    ///
    /// - `self`: the page.
    fn report(self: *Self) void {
        WkWebViewBackend.delivering += 1;
        defer WkWebViewBackend.delivering -= 1;
        const address = mod.ObjectiveC.send(mod.Id, self.view, "URL", .{});
        self.page.update(.{
            .url = mod.ObjectiveC.utf8(mod.ObjectiveC.send(mod.Id, address, "absoluteString", .{})),
            .title = mod.ObjectiveC.utf8(mod.ObjectiveC.send(mod.Id, self.view, "title", .{})),
            .failure = self.failure[0..self.failure_length],
            .can_go_back = mod.ObjectiveC.send(u8, self.view, "canGoBack", .{}) != 0,
            .can_go_forward = mod.ObjectiveC.send(u8, self.view, "canGoForward", .{}) != 0,
        });
    }
};

/// The WebKit web view behind every `WebPage` on macOS.
pub const WkWebViewBackend = struct {
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

    /// The view properties key-value observing reports.
    const watched_key_paths = [_][*:0]const u8{ "URL", "title", "canGoBack", "canGoForward" };

    // Inside the struct, as Cocoa's are, so a file-level `refAllDecls` on
    // another OS never asks the linker for them.

    /// The first live page, or null.
    var first: ?*NativePage = null;

    /// How many WebKit notifications are being delivered to the app now
    /// (nested): a page destroyed from inside one (an `onChange` or
    /// `onMessage` that frees it) has its WebKit objects autoreleased, not
    /// released, so they outlive the notification WebKit is still in.
    var delivering: u32 = 0;

    /// Makes a `WKWebView` with nothing loaded, its observer, navigation
    /// delegate and bridge handler.
    ///
    /// - `page`: the page it reports to.
    /// - Returns: the handle, or null when WebKit will not vend what it needs.
    fn create(page: *views.WebPage) ?*anyopaque {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const configuration = mod.ObjectiveC.new("WKWebViewConfiguration");
        if (configuration == null) return null;
        // The view keeps a copy of its own.
        defer mod.ObjectiveC.release(configuration);
        const controller = mod.ObjectiveC.retain(mod.ObjectiveC.send(mod.Id, configuration, "userContentController", .{}));
        // The host sets the real frame on its first frame.
        const web_view = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("WKWebView"), "alloc", .{}), "initWithFrame:configuration:", .{ mod.CGRect{}, configuration });
        const handler = Self.instance("ZigguiWebBridge", &.{.{ .selector = "userContentController:didReceiveScriptMessage:", .implementation = @ptrCast(&Self.onMessage), .types = "v@:@@" }});
        const observer = Self.instance("ZigguiWebObserver", &.{.{ .selector = "observeValueForKeyPath:ofObject:change:context:", .implementation = @ptrCast(&Self.onObserve), .types = "v@:@@@^v" }});
        const navigation = Self.instance("ZigguiWebNavigation", &.{
            .{ .selector = "webView:didFailNavigation:withError:", .implementation = @ptrCast(&Self.onFail), .types = "v@:@@@" },
            .{ .selector = "webView:didFailProvisionalNavigation:withError:", .implementation = @ptrCast(&Self.onFail), .types = "v@:@@@" },
            .{ .selector = "webView:didCommitNavigation:", .implementation = @ptrCast(&Self.onCommit), .types = "v@:@@" },
        });
        const native = std.heap.c_allocator.create(NativePage) catch |err| blk: {
            log.warn("page not made: {s}", .{@errorName(err)});
            break :blk null;
        };
        if (controller == null or web_view == null or handler == null or observer == null or navigation == null or native == null) {
            for ([_]mod.Id{ controller, web_view, handler, observer, navigation }) |object| mod.ObjectiveC.release(object);
            if (native) |unused| std.heap.c_allocator.destroy(unused);
            return null;
        }
        native.?.* = .{ .page = page, .view = web_view, .controller = controller, .handler = handler, .observer = observer, .navigation = navigation, .next = first };
        mod.ObjectiveC.send(void, web_view, "setNavigationDelegate:", .{navigation});
        mod.ObjectiveC.send(void, web_view, "setAllowsBackForwardNavigationGestures:", .{@as(u8, 1)});
        for (watched_key_paths) |key_path| {
            mod.ObjectiveC.send(void, web_view, "addObserver:forKeyPath:options:context:", .{ observer, mod.ObjectiveC.string(key_path), @as(u64, 0), @as(?*anyopaque, null) });
        }
        if (first) |head| head.previous = native.?;
        first = native.?;
        return native.?;
    }

    /// Takes the view out of the window and frees every object of the page.
    ///
    /// - `handle`: the page.
    fn destroy(handle: *anyopaque) void {
        const native = Self.nativeOf(handle);
        Self.detach(native);
        // Inside a WebKit notification (the app freed the page from a
        // callback), WebKit is still using these: the run loop's pool frees
        // them once it returns. Outside one, at once (there may be no pool).
        const free = if (delivering > 0) &mod.ObjectiveC.autorelease else &mod.ObjectiveC.release;
        for ([_]mod.Id{ native.view, native.controller, native.handler, native.observer, native.navigation, native.trusted_url }) |object| free(object);
        if (native.previous) |previous| previous.next = native.next else first = native.next;
        if (native.next) |next| next.previous = native.previous;
        std.heap.c_allocator.destroy(native);
    }

    /// Stops a page and takes it out of everything that reaches it: its
    /// observer, delegate and bridges, its load, and the window.
    ///
    /// - `native`: the page.
    fn detach(native: *NativePage) void {
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        // Key-value observing throws if the view goes while still observed.
        for (watched_key_paths) |key_path| {
            mod.ObjectiveC.send(void, native.view, "removeObserver:forKeyPath:context:", .{ native.observer, mod.ObjectiveC.string(key_path), @as(?*anyopaque, null) });
        }
        mod.ObjectiveC.send(void, native.view, "setNavigationDelegate:", .{@as(mod.Id, null)});
        mod.ObjectiveC.send(void, native.controller, "removeAllScriptMessageHandlers", .{});
        // Stopped and blanked now: the native-view host keeps the view until
        // its next frame drops it, and a page left running would keep
        // loading, and playing its sound, until then.
        mod.ObjectiveC.send(void, native.view, "stopLoading", .{});
        _ = mod.ObjectiveC.send(mod.Id, native.view, "loadHTMLString:baseURL:", .{ mod.ObjectiveC.string(""), @as(mod.Id, null) });
        // The native-view host drops a view taken out of its container.
        mod.ObjectiveC.send(void, native.view, "removeFromSuperview", .{});
    }

    /// The `WKWebView`, for the native-view host to place.
    ///
    /// - `handle`: the page.
    /// - Returns: the view.
    fn view(handle: *anyopaque) ?*anyopaque {
        return Self.nativeOf(handle).view;
    }

    /// Sets the origin the bridges hear; an address `NSURL` will not parse
    /// leaves them hearing none.
    ///
    /// - `handle`: the page.
    /// - `url`: the trusted address.
    fn trust(handle: *anyopaque, url: [:0]const u8) void {
        const native = Self.nativeOf(handle);
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const address = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSURL"), "URLWithString:", .{mod.ObjectiveC.string(url.ptr)});
        mod.ObjectiveC.release(native.trusted_url);
        native.trusted_url = mod.ObjectiveC.retain(address);
    }

    /// Loads `url`: a `file:` URL with read access to its folder (WebKit will
    /// not read a file through a request), anything else through a request.
    ///
    /// - `handle`: the page.
    /// - `url`: the address.
    /// - Returns: false when `NSURL` will not parse it.
    fn load(handle: *anyopaque, url: [:0]const u8) bool {
        const native = Self.nativeOf(handle);
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        const address = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSURL"), "URLWithString:", .{mod.ObjectiveC.string(url.ptr)});
        if (address == null) return false;
        if (mod.ObjectiveC.send(u8, address, "isFileURL", .{}) != 0) {
            const folder = mod.ObjectiveC.send(mod.Id, address, "URLByDeletingLastPathComponent", .{});
            _ = mod.ObjectiveC.send(mod.Id, native.view, "loadFileURL:allowingReadAccessToURL:", .{ address, folder });
            return true;
        }
        const request = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSURLRequest"), "requestWithURL:", .{address});
        _ = mod.ObjectiveC.send(mod.Id, native.view, "loadRequest:", .{request});
        return true;
    }

    /// Goes back one page, if the history has one.
    ///
    /// - `handle`: the page.
    fn goBack(handle: *anyopaque) void {
        _ = mod.ObjectiveC.send(mod.Id, Self.nativeOf(handle).view, "goBack", .{});
    }

    /// Goes forward one page, if the history has one.
    ///
    /// - `handle`: the page.
    fn goForward(handle: *anyopaque) void {
        _ = mod.ObjectiveC.send(mod.Id, Self.nativeOf(handle).view, "goForward", .{});
    }

    /// Loads the page showing again.
    ///
    /// - `handle`: the page.
    fn reload(handle: *anyopaque) void {
        _ = mod.ObjectiveC.send(mod.Id, Self.nativeOf(handle).view, "reload", .{});
    }

    /// Lets the page post messages under `name`.
    ///
    /// - `handle`: the page.
    /// - `name`: the bridge's name.
    fn addBridge(handle: *anyopaque, name: [:0]const u8) void {
        const native = Self.nativeOf(handle);
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);
        // WebKit throws on a name already taken, and an exception thrown through
        // Zig frames aborts the process; removing an unknown name does nothing.
        const key = mod.ObjectiveC.string(name.ptr);
        mod.ObjectiveC.send(void, native.controller, "removeScriptMessageHandlerForName:", .{key});
        mod.ObjectiveC.send(void, native.controller, "addScriptMessageHandler:name:", .{ native.handler, key });
    }

    /// The live page whose view is `web_view`.
    ///
    /// - `web_view`: the `WKWebView`.
    /// - Returns: the page, or null for one already freed.
    fn pageFor(web_view: mod.Id) ?*NativePage {
        var node = first;
        while (node) |native| : (node = native.next) {
            if (native.view == web_view) return native;
        }
        return null;
    }

    /// `-[ZigguiWebBridge userContentController:didReceiveScriptMessage:]`:
    /// hands the page a message posted from the main frame of its trusted
    /// origin with a string body; any other is dropped, with a warning.
    ///
    /// - `receiver`: the handler; unused.
    /// - `selector`: the selector sent; unused.
    /// - `controller`: the content controller that delivered it; unused.
    /// - `message`: the `WKScriptMessage`.
    fn onMessage(receiver: mod.Id, selector: mod.Id, controller: mod.Id, message: mod.Id) callconv(.c) void {
        _ = receiver;
        _ = selector;
        _ = controller;
        const native = Self.pageFor(mod.ObjectiveC.send(mod.Id, message, "webView", .{})) orelse return;
        // Any frame can post, and the view follows links off the first origin:
        // without these checks an embedded third-party frame, or whatever site
        // a link led to, could reach the app.
        const frame = mod.ObjectiveC.send(mod.Id, message, "frameInfo", .{});
        if (mod.ObjectiveC.send(u8, frame, "isMainFrame", .{}) == 0) {
            log.warn("bridge ignored a message from a subframe", .{});
            return;
        }
        const current = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, frame, "request", .{}), "URL", .{});
        if (!Self.sameOrigin(native.trusted_url, current)) {
            log.warn("bridge ignored a message from outside the loaded origin", .{});
            return;
        }
        const body = mod.ObjectiveC.send(mod.Id, message, "body", .{});
        // `UTF8String` on anything but a string is a message it does not answer.
        if (body == null or mod.ObjectiveC.send(u8, body, "isKindOfClass:", .{mod.ObjectiveC.class("NSString")}) == 0) {
            log.warn("bridge received a non-string body", .{});
            return;
        }
        delivering += 1;
        defer delivering -= 1;
        native.page.receive(.{
            .bridge = mod.ObjectiveC.utf8(mod.ObjectiveC.send(mod.Id, message, "name", .{})),
            .body = mod.ObjectiveC.utf8(body),
        });
    }

    /// `-[ZigguiWebObserver observeValueForKeyPath:ofObject:change:context:]`:
    /// the view's address, title or history changed.
    ///
    /// - `receiver`: the observer; unused.
    /// - `selector`: the selector sent; unused.
    /// - `key_path`: the property that changed; unused.
    /// - `object`: the `WKWebView`.
    /// - `change`: the change dictionary; unused.
    /// - `context`: the context registered; unused.
    fn onObserve(receiver: mod.Id, selector: mod.Id, key_path: mod.Id, object: mod.Id, change: mod.Id, context: ?*anyopaque) callconv(.c) void {
        _ = receiver;
        _ = selector;
        _ = key_path;
        _ = change;
        _ = context;
        if (Self.pageFor(object)) |native| native.report();
    }

    /// `-[ZigguiWebNavigation webView:didFail(Provisional)Navigation:withError:]`:
    /// keeps the error's description as the failure; a cancelled load (a
    /// newer one, the user) is none.
    ///
    /// - `receiver`: the delegate; unused.
    /// - `selector`: the selector sent; unused.
    /// - `web_view`: the `WKWebView`.
    /// - `navigation`: the navigation; unused.
    /// - `error_object`: the `NSError`.
    fn onFail(receiver: mod.Id, selector: mod.Id, web_view: mod.Id, navigation: mod.Id, error_object: mod.Id) callconv(.c) void {
        _ = receiver;
        _ = selector;
        _ = navigation;
        const native = Self.pageFor(web_view) orelse return;
        if (mod.ObjectiveC.send(i64, error_object, "code", .{}) == url_error_cancelled) return;
        // No pool of its own: see `NativePage.report`.
        const description = mod.ObjectiveC.utf8(mod.ObjectiveC.send(mod.Id, error_object, "localizedDescription", .{}));
        const text = if (description.len > 0) description else "The page could not be loaded.";
        const length = views.DisplayText.fitLength(text, native.failure.len);
        native.failure_length = length;
        @memcpy(native.failure[0..length], text[0..length]);
        native.report();
    }

    /// `-[ZigguiWebNavigation webView:didCommitNavigation:]`: a page started
    /// showing, so no failure stands.
    ///
    /// - `receiver`: the delegate; unused.
    /// - `selector`: the selector sent; unused.
    /// - `web_view`: the `WKWebView`.
    /// - `navigation`: the navigation; unused.
    fn onCommit(receiver: mod.Id, selector: mod.Id, web_view: mod.Id, navigation: mod.Id) callconv(.c) void {
        _ = receiver;
        _ = selector;
        _ = navigation;
        const native = Self.pageFor(web_view) orelse return;
        if (native.failure_length == 0) return;
        native.failure_length = 0;
        native.report();
    }

    /// Whether two `NSURL`s share an origin, by the rule every platform's
    /// web view applies (`WebOrigin.same`) to their absolute addresses.
    ///
    /// - `first_url`: one URL; nil never matches.
    /// - `second_url`: the other; nil never matches.
    /// - Returns: true when both are present and their origins agree.
    fn sameOrigin(first_url: mod.Id, second_url: mod.Id) bool {
        if (first_url == null or second_url == null) return false;
        const first_address = mod.ObjectiveC.utf8(mod.ObjectiveC.send(mod.Id, first_url, "absoluteString", .{}));
        const second_address = mod.ObjectiveC.utf8(mod.ObjectiveC.send(mod.Id, second_url, "absoluteString", .{}));
        return mod.WebOrigin.same(first_address, second_address);
    }

    /// A new instance (+1) of an `NSObject` subclass answering `methods`,
    /// registering the class on first use.
    ///
    /// - `name`: the class's name.
    /// - `methods`: the methods it answers.
    /// - Returns: the instance, or nil when the runtime will not register the class.
    fn instance(name: [*:0]const u8, methods: []const mod.ObjectiveCMethod) mod.Id {
        if (mod.ObjectiveC.defineClass(name, "NSObject", methods) == null) return null;
        return mod.ObjectiveC.new(name);
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

/// Fixtures for the tests below.
const TestSupport = struct {
    const Self = @This();

    /// Parses `value` into an autoreleased `NSURL`.
    ///
    /// - `value`: the address.
    /// - Returns: the URL, or nil when it will not parse.
    fn url(value: [*:0]const u8) mod.Id {
        return mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSURL"), "URLWithString:", .{mod.ObjectiveC.string(value)});
    }
};

// A view cannot be built here: it needs a window server session, which the
// test runner has none of. What is testable is that WebKit is linked and the
// runtime answers what the view is assembled from.

test {
    std.testing.refAllDecls(@This());
    // Its bodies reach the Objective-C runtime, which only macOS links.
    if (comptime mod.os_tag == .macos) std.testing.refAllDecls(WkWebViewBackend);
}

test "wk web view backend resolves the WebKit classes it builds from" {
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    try std.testing.expect(mod.ObjectiveC.class("WKWebView") != null);
    try std.testing.expect(mod.ObjectiveC.class("WKWebViewConfiguration") != null);
    try std.testing.expect(mod.ObjectiveC.class("NSURLRequest") != null);
}

test "wk web view backend registers each of its classes once" {
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    const pool = mod.ObjectiveC.pushPool();
    defer mod.ObjectiveC.popPool(pool);
    const methods = [_]mod.ObjectiveCMethod{.{ .selector = "userContentController:didReceiveScriptMessage:", .implementation = @ptrCast(&WkWebViewBackend.onMessage), .types = "v@:@@" }};
    const first_instance = WkWebViewBackend.instance("ZigguiWebBridge", &methods);
    defer mod.ObjectiveC.release(first_instance);
    // The second comes from the class the first registered.
    const second_instance = WkWebViewBackend.instance("ZigguiWebBridge", &methods);
    defer mod.ObjectiveC.release(second_instance);
    try std.testing.expect(first_instance != null and second_instance != null);
    try std.testing.expect(mod.ObjectiveC.send(u8, first_instance, "respondsToSelector:", .{mod.ObjectiveC.selectorNamed("userContentController:didReceiveScriptMessage:")}) != 0);
}

test "wk web view backend hears only the origin it loaded" {
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    const pool = mod.ObjectiveC.pushPool();
    defer mod.ObjectiveC.popPool(pool);
    const console = TestSupport.url("http://127.0.0.1:8080/console");
    try std.testing.expect(WkWebViewBackend.sameOrigin(console, TestSupport.url("HTTP://127.0.0.1:8080/other#frag")));
    try std.testing.expect(!WkWebViewBackend.sameOrigin(console, TestSupport.url("http://127.0.0.1:8081/console")));
    try std.testing.expect(!WkWebViewBackend.sameOrigin(console, TestSupport.url("http://example.com:8080/console")));
    try std.testing.expect(!WkWebViewBackend.sameOrigin(console, TestSupport.url("https://127.0.0.1:8080/console")));
    try std.testing.expect(!WkWebViewBackend.sameOrigin(console, null));
    // An inline page has no host: it matches only itself, never another
    // `data:` page a site could navigate to.
    const page = TestSupport.url("data:text/html;base64,PHA+");
    try std.testing.expect(WkWebViewBackend.sameOrigin(page, TestSupport.url("data:text/html;base64,PHA+")));
    try std.testing.expect(!WkWebViewBackend.sameOrigin(page, TestSupport.url("data:text/html;base64,PGI+")));
    try std.testing.expect(!WkWebViewBackend.sameOrigin(page, TestSupport.url("about:blank")));
    try std.testing.expect(!WkWebViewBackend.sameOrigin(page, console));
    // Local files are the user's own, one origin across a folder.
    try std.testing.expect(WkWebViewBackend.sameOrigin(TestSupport.url("file:///tmp/site/index.html"), TestSupport.url("file:///tmp/site/other.html")));
}

test "wk web view backend answers the navigation and edit actions it sends" {
    if (comptime mod.os_tag != .macos) return error.SkipZigTest;
    const class = mod.ObjectiveC.class("WKWebView");
    for ([_][*:0]const u8{ "goBack", "goForward", "reload", "canGoBack", "canGoForward", "stopLoading", "loadHTMLString:baseURL:", "copy:", "cut:", "paste:", "selectAll:" }) |action| {
        try std.testing.expect(mod.ObjectiveC.send(u8, class, "instancesRespondToSelector:", .{mod.ObjectiveC.selectorNamed(action)}) != 0);
    }
}
