//! What view constructors read while a frame is built: the build arena, the
//! published theme and its tokens, the window size, the wrapped-text cache,
//! and the link handler.

const std = @import("std");
const log = std.log.scoped(.ziggui_build_scope);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The per-frame build state view constructors read. The arena, tokens,
/// theme and wrap cache are per thread (a render thread never races the main
/// loop); the window size and the link handler are the process's.
pub const BuildScope = struct {
    const Self = @This();

    /// The arena view constructors allocate from while a tree is built.
    arena: ?std.mem.Allocator = null,

    /// The published theme's build-time colors.
    build_tokens: mod.BuildTokens = .{},

    /// The theme `setTheme` last published (see `theme`).
    build_theme: renderer.Theme = renderer.MacosTheme.light,

    /// The wrapped-text cache, when the app installed one.
    wrap_cache: ?*mod.WrapCache = null,

    /// How many selectable views of each text (`TextSelection.contentHash`)
    /// the frame has built so far, for `selectionOrdinal`. Kept off the build
    /// arena, so it never outlives its memory; `begin` empties it.
    selection_counts: std.AutoHashMapUnmanaged(u64, u32) = .empty,

    /// The main window's frame being built (or last built), counted by `begin`
    /// from 1 (a popover window's `beginPopoverWindow` leaves it): what a view stamps
    /// its state with when it paints, so the event loop can tell a view the
    /// last frame drew from one scrolled or switched away (`ZoomState.contains`).
    frame_number: u64 = 0,

    /// The popover window's frame being built (or last built), counted by
    /// `beginPopoverWindow` from 1 and stepped by `forgetPopoverWindow` as the popover window
    /// hides: `frame_number`'s counterpart for a view the popover window drew.
    popover_window_frame_number: u64 = 0,

    /// How many stateless scroll views the frame has built so far, for
    /// `scrollViewKey`; `begin` and `beginPopoverWindow` empty it.
    scroll_count: u32 = 0,

    /// Whether the frame being built is a second window's (`beginPopoverWindow`),
    /// so its scroll views keep positions apart from the main window's.
    popover_window: bool = false,

    /// The current thread's scope.
    threadlocal var shared_scope: Self = .{};

    /// The window's size in design points, set by the app loop before each build
    /// so views can size to it (a reading column, table columns).
    var viewport_size: renderer.Size = .{ .width = 1100, .height = 760 };

    /// Called with the URL when a link span is tapped. The app sets it once.
    var link_handler: ?*const fn ([]const u8) void = null;

    /// Makes the tokens for a published theme in place of
    /// `BuildTokens.fromTheme`, when the app installed one (`setTokenProvider`).
    /// The process's, as the link handler is: the app sets it once.
    var token_provider: ?*const fn (renderer.Theme) mod.BuildTokens = null;

    /// The current thread's build scope.
    ///
    /// - Returns: the shared scope.
    pub fn shared() *Self {
        return &shared_scope;
    }

    /// Opens the build arena for a frame. The framework calls this each frame;
    /// tests call it directly. It is the frame boundary: the wrap cache may
    /// empty itself here, the last frame's tap regions being done with.
    ///
    /// - `self`: the scope.
    /// - `arena`: the arena view constructors allocate from.
    pub fn begin(self: *Self, arena: std.mem.Allocator) void {
        self.frame_number +%= 1;
        self.popover_window = false;
        self.open(arena);
    }

    /// Opens the build arena for a second window's frame (the popover window the
    /// SDL loop draws after the main window), as `begin` does, but leaves
    /// `frame_number`, which counts only the main window's frames: a view the
    /// main window drew stays the one its next events land on.
    ///
    /// - `self`: the scope.
    /// - `arena`: the arena view constructors allocate from.
    pub fn beginPopoverWindow(self: *Self, arena: std.mem.Allocator) void {
        self.popover_window_frame_number +%= 1;
        self.popover_window = true;
        self.open(arena);
    }

    /// The second window (the popover window) was hidden: what its last frame
    /// drew shows no more, so `isLatest` turns false for it until the popover window
    /// draws it again.
    ///
    /// - `self`: the scope.
    pub fn forgetPopoverWindow(self: *Self) void {
        self.popover_window_frame_number +%= 1;
    }

    /// The frame being built, in the window being drawn, for a view's state
    /// to keep (`isLatest`).
    ///
    /// - `self`: the scope.
    /// - Returns: the stamp.
    pub fn stamp(self: *const Self) mod.FrameStamp {
        return .{ .popover_window = self.popover_window, .number = if (self.popover_window) self.popover_window_frame_number else self.frame_number };
    }

    /// Whether a stamp is its window's last frame: what that frame drew is
    /// still on show, so the events that follow may reach it. A view the
    /// main window drew stays latest through the popover window's frames, and one the
    /// popover window drew through the main window's.
    ///
    /// - `self`: the scope.
    /// - `frame`: the stamp a view kept.
    /// - Returns: true while that window has not drawn (or hidden) since.
    pub fn isLatest(self: *const Self, frame: mod.FrameStamp) bool {
        return frame.number == (if (frame.popover_window) self.popover_window_frame_number else self.frame_number);
    }

    /// Closes the build arena.
    ///
    /// - `self`: the scope.
    pub fn end(self: *Self) void {
        self.arena = null;
    }

    /// The per-frame build arena, for constructors that allocate the slices and
    /// children they own.
    ///
    /// - `self`: the scope.
    /// - Returns: the arena; panics outside `begin`/`end`.
    pub fn allocator(self: *const Self) std.mem.Allocator {
        return self.arena orelse @panic("ziggui: view constructed outside BuildScope.begin()/end()");
    }

    /// Points the build arena at `arena` and hands back the one it replaced,
    /// for content built at paint time, after the frame's build has ended.
    ///
    /// - `self`: the scope.
    /// - `arena`: the arena to build in, or null to close it.
    /// - Returns: the arena it replaced, to restore afterwards.
    pub fn swapAllocator(self: *Self, arena: ?std.mem.Allocator) ?std.mem.Allocator {
        const saved = self.arena;
        self.arena = arena;
        return saved;
    }

    /// Which of the frame's selectable views with text `content` the one
    /// being built is: 0 for the first built since `begin`, 1 for the next.
    /// Views built at paint time (a `GeometryReader`'s) count on after the
    /// build's, in paint order. Build order is the same frame to frame, and
    /// does not change as a scroll view scrolls (painting skips what it
    /// hides, building does not), so the ordinal keeps a selection on its view.
    ///
    /// - `self`: the scope.
    /// - `content`: the view's `TextSelection.contentHash`.
    /// - Returns: the ordinal.
    pub fn selectionOrdinal(self: *Self, content: u64) u32 {
        // The process's allocator, not the build arena: the counts are emptied,
        // not freed, at each `begin`, and must not dangle between frames.
        const entry = self.selection_counts.getOrPut(std.heap.page_allocator, content) catch @panic("oom");
        entry.value_ptr.* = if (entry.found_existing) entry.value_ptr.* + 1 else 0;
        return entry.value_ptr.*;
    }

    /// The key a stateless scroll view keeps its position under
    /// (`ScrollMemory`): its place among the frame's stateless scroll views,
    /// in build order, and the window it is built for. Build order is the same
    /// frame to frame, so the key stays with its view while the views built
    /// before it stay the same.
    ///
    /// - `self`: the scope.
    /// - Returns: the key.
    pub fn scrollViewKey(self: *Self) u64 {
        const ordinal = self.scroll_count;
        self.scroll_count += 1;
        return (@as(u64, @intFromBool(self.popover_window)) << 32) | ordinal;
    }

    /// Formats a string in the build arena (for state-derived text).
    ///
    /// - `self`: the scope.
    /// - `format`: the format string.
    /// - `args`: its arguments.
    /// - Returns: the string, valid until the next frame.
    pub fn print(self: *const Self, comptime format: []const u8, args: anytype) []const u8 {
        return self.allocator().print(format, args) catch @panic("oom");
    }

    /// The active build-time theme tokens, for composed (theme-less) constructors.
    ///
    /// - `self`: the scope.
    /// - Returns: the tokens.
    pub fn tokens(self: *const Self) mod.BuildTokens {
        return self.build_tokens;
    }

    /// The whole theme `setTheme` last published, for composed constructors
    /// that need colors `BuildTokens` does not carry. Before any `setTheme` it
    /// is the macOS light theme, as `BuildTokens`' defaults are.
    ///
    /// - `self`: the scope.
    /// - Returns: the theme.
    pub fn theme(self: *const Self) renderer.Theme {
        return self.build_theme;
    }

    /// Publishes the active theme and its build-time tokens for composed
    /// constructors. Call once per frame (the app does this in its build step)
    /// before building views.
    ///
    /// - `self`: the scope.
    /// - `published`: the theme.
    pub fn setTheme(self: *Self, published: renderer.Theme) void {
        self.build_tokens = if (token_provider) |provider| provider(published) else mod.BuildTokens.fromTheme(published);
        self.build_theme = published;
    }

    /// Installs the app's design tokens: from the next `setTheme` on, the
    /// tokens are `provider(theme)` instead of `BuildTokens.fromTheme(theme)`,
    /// so an app with its own design system recolors ziggui's widgets. The
    /// provider may start from `BuildTokens.fromTheme` and change some roles.
    /// Null (the default) restores `fromTheme`.
    ///
    /// - `self`: the scope.
    /// - `provider`: makes the tokens for a theme; null for ziggui's own.
    pub fn setTokenProvider(self: *Self, provider: ?*const fn (renderer.Theme) mod.BuildTokens) void {
        _ = self;
        token_provider = provider;
    }

    /// The window's size in design points, as the frame being built is laid out at.
    ///
    /// - `self`: the scope.
    /// - Returns: the size.
    pub fn viewport(self: *const Self) renderer.Size {
        _ = self;
        return viewport_size;
    }

    /// Sets the window size `viewport` reports; the app runtime calls it, and
    /// headless frames do.
    ///
    /// - `self`: the scope.
    /// - `width`: the width, in points.
    /// - `height`: the height, in points.
    pub fn setViewport(self: *Self, width: f32, height: f32) void {
        _ = self;
        viewport_size = .{ .width = width, .height = height };
    }

    /// Sets the handler a tapped link calls.
    ///
    /// - `self`: the scope.
    /// - `handler`: called with the URL; null for none.
    pub fn setLinkHandler(self: *Self, handler: ?*const fn ([]const u8) void) void {
        _ = self;
        link_handler = handler;
    }

    /// Invokes the app's link handler directly (a button that opens a URL).
    ///
    /// - `self`: the scope.
    /// - `url`: the URL.
    pub fn openLink(self: *const Self, url: []const u8) void {
        _ = self;
        if (link_handler) |handler| handler(url);
    }

    /// Installs the per-thread wrapped-text cache (the app's render loop owns it
    /// and sets it once). Passing null disables caching (the default —
    /// headless/one-shot renders just re-wrap each time).
    ///
    /// - `self`: the scope.
    /// - `cache`: the cache, or null.
    pub fn setWrapCache(self: *Self, cache: ?*mod.WrapCache) void {
        self.wrap_cache = cache;
    }

    /// Wraps `text`, from the wrap cache when one is installed. The returned
    /// slice is valid for the current frame.
    ///
    /// - `self`: the scope.
    /// - `arena`: the frame arena.
    /// - `face`: the face the text is measured in.
    /// - `text`: the text.
    /// - `pixel_size`: its size.
    /// - `max_width`: the width it wraps to.
    /// - Returns: the wrapped lines.
    pub fn wrapText(self: *const Self, arena: std.mem.Allocator, face: *const renderer.TtfFont, text: []const u8, pixel_size: f32, max_width: f32) []renderer.WrappedLine {
        const cache = self.wrap_cache orelse
            return renderer.TextShaper.init(face).wrapText(arena, text, pixel_size, max_width) catch @panic("oom");
        return cache.wrap(arena, face, text, pixel_size, max_width);
    }

    /// Lays out a rich paragraph, from the wrap cache when one is installed.
    ///
    /// - `self`: the scope.
    /// - `arena`: the frame arena.
    /// - `spans`: the paragraph.
    /// - `faces`: the faces its spans are drawn in.
    /// - `pixel_size`: its base size.
    /// - `line_multiple`: line height as a multiple of the size.
    /// - `max_width`: the width it wraps to.
    /// - `preformatted`: preformatted (no wrapping).
    /// - Returns: the layout; propagates allocation failure.
    pub fn layoutRich(self: *const Self, arena: std.mem.Allocator, spans: []const mod.Span, faces: mod.RichFaces, pixel_size: f32, line_multiple: f32, max_width: f32, preformatted: bool) std.mem.Allocator.Error!mod.RichLayout {
        const cache = self.wrap_cache orelse return mod.RichLayout.layOut(arena, spans, faces, pixel_size, line_multiple, max_width, preformatted);
        return cache.layoutRich(arena, spans, faces, pixel_size, line_multiple, max_width, preformatted);
    }

    /// Starts a frame's build without counting it: the wrap cache may empty
    /// itself, the selection ordinals restart, and the arena opens.
    ///
    /// - `self`: the scope.
    /// - `arena`: the arena view constructors allocate from.
    fn open(self: *Self, arena: std.mem.Allocator) void {
        if (self.wrap_cache) |cache| cache.beginFrame();
        self.selection_counts.clearRetainingCapacity();
        self.scroll_count = 0;
        self.arena = arena;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "view: buildTheme returns the theme setThemeTokens published" {
    const scope = BuildScope.shared();
    scope.setTheme(renderer.MacosTheme.dark);
    defer scope.setTheme(renderer.MacosTheme.light);
    try std.testing.expect(scope.theme().scheme == .dark);
    try std.testing.expect(scope.theme().colors.label.r == renderer.MacosTheme.dark.colors.label.r);
}

test "a token provider's tokens reach tokens(), and clearing it restores fromTheme" {
    const Provider = struct {
        const Self = @This();

        /// The macOS tokens with an orange warning.
        ///
        /// - `theme`: the theme.
        /// - Returns: the tokens.
        fn tokens(theme: renderer.Theme) mod.BuildTokens {
            var made = mod.BuildTokens.fromTheme(theme);
            made.warning = renderer.Color.fromRgb8(255, 128, 0);
            return made;
        }
    };
    const scope = BuildScope.shared();
    scope.setTokenProvider(Provider.tokens);
    defer scope.setTokenProvider(null);
    scope.setTheme(renderer.MacosTheme.light);
    try std.testing.expectEqual(renderer.Color.fromRgb8(255, 128, 0), scope.tokens().warning);

    scope.setTokenProvider(null);
    scope.setTheme(renderer.MacosTheme.light);
    try std.testing.expectEqual(mod.BuildTokens.fromTheme(renderer.MacosTheme.light).warning, scope.tokens().warning);
}

test "a frame stamp stays latest through the other window's frames, until its own window draws or the popover window hides" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const scope = BuildScope.shared();
    const saved_main = scope.frame_number;
    const saved_popover = scope.popover_window_frame_number;
    defer {
        scope.frame_number = saved_main;
        scope.popover_window_frame_number = saved_popover;
        scope.popover_window = false;
    }

    scope.begin(arena.allocator());
    const main_frame = scope.stamp();
    scope.end();
    scope.beginPopoverWindow(arena.allocator());
    const popover_frame = scope.stamp();
    scope.end();
    try std.testing.expect(popover_frame.popover_window and !main_frame.popover_window);
    // Each window's frame leaves the other's stamps latest.
    try std.testing.expect(scope.isLatest(main_frame) and scope.isLatest(popover_frame));
    scope.begin(arena.allocator());
    scope.end();
    try std.testing.expect(!scope.isLatest(main_frame) and scope.isLatest(popover_frame));
    // A hidden popover window shows nothing it drew.
    scope.forgetPopoverWindow();
    try std.testing.expect(!scope.isLatest(popover_frame));
}
