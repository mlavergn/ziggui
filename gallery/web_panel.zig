const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_web_panel);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The bridge the start page's Send button posts to; the page names it too.
const bridge_name: []const u8 = "gallery";

/// The address field's hint.
const address_hint: []const u8 = "Enter a URL, like ziglang.org";

/// The start page, as authored.
const start_html: []const u8 =
    \\<!doctype html>
    \\<html><head><meta charset="utf-8"><title>ziggui Web View</title>
    \\<style>
    \\  :root { color-scheme: light dark; font: 14px -apple-system, system-ui, sans-serif; }
    \\  body { margin: 0; padding: 20px; }
    \\  h1 { font-size: 17px; margin: 0 0 4px; }
    \\  p { margin: 0 0 14px; opacity: .7; }
    \\  input { width: 100%; box-sizing: border-box; padding: 6px 8px; margin-bottom: 8px; }
    \\  output { display: block; margin-top: 12px; }
    \\</style></head>
    \\<body>
    \\<h1>ziggui Web View</h1>
    \\<p>An inline page in a <code>WebView</code>, placed by ziggui. Send posts the field to the <code>gallery</code> bridge, and the panel shows what arrives; ⌘C, ⌘X, ⌘V and ⌘A edit the field. Follow <a href="https://ziglang.org/">ziglang.org</a>, then go back.</p>
    \\<input id="text" value="Sent through the gallery bridge">
    \\<button id="send">Send</button>
    \\<output id="status"></output>
    \\<script>
    \\  const bridge = window.webkit?.messageHandlers?.gallery;
    \\  const status = document.getElementById('status');
    \\  status.textContent = bridge ? 'Bridge registered.' : 'No bridge: this is not a native view.';
    \\  document.getElementById('send').addEventListener('click', () => {
    \\    if (!bridge) return;
    \\    bridge.postMessage(document.getElementById('text').value);
    \\    status.textContent = 'Sent.';
    \\  });
    \\</script>
    \\</body></html>
;

/// What `start_url` carries ahead of the encoded page.
const start_url_prefix: []const u8 = "data:text/html;charset=utf-8;base64,";

/// The start page as a `data:` URL, encoded at compile time: base64, whose
/// every byte is legal in a URL.
const start_url: []const u8 = blk: {
    @setEvalBranchQuota(100_000);
    const encoder = std.base64.standard.Encoder;
    var buffer: [encoder.calcSize(start_html.len)]u8 = undefined;
    _ = encoder.encode(&buffer, start_html);
    const encoded = buffer;
    break :blk start_url_prefix ++ &encoded;
};

/// The most of a page's message the panel keeps to show: a line's worth.
const max_message_bytes: usize = 256;

/// The Web View panel: a `WebPage` shown by a `WebView` under a browser's
/// toolbar (back, forward, reload, the address, home, bookmarks), its start
/// page posting to a bridge. Ported from zigwebview's browser shell.
pub const WebPanel = struct {
    const Self = @This();

    /// Owns the page, the field and the bookmarks.
    allocator: std.mem.Allocator,

    /// The page.
    page: ziggui.WebPage,

    /// The address field: Enter or Go loads what it holds, a blank one the start page.
    address: ziggui.TextFieldState,

    /// The saved sites, in memory.
    bookmarks: gallery.Bookmarks,

    /// Whether the Bookmarks menu is open.
    bookmarks_open: ziggui.State(bool),

    /// The last message the page posted, its first `max_message_bytes`, copied.
    message: std.ArrayList(u8) = .empty,

    /// The page address the field last showed, so a change is shown once,
    /// and not while the field is typed in.
    followed_url: std.ArrayList(u8) = .empty,

    /// The page as a panel, its start page asked for and its bridge registered;
    /// the platform page is made as the panel first shows.
    ///
    /// - `allocator`: owns the page, the field and the bookmarks.
    /// - Returns: the panel; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        var self = Self{
            .allocator = allocator,
            .page = ziggui.WebPage.init(allocator),
            .address = ziggui.TextFieldState.init(allocator),
            .bookmarks = gallery.Bookmarks.init(allocator),
            .bookmarks_open = ziggui.State(bool).init(allocator, false),
        };
        errdefer self.deinit();
        try self.page.addBridge(bridge_name);
        try self.page.load(start_url);
        return self;
    }

    /// Frees the page (taking its view out of the window), the field and the bookmarks.
    ///
    /// - `self`: the panel.
    pub fn deinit(self: *Self) void {
        self.followed_url.deinit(self.allocator);
        self.message.deinit(self.allocator);
        self.bookmarks_open.deinit();
        self.bookmarks.deinit();
        self.address.deinit();
        self.page.deinit();
    }

    /// The panel, title included: the toolbar, a failed load's reason, the
    /// page filling the rest, and the page's title and last message. It fills
    /// the pane, so the gallery does not scroll it.
    ///
    /// - `self`: the panel.
    /// - `theme`: the theme this frame draws with.
    /// - `title`: the panel's title.
    /// - Returns: the panel's view.
    pub fn panel(self: *Self, theme: ziggui.Theme, title: []const u8) ziggui.View {
        // Here, not in `init`: the panel has its final address only now.
        self.page.onChange(ziggui.Callback.init(Self, self, Self.followPage));
        self.page.onMessage(ziggui.WebPageMessageCallback.init(Self, self, Self.received));
        // Also here, not only on a change: one that came while the field was
        // typed in shows once the field lets go.
        self.followPage();
        const tokens = ziggui.BuildScope.shared().tokens();
        const submit = ziggui.Callback.init(Self, self, Self.go);
        const toolbar = ziggui.HStack(.{
            ziggui.IconButton(.chevronLeft, 16, ziggui.Callback.init(ziggui.WebPage, &self.page, ziggui.WebPage.goBack)).disabled(!self.page.canGoBack()),
            ziggui.IconButton(.chevronRight, 16, ziggui.Callback.init(ziggui.WebPage, &self.page, ziggui.WebPage.goForward)).disabled(!self.page.canGoForward()),
            ziggui.IconButton(.rotateCw, 16, ziggui.Callback.init(ziggui.WebPage, &self.page, ziggui.WebPage.reload)),
            ziggui.TextField(address_hint, &self.address).onSubmit(submit).frameHeight(28).frameMaxWidth(),
            ziggui.Button("Go", submit),
            ziggui.IconButton(.house, 16, ziggui.Callback.init(Self, self, Self.home)),
            ziggui.IconButton(if (self.bookmarks.contains(self.page.url())) .bookmarkCheck else .bookmarkPlus, 16, ziggui.Callback.init(Self, self, Self.toggleBookmark)),
            ziggui.Menu("Bookmarks", &self.bookmarks_open, self.bookmarkItems()),
        }).spacing(8).frameMaxWidth();
        const failure = self.page.failure();
        const status = ziggui.BuildScope.shared().allocator().print("{s}{s}{s}", .{
            if (self.page.title().len > 0) self.page.title() else "Untitled",
            if (self.message.items.len > 0) " · Message: " else "",
            self.message.items,
        }) catch @panic("oom");
        return ziggui.VStack(.{
            ziggui.HStack(.{ ziggui.Text(title).font(.largeTitle), ziggui.Spacer() }).frameMaxWidth(),
            toolbar,
            if (failure.len > 0) ziggui.Text(failure).foreground(tokens.removed).truncated().frameMaxWidth().frameAlign(.leading) else ziggui.Empty(),
            ziggui.WebView(&self.page).cornerRadius(theme.metrics.corner_radius).border(theme.colors.separator, theme.metrics.hairline).frameMaxWidth().frameMaxHeight(),
            ziggui.Text(status).font(.footnote).foreground(tokens.secondary_label).truncated().frameMaxWidth().frameAlign(.leading),
            ziggui.Text("ziggui.WebView · ziggui.WebPage · ziggui.WebPageMessageCallback").font(.caption).mono().foreground(tokens.secondary_label).frameMaxWidth().frameAlign(.leading),
        }).spacing(10).padding(20).frameMaxWidth().frameMaxHeight();
    }

    /// The address to load for what the field holds: a bare host gains
    /// `https://`, anything naming a scheme is kept.
    ///
    /// - `self`: the panel, whose allocator owns the address.
    /// - `text`: the address as typed, surrounding spaces ignored.
    /// - Returns: the address (the caller frees it), or null when the field is
    ///   blank; propagates allocation failure.
    pub fn urlFor(self: *const Self, text: []const u8) std.mem.Allocator.Error!?[]u8 {
        const typed = std.mem.trim(u8, text, " \t\r\n");
        if (typed.len == 0) return null;
        if (std.mem.find(u8, typed, "://") != null) return try self.allocator.dupe(u8, typed);
        for ([_][]const u8{ "data:", "file:", "about:" }) |scheme| {
            if (std.mem.startsWith(u8, typed, scheme)) return try self.allocator.dupe(u8, typed);
        }
        return try self.allocator.print("https://{s}", .{typed});
    }

    /// What the field shows for a page's address: nothing for an inline
    /// `data:` page, whose address is the whole page.
    ///
    /// - `current`: the page's address.
    /// - Returns: the text for the field.
    pub fn addressFor(current: []const u8) []const u8 {
        return if (std.mem.startsWith(u8, current, "data:")) "" else current;
    }

    /// The page's `onChange`, and each build: shows the page's address in
    /// the field once it changes, unless the field is being typed in. A
    /// change that is no change of address (a refused one, a title) leaves
    /// what the user typed.
    ///
    /// - `self`: the panel.
    fn followPage(self: *Self) void {
        const current = self.page.url();
        if (std.mem.eql(u8, current, self.followed_url.items)) return;
        if (ziggui.Focus.shared().focused() == &self.address) return;
        self.followed_url.clearRetainingCapacity();
        self.followed_url.appendSlice(self.allocator, current) catch |err| {
            log.warn("page not followed [{t}]", .{err});
            return;
        };
        self.address.setText(Self.addressFor(current)) catch |err| log.warn("address not shown [{t}]", .{err});
    }

    /// The page's `onMessage`: keeps a copy of the message's body to show,
    /// its first `max_message_bytes` (cut on a character), a line's worth.
    ///
    /// - `self`: the panel.
    /// - `message`: the message, borrowed for the call.
    fn received(self: *Self, message: ziggui.WebPageMessage) void {
        var length = @min(message.body.len, max_message_bytes);
        if (length < message.body.len) {
            while (length > 0 and (message.body[length] & 0xC0) == 0x80) length -= 1;
        }
        self.message.clearRetainingCapacity();
        self.message.appendSlice(self.allocator, message.body[0..length]) catch |err| log.warn("message not kept [{t}]", .{err});
    }

    /// Loads what the field holds, or the start page when it is blank.
    ///
    /// - `self`: the panel.
    fn go(self: *Self) void {
        const typed = self.urlFor(self.address.text()) catch |err| {
            log.warn("address not built [{t}]", .{err});
            return;
        };
        defer if (typed) |url| self.allocator.free(url);
        // Let go of the field, so it shows the page's real address once loaded.
        if (ziggui.Focus.shared().focused() == &self.address) ziggui.Focus.shared().clear();
        self.page.load(typed orelse start_url) catch |err| log.warn("page not loaded [{t}]", .{err});
    }

    /// Loads the start page.
    ///
    /// - `self`: the panel.
    fn home(self: *Self) void {
        self.page.load(start_url) catch |err| log.warn("page not loaded [{t}]", .{err});
    }

    /// Saves the page showing, or forgets it when it is saved already.
    ///
    /// - `self`: the panel.
    fn toggleBookmark(self: *Self) void {
        const url = self.page.url();
        if (url.len == 0) return;
        if (self.bookmarks.contains(url)) return self.bookmarks.remove(url);
        const page_title = self.page.title();
        self.bookmarks.add(if (page_title.len > 0) page_title else url, url) catch |err| log.warn("bookmark not saved [{t}]", .{err});
    }

    /// Loads a bookmark and closes the menu.
    ///
    /// - `self`: the panel.
    /// - `index`: the bookmark's place in the list.
    fn openBookmark(self: *Self, index: usize) void {
        self.bookmarks_open.set(false);
        const saved = self.bookmarks.list();
        if (index >= saved.len) return;
        self.address.setText(saved[index].url) catch |err| log.warn("address not shown [{t}]", .{err});
        self.page.load(saved[index].url) catch |err| log.warn("page not loaded [{t}]", .{err});
    }

    /// The Bookmarks menu's entries: one per saved site, or a note when there
    /// are none; none at all while the menu is closed, which shows none.
    ///
    /// - `self`: the panel the entries open bookmarks in.
    /// - Returns: the entries, in the build arena.
    fn bookmarkItems(self: *Self) []const ziggui.View {
        if (!self.bookmarks_open.get()) return &.{};
        const tokens = ziggui.BuildScope.shared().tokens();
        const arena = ziggui.BuildScope.shared().allocator();
        const saved = self.bookmarks.list();
        if (saved.len == 0) {
            const empty = arena.alloc(ziggui.View, 1) catch @panic("oom");
            empty[0] = ziggui.Text("No bookmarks yet").foreground(tokens.secondary_label).padding(6);
            return empty;
        }
        const items = arena.alloc(ziggui.View, saved.len) catch @panic("oom");
        for (saved, items, 0..) |bookmark, *item, index| {
            item.* = ziggui.MenuItem(bookmark.title, ziggui.Callback.tagged(Self, self, Self.openBookmark, index));
        }
        return items;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// Helpers for the tests below.
const TestSupport = struct {
    const Self = @This();

    /// Checks the address the panel builds for what was typed.
    ///
    /// - `panel`: the panel building it.
    /// - `expected`: the address it should build.
    /// - `typed`: what was typed.
    /// - Returns: nothing; fails the test on another address, or none.
    fn expectUrl(panel: *const WebPanel, expected: []const u8, typed: []const u8) !void {
        const url = (try panel.urlFor(typed)) orelse return error.TestExpectedUrl;
        defer panel.allocator.free(url);
        try std.testing.expectEqualStrings(expected, url);
    }
};

test {
    std.testing.refAllDecls(@This());
    _ = gallery;
}

test "web panel: the start page decodes back to what was authored, and posts to its bridge" {
    const allocator = std.testing.allocator;
    try std.testing.expect(std.mem.startsWith(u8, start_url, start_url_prefix));
    const encoded = start_url[start_url_prefix.len..];
    const decoder = std.base64.standard.Decoder;
    const decoded = try allocator.alloc(u8, try decoder.calcSizeForSlice(encoded));
    defer allocator.free(decoded);
    try decoder.decode(decoded, encoded);
    try std.testing.expectEqualStrings(start_html, decoded);
    try std.testing.expect(std.mem.find(u8, start_html, "messageHandlers?." ++ bridge_name) != null);
}

test "web panel: a bare host gains https, a scheme is kept, a blank field is none" {
    ziggui.WebPage.setBackend(null);
    var panel = try WebPanel.init(std.testing.allocator);
    defer panel.deinit();
    try TestSupport.expectUrl(&panel, "https://ziglang.org", " ziglang.org\n");
    try TestSupport.expectUrl(&panel, "http://localhost:8080/", "http://localhost:8080/");
    try TestSupport.expectUrl(&panel, "file:///tmp/a.html", "file:///tmp/a.html");
    try TestSupport.expectUrl(&panel, "about:blank", "about:blank");
    try std.testing.expect(try panel.urlFor("  ") == null);
    try std.testing.expectEqualStrings("", WebPanel.addressFor(start_url));
}

test "web panel: the field follows the page unless typed in, and a message is kept" {
    ziggui.WebPage.setBackend(null);
    var panel = try WebPanel.init(std.testing.allocator);
    defer panel.deinit();
    panel.page.onChange(ziggui.Callback.init(WebPanel, &panel, WebPanel.followPage));
    panel.page.onMessage(ziggui.WebPageMessageCallback.init(WebPanel, &panel, WebPanel.received));
    panel.page.update(.{ .url = "https://ziglang.org/", .title = "Zig" });
    try std.testing.expectEqualStrings("https://ziglang.org/", panel.address.text());
    // Typed in, the field keeps what the user typed.
    ziggui.Focus.shared().set(&panel.address);
    defer ziggui.Focus.shared().clear();
    try panel.address.setText("example");
    panel.page.update(.{ .url = "https://ziglang.org/learn/", .title = "Learn" });
    try std.testing.expectEqualStrings("example", panel.address.text());
    panel.page.receive(.{ .bridge = bridge_name, .body = "hello" });
    try std.testing.expectEqualStrings("hello", panel.message.items);
}

test "web panel: a bookmark toggles on the page showing" {
    ziggui.WebPage.setBackend(null);
    var panel = try WebPanel.init(std.testing.allocator);
    defer panel.deinit();
    panel.page.update(.{ .url = "https://ziglang.org/", .title = "Zig" });
    panel.toggleBookmark();
    try std.testing.expect(panel.bookmarks.contains("https://ziglang.org/"));
    try std.testing.expectEqualStrings("Zig", panel.bookmarks.list()[0].title);
    panel.toggleBookmark();
    try std.testing.expect(!panel.bookmarks.contains("https://ziglang.org/"));
}

test "web panel: a refused address leaves what was typed; a change while typing shows once the field lets go" {
    ziggui.WebPage.setBackend(null);
    var panel = try WebPanel.init(std.testing.allocator);
    defer panel.deinit();
    panel.page.onChange(ziggui.Callback.init(WebPanel, &panel, WebPanel.followPage));
    panel.page.update(.{ .url = "https://ziglang.org/" });
    try std.testing.expectEqualStrings("https://ziglang.org/", panel.address.text());
    // A report that is no change of address leaves the typed text.
    try panel.address.setText("ziglang.or");
    panel.page.update(.{ .url = "https://ziglang.org/", .title = "Zig" });
    try std.testing.expectEqualStrings("ziglang.or", panel.address.text());
    // A new address while typing waits for the field to let go.
    ziggui.Focus.shared().set(&panel.address);
    panel.page.update(.{ .url = "https://ziglang.org/learn/" });
    try std.testing.expectEqualStrings("ziglang.or", panel.address.text());
    ziggui.Focus.shared().clear();
    panel.followPage();
    try std.testing.expectEqualStrings("https://ziglang.org/learn/", panel.address.text());
}

test "web panel: a long message is kept to a line's worth" {
    ziggui.WebPage.setBackend(null);
    var panel = try WebPanel.init(std.testing.allocator);
    defer panel.deinit();
    // 200 two-byte characters: the cut lands between two of them.
    var body: [400]u8 = undefined;
    for (0..200) |index| {
        body[index * 2] = 0xC3;
        body[index * 2 + 1] = 0xA9;
    }
    panel.received(.{ .bridge = bridge_name, .body = &body });
    try std.testing.expectEqual(@as(usize, max_message_bytes), panel.message.items.len);
    try std.testing.expect(std.unicode.utf8ValidateSlice(panel.message.items));
}
