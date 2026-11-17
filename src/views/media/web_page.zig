//! A web page modeled on SwiftUI's `WebPage`: loaded, navigated and heard
//! from by the app, its view shown by `WebView`. The platform web view
//! behind it comes from the installed `WebPageBackend`, made on first need,
//! so a page can be set up before the window opens.

const std = @import("std");
const log = std.log.scoped(.ziggui_web_page);
const mod = @import("module.zig");

/// What the platform web view reports with `WebPage.update`: everything the
/// page shows about itself, borrowed for the call.
pub const WebPageState = struct {
    const Self = @This();

    /// The address of the page showing now (after any link followed).
    url: []const u8 = "",

    /// The page's title.
    title: []const u8 = "",

    /// Why the last load failed, or empty once a load has committed.
    failure: []const u8 = "",

    /// The history has a page before this one.
    can_go_back: bool = false,

    /// The history has a page after this one.
    can_go_forward: bool = false,
};

/// A message a page posted to one of its bridges, borrowed from the platform
/// for the call: the app copies what it keeps.
pub const WebPageMessage = struct {
    const Self = @This();

    /// The bridge's name (`window.webkit.messageHandlers.<name>` on macOS).
    bridge: []const u8,

    /// The message's body, a string.
    body: []const u8,
};

/// What `WebPage.onMessage` calls with each message: a method and the
/// context it is called on, as `Callback` is for a tap.
pub const WebPageMessageCallback = struct {
    const Self = @This();

    /// What `function` gets back.
    context: ?*anyopaque = null,

    /// The handler, given each message.
    function: *const fn (?*anyopaque, WebPageMessage) void,

    /// Wraps a method taking a typed context pointer and a message.
    ///
    /// - `T`: the context's type.
    /// - `context`: the context; it must outlive the page's use of the callback.
    /// - `method`: the method called with it and each message.
    /// - Returns: the callback.
    pub fn init(comptime T: type, context: *T, comptime method: fn (*T, WebPageMessage) void) Self {
        const self = Self{ .context = context, .function = struct {
            const Self = @This();

            /// Calls `method` on the context with the message.
            ///
            /// - `pointer`: the context.
            /// - `message`: the message.
            fn call(pointer: ?*anyopaque, message: WebPageMessage) void {
                method(@ptrCast(@alignCast(pointer.?)), message);
            }
        }.call };
        return self;
    }

    /// Calls the handler with `message`.
    ///
    /// - `self`: the callback.
    /// - `message`: the message, borrowed for the call.
    pub fn call(self: *const Self, message: WebPageMessage) void {
        self.function(self.context, message);
    }
};

/// A web page the app owns, like a `Player`: its address must stay put while
/// views show it, since the platform page reports back to it. Call it from
/// the UI thread; its callbacks run there too, inside the platform's
/// notification, mostly while the loop pumps events, between frames. The
/// build that first shows the page is the exception: making the platform page
/// loads the address asked for, and the platform may report it at once, so
/// `onChange` may run during that build. A callback may free the page.
pub const WebPage = struct {
    const Self = @This();

    /// Owns the addresses, names and texts the page keeps.
    allocator: std.mem.Allocator,

    /// The platform page, once made.
    handle: ?*anyopaque = null,

    /// The backend `handle` came from (it frees it, even after the runtime
    /// has gone).
    backend: ?*const mod.WebPageBackend = null,

    /// The last address `load` asked for, which a page made later loads.
    requested_url: ?[:0]u8 = null,

    /// The first address `load` was ever asked for: the origin the bridges
    /// hear, told to the platform page as it is made (or at once, when it is
    /// made already), so an address asked for later, even before the page
    /// exists, never inherits that trust.
    trusted_url: ?[:0]u8 = null,

    /// Why the platform refused the last address asked for ("Not an
    /// address: …"), until it accepts one; kept apart from what the
    /// platform reports, which knows nothing of it.
    refusal: []u8 = &.{},

    /// The platform would not make a page: it is not asked again.
    create_refused: bool = false,

    /// The bridges asked for, which a page made later registers.
    bridges: std.ArrayList([:0]u8) = .empty,

    /// What a change of address, title, history or failure calls.
    on_change: ?mod.Callback = null,

    /// What a bridge message calls.
    on_message: ?WebPageMessageCallback = null,

    /// The address showing, as the platform last reported it.
    current_url: []u8 = &.{},

    /// The title, as the platform last reported it.
    current_title: []u8 = &.{},

    /// Why the last load failed, as the platform last reported it.
    current_failure: []u8 = &.{},

    /// The history has a page before this one.
    can_go_back: bool = false,

    /// The history has a page after this one.
    can_go_forward: bool = false,

    /// The backend new pages use, installed by the SDL runtime as its loop
    /// starts; null headless and in tests, unless a test installs one.
    var installed_backend: ?*const mod.WebPageBackend = null;

    /// A page with nothing loaded.
    ///
    /// - `allocator`: owns what the page keeps.
    /// - Returns: the page.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Takes the page's view out of the window and frees the page.
    ///
    /// - `self`: the page.
    pub fn deinit(self: *Self) void {
        if (self.handle) |handle| self.backend.?.destroy(handle);
        if (self.requested_url) |requested| self.allocator.free(requested);
        if (self.trusted_url) |trusted| self.allocator.free(trusted);
        self.allocator.free(self.refusal);
        for (self.bridges.items) |name| self.allocator.free(name);
        self.bridges.deinit(self.allocator);
        self.allocator.free(self.current_url);
        self.allocator.free(self.current_title);
        self.allocator.free(self.current_failure);
        self.* = .{ .allocator = self.allocator };
    }

    /// Installs the backend pages are made with; the SDL runtime calls this
    /// as its loop starts and ends. A page keeps the backend it was made with.
    ///
    /// - `backend`: the platform web view; null for none.
    pub fn setBackend(backend: ?*const mod.WebPageBackend) void {
        installed_backend = backend;
    }

    /// Loads the page at `url` (`https://…`, `file:///…`, a `data:` URL).
    /// Without a platform page yet, the one made later loads it. An address
    /// the platform cannot parse becomes the failure. The first address ever
    /// asked for is the origin the bridges hear.
    ///
    /// - `self`: the page.
    /// - `address`: the address.
    /// - Returns: nothing; propagates allocation failure.
    pub fn load(self: *Self, address: []const u8) std.mem.Allocator.Error!void {
        const copy = try self.allocator.dupeSentinel(u8, address, 0);
        if (self.trusted_url == null) {
            self.trusted_url = self.allocator.dupeSentinel(u8, address, 0) catch |err| {
                self.allocator.free(copy);
                return err;
            };
            if (self.handle) |handle| self.backend.?.trust(handle, self.trusted_url.?);
        }
        // `address` may be the old one's own bytes (`load(page.url())`): only
        // the copy is read from here on.
        if (self.requested_url) |old| self.allocator.free(old);
        self.requested_url = copy;
        if (self.handle) |handle| try self.loadNow(handle, copy);
    }

    /// Goes back one page in the history, if it can.
    ///
    /// - `self`: the page.
    pub fn goBack(self: *Self) void {
        self.clearRefusal();
        if (self.handle) |handle| self.backend.?.go_back(handle);
    }

    /// Goes forward one page in the history, if it can.
    ///
    /// - `self`: the page.
    pub fn goForward(self: *Self) void {
        self.clearRefusal();
        if (self.handle) |handle| self.backend.?.go_forward(handle);
    }

    /// Loads the page showing again.
    ///
    /// - `self`: the page.
    pub fn reload(self: *Self) void {
        self.clearRefusal();
        if (self.handle) |handle| self.backend.?.reload(handle);
    }

    /// Lets the page post messages to the app under `name`, which
    /// `onMessage` hears. Only the main frame of the first page this one
    /// loaded is heard, so an address typed in later cannot reach the app.
    /// Registering a name again replaces it.
    ///
    /// - `self`: the page.
    /// - `name`: the name the page posts to.
    /// - Returns: nothing; propagates allocation failure.
    pub fn addBridge(self: *Self, name: []const u8) std.mem.Allocator.Error!void {
        for (self.bridges.items) |existing| {
            if (std.mem.eql(u8, existing, name)) {
                if (self.handle) |handle| self.backend.?.add_bridge(handle, existing);
                return;
            }
        }
        const copy = try self.allocator.dupeSentinel(u8, name, 0);
        errdefer self.allocator.free(copy);
        try self.bridges.append(self.allocator, copy);
        if (self.handle) |handle| self.backend.?.add_bridge(handle, copy);
    }

    /// Sets what a change of address, title, history or failure calls.
    ///
    /// - `self`: the page.
    /// - `callback`: the callback, or null for none; replaces any earlier one.
    pub fn onChange(self: *Self, callback: ?mod.Callback) void {
        self.on_change = callback;
    }

    /// Sets what each bridge message calls.
    ///
    /// - `self`: the page.
    /// - `callback`: the callback, or null for none; replaces any earlier one.
    pub fn onMessage(self: *Self, callback: ?WebPageMessageCallback) void {
        self.on_message = callback;
    }

    /// The address of the page showing now; before the platform reports one,
    /// the address last asked for.
    ///
    /// - `self`: the page.
    /// - Returns: the address, valid until the next change; empty for none.
    pub fn url(self: *const Self) []const u8 {
        if (self.current_url.len > 0) return self.current_url;
        return if (self.requested_url) |requested| requested else "";
    }

    /// The title of the page showing now.
    ///
    /// - `self`: the page.
    /// - Returns: the title, valid until the next change; empty for none.
    pub fn title(self: *const Self) []const u8 {
        return self.current_title;
    }

    /// Why the last address asked for was refused, else why the last load
    /// failed (a bad host, a refused connection), else why there is no
    /// platform page (none on this platform, or it would not make one);
    /// empty otherwise.
    ///
    /// - `self`: the page.
    /// - Returns: the reason, valid until the next change.
    pub fn failure(self: *const Self) []const u8 {
        if (self.refusal.len > 0) return self.refusal;
        if (self.current_failure.len > 0) return self.current_failure;
        if (self.create_refused) return "The web view could not be made.";
        if (self.handle == null) if (installed_backend) |backend| if (backend.unsupported) |reason| return reason;
        return "";
    }

    /// Whether the history has a page before this one.
    ///
    /// - `self`: the page.
    /// - Returns: true when `goBack` can go.
    pub fn canGoBack(self: *const Self) bool {
        return self.can_go_back;
    }

    /// Whether the history has a page after this one.
    ///
    /// - `self`: the page.
    /// - Returns: true when `goForward` can go.
    pub fn canGoForward(self: *const Self) bool {
        return self.can_go_forward;
    }

    /// The platform view to place (`WebView` places it), making the platform
    /// page on first need and giving it the bridges, the origin they hear and
    /// the address asked for before it existed. A platform that refuses to
    /// make one is not asked again (`failure` says so).
    ///
    /// - `self`: the page; it must stay put from now on.
    /// - Returns: the view, or null with no backend or when it refused.
    pub fn nativeView(self: *Self) ?*anyopaque {
        if (self.handle) |handle| return self.backend.?.view(handle);
        if (self.create_refused) return null;
        const backend = installed_backend orelse return null;
        if (backend.unsupported != null) return null;
        const handle = backend.create(self) orelse {
            self.create_refused = true;
            self.notify();
            return null;
        };
        self.handle = handle;
        self.backend = backend;
        for (self.bridges.items) |name| backend.add_bridge(handle, name);
        if (self.trusted_url) |trusted| backend.trust(handle, trusted);
        if (self.requested_url) |requested| self.loadNow(handle, requested) catch |err| log.warn("refusal not kept [{t}]", .{err});
        return backend.view(handle);
    }

    /// Takes the platform's report of the page (for backends): keeps copies of
    /// its address, title and failure, then calls `onChange` and wakes the
    /// window. A copy that cannot be made keeps the one before.
    ///
    /// - `self`: the page.
    /// - `state`: what the page shows now, borrowed for the call.
    pub fn update(self: *Self, state: WebPageState) void {
        Self.keep(self.allocator, &self.current_url, state.url);
        Self.keep(self.allocator, &self.current_title, state.title);
        Self.keep(self.allocator, &self.current_failure, state.failure);
        self.can_go_back = state.can_go_back;
        self.can_go_forward = state.can_go_forward;
        self.notify();
    }

    /// Takes a message the page posted to a bridge (for backends): calls
    /// `onMessage` with it and wakes the window.
    ///
    /// - `self`: the page.
    /// - `message`: the message, borrowed for the call.
    pub fn receive(self: *Self, message: WebPageMessage) void {
        if (self.on_message) |callback| callback.call(message);
        mod.FrameClock.shared().wake();
    }

    /// Asks the platform page to load `url`; a refusal becomes the failure
    /// (a change), an accepted address clears an earlier refusal.
    ///
    /// - `self`: the page.
    /// - `handle`: the platform page.
    /// - `address`: the address, owned by the page.
    /// - Returns: nothing; propagates allocation failure.
    fn loadNow(self: *Self, handle: *anyopaque, address: [:0]const u8) std.mem.Allocator.Error!void {
        if (self.backend.?.load(handle, address)) return self.clearRefusal();
        const reason = try self.allocator.print("Not an address: {s}", .{address});
        self.allocator.free(self.refusal);
        self.refusal = reason;
        self.notify();
    }

    /// Forgets a refused address: the page moved on.
    ///
    /// - `self`: the page.
    fn clearRefusal(self: *Self) void {
        if (self.refusal.len == 0) return;
        self.allocator.free(self.refusal);
        self.refusal = &.{};
    }

    /// Calls `onChange` and wakes the window.
    ///
    /// - `self`: the page.
    fn notify(self: *Self) void {
        if (self.on_change) |callback| callback.function(callback.context);
        mod.FrameClock.shared().wake();
    }

    /// Replaces `slot`'s text with a copy of `text`, unless it is the same; a
    /// copy that cannot be made leaves the old text.
    ///
    /// - `allocator`: owns the text.
    /// - `slot`: where the text is kept.
    /// - `text`: the new text, borrowed.
    fn keep(allocator: std.mem.Allocator, slot: *[]u8, text: []const u8) void {
        if (std.mem.eql(u8, slot.*, text)) return;
        const copy = allocator.dupe(u8, text) catch |err| {
            log.warn("page text not kept [{t}]", .{err});
            return;
        };
        allocator.free(slot.*);
        slot.* = copy;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// A backend for the tests: records what the page asked of it, and reports
/// back through the page it was made for.
const TestBackend = struct {
    const Self = @This();

    /// The page `create` was given.
    var page: ?*WebPage = null;

    /// What the backend was asked, in order, in a fixed buffer.
    var calls: [256]u8 = undefined;

    /// How many bytes of `calls` are used.
    var calls_length: usize = 0;

    /// The marker handle `create` returns.
    var marker: u8 = 0;

    /// The backend.
    const backend: mod.WebPageBackend = .{
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

    /// Forgets what was asked.
    fn reset() void {
        page = null;
        calls_length = 0;
        refuse_create = false;
    }

    /// What the backend was asked, in order.
    ///
    /// - Returns: the record.
    fn record() []const u8 {
        return calls[0..calls_length];
    }

    /// Appends `text` and a space to the record.
    ///
    /// - `text`: what was asked.
    fn note(text: []const u8) void {
        @memcpy(calls[calls_length..][0..text.len], text);
        calls[calls_length + text.len] = ' ';
        calls_length += text.len + 1;
    }

    /// Makes the marker page.
    ///
    /// - `for_page`: the page it reports to.
    /// - Returns: the marker.
    fn create(for_page: *WebPage) ?*anyopaque {
        Self.note("create");
        if (refuse_create) return null;
        page = for_page;
        return &marker;
    }

    /// Records the destroy.
    fn destroy(_: *anyopaque) void {
        Self.note("destroy");
    }

    /// The marker as the view.
    ///
    /// - Returns: the marker.
    fn view(_: *anyopaque) ?*anyopaque {
        return &marker;
    }

    /// Records the origin the bridges hear.
    ///
    /// - `url`: the address.
    fn trust(_: *anyopaque, url: [:0]const u8) void {
        Self.note("trust:");
        Self.note(url);
    }

    /// Whether `create` refuses.
    var refuse_create: bool = false;

    /// Records the load; refuses an address with a space.
    ///
    /// - `url`: the address.
    /// - Returns: false for an address with a space.
    fn load(_: *anyopaque, url: [:0]const u8) bool {
        Self.note(url);
        return std.mem.findScalar(u8, url, ' ') == null;
    }

    /// Records going back.
    fn goBack(_: *anyopaque) void {
        Self.note("back");
    }

    /// Records going forward.
    fn goForward(_: *anyopaque) void {
        Self.note("forward");
    }

    /// Records the reload.
    fn reload(_: *anyopaque) void {
        Self.note("reload");
    }

    /// Records the bridge.
    ///
    /// - `name`: its name.
    fn addBridge(_: *anyopaque, name: [:0]const u8) void {
        Self.note(name);
    }
};

/// What the tests' callbacks heard.
const TestListener = struct {
    const Self = @This();

    /// How many changes were reported.
    changes: u32 = 0,

    /// The last message's body, copied.
    body: [32]u8 = undefined,

    /// How many bytes of `body` are used.
    body_length: usize = 0,

    /// Counts a change.
    ///
    /// - `self`: the listener.
    fn changed(self: *Self) void {
        self.changes += 1;
    }

    /// Copies the message's body.
    ///
    /// - `self`: the listener.
    /// - `message`: the message.
    fn heard(self: *Self, message: WebPageMessage) void {
        @memcpy(self.body[0..message.body.len], message.body);
        self.body_length = message.body.len;
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "web page: without a backend it keeps what it was asked and goes nowhere" {
    WebPage.setBackend(null);
    var page = WebPage.init(std.testing.allocator);
    defer page.deinit();
    try page.load("https://example.com/");
    try page.addBridge("clipboard");
    page.goBack();
    page.reload();
    try std.testing.expectEqualStrings("https://example.com/", page.url());
    try std.testing.expect(!page.canGoBack() and !page.canGoForward());
    try std.testing.expect(page.nativeView() == null);
    try std.testing.expectEqualStrings("", page.failure());
}

test "web page: an unsupported backend is its failure" {
    const unsupported: mod.WebPageBackend = .{ .unsupported = "No web view here.", .create = TestBackend.create, .destroy = TestBackend.destroy, .view = TestBackend.view, .trust = TestBackend.trust, .load = TestBackend.load, .go_back = TestBackend.goBack, .go_forward = TestBackend.goForward, .reload = TestBackend.reload, .add_bridge = TestBackend.addBridge };
    WebPage.setBackend(&unsupported);
    defer WebPage.setBackend(null);
    var page = WebPage.init(std.testing.allocator);
    defer page.deinit();
    try std.testing.expect(page.nativeView() == null);
    try std.testing.expectEqualStrings("No web view here.", page.failure());
}

test "web page: the platform page is made on first need and given what was asked before" {
    TestBackend.reset();
    WebPage.setBackend(&TestBackend.backend);
    defer WebPage.setBackend(null);
    var page = WebPage.init(std.testing.allocator);
    try page.addBridge("clipboard");
    try page.addBridge("clipboard");
    try page.load("https://example.com/");
    try std.testing.expectEqualStrings("", TestBackend.record());
    try std.testing.expect(page.nativeView() != null);
    page.goBack();
    page.goForward();
    page.reload();
    page.deinit();
    try std.testing.expectEqualStrings("create clipboard trust: https://example.com/ https://example.com/ back forward reload destroy ", TestBackend.record());
}

test "web page: a report is kept and heard, a message is heard, a bad address fails" {
    TestBackend.reset();
    WebPage.setBackend(&TestBackend.backend);
    defer WebPage.setBackend(null);
    var page = WebPage.init(std.testing.allocator);
    defer page.deinit();
    var listener: TestListener = .{};
    page.onChange(mod.Callback.init(TestListener, &listener, TestListener.changed));
    page.onMessage(WebPageMessageCallback.init(TestListener, &listener, TestListener.heard));
    _ = page.nativeView();

    TestBackend.page.?.update(.{ .url = "https://example.com/a", .title = "A", .can_go_back = true });
    try std.testing.expectEqualStrings("https://example.com/a", page.url());
    try std.testing.expectEqualStrings("A", page.title());
    try std.testing.expect(page.canGoBack() and !page.canGoForward());
    try std.testing.expectEqual(@as(u32, 1), listener.changes);

    TestBackend.page.?.receive(.{ .bridge = "clipboard", .body = "copied" });
    try std.testing.expectEqualStrings("copied", listener.body[0..listener.body_length]);

    // An address the platform cannot parse fails, and is a change.
    try page.load("not an address");
    try std.testing.expectEqualStrings("Not an address: not an address", page.failure());
    try std.testing.expectEqual(@as(u32, 2), listener.changes);
    // An accepted address clears it.
    try page.load("https://example.com/b");
    try std.testing.expectEqualStrings("", page.failure());
}

test "web page: the bridges hear the first address asked for, not one asked for later" {
    TestBackend.reset();
    WebPage.setBackend(&TestBackend.backend);
    defer WebPage.setBackend(null);
    var page = WebPage.init(std.testing.allocator);
    defer page.deinit();
    try page.load("https://own.example/");
    try page.load("https://elsewhere.example/");
    _ = page.nativeView();
    // Trusted: the app's own page; loaded: the one asked for last.
    try std.testing.expectEqualStrings("create trust: https://own.example/ https://elsewhere.example/ ", TestBackend.record());
}

test "web page: a refused address is reported, read from the page's own copy, and kept until one is accepted" {
    TestBackend.reset();
    WebPage.setBackend(&TestBackend.backend);
    defer WebPage.setBackend(null);
    var page = WebPage.init(std.testing.allocator);
    defer page.deinit();
    // Asked for before the platform page exists: refused as it is made.
    try page.load("bad address");
    _ = page.nativeView();
    try std.testing.expectEqualStrings("Not an address: bad address", page.failure());
    // A retry with the page's own address, whose old bytes the load frees.
    try page.load(page.url());
    try std.testing.expectEqualStrings("Not an address: bad address", page.failure());
    // An unrelated report keeps it; an accepted address clears it.
    TestBackend.page.?.update(.{ .title = "Still here" });
    try std.testing.expectEqualStrings("Not an address: bad address", page.failure());
    try page.load("https://example.com/");
    try std.testing.expectEqualStrings("", page.failure());
}

test "web page: a platform that will not make a page is asked once, and says so" {
    TestBackend.reset();
    TestBackend.refuse_create = true;
    WebPage.setBackend(&TestBackend.backend);
    defer WebPage.setBackend(null);
    var page = WebPage.init(std.testing.allocator);
    defer page.deinit();
    try std.testing.expect(page.nativeView() == null);
    try std.testing.expect(page.nativeView() == null);
    try std.testing.expectEqualStrings("create ", TestBackend.record());
    try std.testing.expectEqualStrings("The web view could not be made.", page.failure());
}
