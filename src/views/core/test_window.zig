//! A headless window for the unit tests: draws a view tree and replays taps and pointer moves (a test fixture).

const std = @import("std");
const log = std.log.scoped(.ziggui_test_window);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A headless window for the unit tests: builds a view tree, draws it with
/// ziggui's software rasterizer, and replays taps on what it drew.
///
/// Heap-allocated (`create`), because the glyph caches point into its fonts.
pub const TestWindow = struct {
    const Self = @This();

    /// The allocator the window and its frames come from.
    allocator: std.mem.Allocator,

    /// The build and frame arena, reset by each `begin`.
    arena: std.heap.ArenaAllocator,

    /// The text face.
    font: renderer.FontFile,

    /// The icon face.
    icon_font: renderer.FontFile,

    /// Glyphs of `font`.
    cache: renderer.GlyphCache,

    /// Glyphs of `icon_font`.
    icon_cache: renderer.GlyphCache,

    /// The theme the current frame is built and drawn with.
    theme: renderer.Theme = renderer.MacosTheme.light,

    /// The tap regions the last `render` registered.
    hits: std.ArrayList(mod.HitRegion) = .empty,

    /// The `onHover` regions the last `render` registered.
    hovers: std.ArrayList(mod.HoverRegion) = .empty,

    /// The scroll regions the last `render` registered.
    scrolls: std.ArrayList(mod.ScrollRegion) = .empty,

    /// Where the pointer rests for the next `render`, or null (outside the window).
    hover_point: ?renderer.Point = null,

    /// Where the primary button is held for the next `render`, or null.
    press_point: ?renderer.Point = null,

    /// The overlays (popovers, sheets, alerts) the last `render` drew.
    overlays: std.ArrayList(mod.OverlayRequest) = .empty,

    /// Makes a window.
    ///
    /// - `allocator`: allocator for the window, its caches and its frames.
    /// - Returns: the window, owned by the caller (`destroy`); propagates allocation failure.
    pub fn create(allocator: std.mem.Allocator) !*Self {
        // Stateless scroll views start at the top, whatever an earlier test scrolled.
        mod.ScrollMemory.shared().reset();
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .arena = .init(allocator),
            .font = renderer.FontFile.default(),
            .icon_font = renderer.FontFile.icons(),
            .cache = undefined,
            .icon_cache = undefined,
        };
        self.cache = renderer.GlyphCache.init(allocator, &self.font.face);
        self.icon_cache = renderer.GlyphCache.init(allocator, &self.icon_font.face);
        return self;
    }

    /// Frees the window, its caches and its last frame.
    ///
    /// - `self`: the window; invalid afterwards.
    pub fn destroy(self: *Self) void {
        self.icon_cache.deinit();
        self.cache.deinit();
        self.arena.deinit();
        self.allocator.destroy(self);
    }

    /// Starts building a frame in `theme`: publishes its tokens and opens the build arena.
    ///
    /// - `self`: the window.
    /// - `theme`: the theme to build and draw with.
    pub fn begin(self: *Self, theme: renderer.Theme) void {
        _ = self.arena.reset(.retain_capacity);
        self.hits = .empty;
        self.hovers = .empty;
        self.scrolls = .empty;
        self.overlays = .empty;
        self.theme = theme;
        mod.BuildScope.shared().setTheme(theme);
        mod.BuildScope.shared().begin(self.arena.allocator());
    }

    /// Closes the build arena, as the app does before it draws.
    ///
    /// - `self`: the window.
    pub fn end(self: *const Self) void {
        _ = self;
        mod.BuildScope.shared().end();
    }

    /// Draws `view` at `width` × `height` points on a white background.
    ///
    /// - `self`: the window.
    /// - `view`: the tree built since `begin`.
    /// - `width`: the frame's width.
    /// - `height`: the frame's height.
    /// - Returns: the pixels, owned by the caller (`deinit`); propagates allocation failure.
    pub fn render(self: *Self, view: mod.View, width: u32, height: u32) !renderer.Framebuffer {
        const arena = self.arena.allocator();
        var context = mod.Context.init(self.theme, &self.cache, arena, &self.hits);
        context.icon_cache = &self.icon_cache;
        context.hover_regions = &self.hovers;
        context.scroll_regions = &self.scrolls;
        context.hover_point = self.hover_point;
        context.press_point = self.press_point;
        context.overlays = &self.overlays;
        var display_list = renderer.DisplayList.init(arena);
        const full: renderer.Rect = .{ .x = 0, .y = 0, .width = @floatFromInt(width), .height = @floatFromInt(height) };
        try mod.ViewRenderer.render(&context, view, full, &display_list);
        var framebuffer = try renderer.Framebuffer.init(self.allocator, width, height);
        errdefer framebuffer.deinit();
        framebuffer.clear(renderer.Color.white);
        try renderer.Rasterizer.init(self.allocator, &framebuffer).render(display_list.commands.items);
        return framebuffer;
    }

    /// Taps the last frame at `point`, as a click would.
    ///
    /// - `self`: the window.
    /// - `point`: where to tap, in points.
    /// - Returns: whether a region took the tap.
    pub fn tap(self: *const Self, point: renderer.Point) bool {
        return mod.PointerInput.shared().tap(self.hits.items, point);
    }

    /// Turns the wheel over the last frame at `point`, as a mouse wheel or a
    /// trackpad would: the scroll view under it moves (`PointerInput.scrollBoth`).
    ///
    /// - `self`: the window.
    /// - `point`: the pointer, in points.
    /// - `delta_x`: the sideways delta, positive to the right.
    /// - `delta_y`: the vertical delta, positive away from the user.
    /// - Returns: whether a region took the event.
    pub fn scroll(self: *const Self, point: renderer.Point, delta_x: f32, delta_y: f32) bool {
        return mod.PointerInput.shared().scrollBoth(self.scrolls.items, point, delta_x, delta_y);
    }

    /// Moves the pointer over the last frame from `from` to `to`, as a mouse
    /// motion would: views whose frame it entered or left hear of it (`onHover`).
    ///
    /// - `self`: the window.
    /// - `from`: where the pointer was, or null outside the window.
    /// - `to`: where it is now, or null outside the window.
    /// - Returns: whether any `onHover` callback fired.
    pub fn hover(self: *const Self, from: ?renderer.Point, to: ?renderer.Point) bool {
        return mod.PointerInput.shared().hover(self.hovers.items, from, to);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a test window draws a view and replays a tap on it" {
    const window = try TestWindow.create(std.testing.allocator);
    defer window.destroy();
    const Probe = struct {
        const Self = @This();
        /// Whether the button was tapped.
        tapped: bool = false,
        /// Notes the tap.
        ///
        /// - `self`: the probe.
        fn onTap(self: *Self) void {
            self.tapped = true;
        }
    };
    var probe: Probe = .{};
    window.begin(renderer.MacosTheme.light);
    const view = mod.Rectangle(renderer.Color.red).onTapGesture(mod.Callback.init(Probe, &probe, Probe.onTap));
    window.end();
    var frame = try window.render(view, 20, 20);
    defer frame.deinit();
    try std.testing.expect(frame.at(10, 10).r > 0.9);
    try std.testing.expect(window.tap(.{ .x = 10, .y = 10 }));
    try std.testing.expect(probe.tapped);
}
