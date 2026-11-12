//! A headless frame for the unit tests: draws a view tree and replays taps and pointer moves (a test fixture).

const std = @import("std");
const log = std.log.scoped(.ziggui_test_canvas);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A headless frame for the unit tests: builds a view tree, draws it with
/// ziggui's software rasterizer, and replays taps on what it drew.
///
/// Heap-allocated (`create`), because the glyph caches point into its fonts.
pub const TestCanvas = struct {
    const Self = @This();

    /// The allocator the canvas and its frames come from.
    allocator: std.mem.Allocator,

    /// The build and frame arena, reset by each `begin`.
    arena: std.heap.ArenaAllocator,

    /// The text face.
    font: renderer.Font,

    /// The icon face.
    icon_font: renderer.Font,

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

    /// The overlays (popovers, sheets, alerts) the last `render` drew.
    overlays: std.ArrayList(mod.OverlayRequest) = .empty,

    /// Makes a canvas.
    ///
    /// - `allocator`: allocator for the canvas, its caches and its frames.
    /// - Returns: the canvas, owned by the caller (`destroy`); propagates allocation failure.
    pub fn create(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .arena = .init(allocator),
            .font = renderer.Font.default(),
            .icon_font = renderer.Font.icons(),
            .cache = undefined,
            .icon_cache = undefined,
        };
        self.cache = renderer.GlyphCache.init(allocator, &self.font.face);
        self.icon_cache = renderer.GlyphCache.init(allocator, &self.icon_font.face);
        return self;
    }

    /// Frees the canvas, its caches and its last frame.
    ///
    /// - `self`: the canvas; invalid afterwards.
    pub fn destroy(self: *Self) void {
        self.icon_cache.deinit();
        self.cache.deinit();
        self.arena.deinit();
        self.allocator.destroy(self);
    }

    /// Starts building a frame in `theme`: publishes its tokens and opens the build arena.
    ///
    /// - `self`: the canvas.
    /// - `theme`: the theme to build and draw with.
    pub fn begin(self: *Self, theme: renderer.Theme) void {
        _ = self.arena.reset(.retain_capacity);
        self.hits = .empty;
        self.hovers = .empty;
        self.overlays = .empty;
        self.theme = theme;
        mod.BuildScope.shared().setTheme(theme);
        mod.BuildScope.shared().begin(self.arena.allocator());
    }

    /// Closes the build arena, as the app does before it draws.
    ///
    /// - `self`: the canvas.
    pub fn end(self: *const Self) void {
        _ = self;
        mod.BuildScope.shared().end();
    }

    /// Draws `view` at `width` × `height` points on a white background.
    ///
    /// - `self`: the canvas.
    /// - `view`: the tree built since `begin`.
    /// - `width`: the frame's width.
    /// - `height`: the frame's height.
    /// - Returns: the pixels, owned by the caller (`deinit`); propagates allocation failure.
    pub fn render(self: *Self, view: mod.View, width: u32, height: u32) !renderer.Framebuffer {
        const arena = self.arena.allocator();
        var context = mod.Context.init(self.theme, &self.cache, arena, &self.hits);
        context.icon_cache = &self.icon_cache;
        context.hover_regions = &self.hovers;
        context.overlays = &self.overlays;
        var canvas = renderer.Canvas.init(arena);
        const full: renderer.Rect = .{ .x = 0, .y = 0, .width = @floatFromInt(width), .height = @floatFromInt(height) };
        try mod.ViewRenderer.render(&context, view, full, &canvas);
        var framebuffer = try renderer.Framebuffer.init(self.allocator, width, height);
        errdefer framebuffer.deinit();
        framebuffer.clear(renderer.Color.white);
        try renderer.Rasterizer.init(self.allocator, &framebuffer).render(canvas.commands.items);
        return framebuffer;
    }

    /// Taps the last frame at `point`, as a click would.
    ///
    /// - `self`: the canvas.
    /// - `point`: where to tap, in points.
    /// - Returns: whether a region took the tap.
    pub fn tap(self: *const Self, point: renderer.Point) bool {
        return mod.PointerInput.shared().tap(self.hits.items, point);
    }

    /// Moves the pointer over the last frame from `from` to `to`, as a mouse
    /// motion would: views whose frame it entered or left hear of it (`onHover`).
    ///
    /// - `self`: the canvas.
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

test "a test canvas draws a view and replays a tap on it" {
    const canvas = try TestCanvas.create(std.testing.allocator);
    defer canvas.destroy();
    const Probe = struct {
        const Self = @This();
        tapped: bool = false,
        fn onTap(self: *Self) void {
            self.tapped = true;
        }
    };
    var probe: Probe = .{};
    canvas.begin(renderer.MacosTheme.light);
    const view = mod.Rectangle(renderer.Color.red).onTap(mod.Callback.init(Probe, &probe, Probe.onTap));
    canvas.end();
    var frame = try canvas.render(view, 20, 20);
    defer frame.deinit();
    try std.testing.expect(frame.at(10, 10).r > 0.9);
    try std.testing.expect(canvas.tap(.{ .x = 10, .y = 10 }));
    try std.testing.expect(probe.tapped);
}
