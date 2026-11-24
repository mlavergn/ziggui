//! A headless frame: the fonts and caches a view tree is drawn with, the
//! tree built, laid out and painted to draw commands as a window's frame
//! would be, and the commands drawn by the software rasterizer. Under
//! `Screenshot.render`, and the gallery's `--gpu` and `--bench`, which draw
//! the same commands through the GPU or time them.

const std = @import("std");
const log = std.log.scoped(.ziggui_screenshot_frame);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// The fonts, caches and arena a headless frame is built with, and the last
/// built frame's draw commands. Heap-allocated (`create`), because the glyph
/// caches point into its fonts.
pub const ScreenshotFrame = struct {
    const Self = @This();

    /// The allocator the frame, its caches and its images come from.
    allocator: std.mem.Allocator,

    /// The size and theme the frame is drawn at, and how many frames settle first.
    options: mod.ScreenshotOptions,

    /// The build and paint arena; holds `commands`.
    arena: std.heap.ArenaAllocator,

    /// The text face; falls back to `emoji_font`.
    font: renderer.FontFile,

    /// The emoji face.
    emoji_font: renderer.FontFile,

    /// The icon face.
    icon_font: renderer.FontFile,

    /// Glyphs of `font`.
    cache: renderer.GlyphCache,

    /// Glyphs of `icon_font`.
    icon_cache: renderer.GlyphCache,

    /// The faces styled text draws with.
    fonts: *renderer.FontSet,

    /// The last built frame's draw commands, in `arena`.
    commands: []const renderer.DrawCommand = &.{},

    /// Makes a frame with nothing built yet.
    ///
    /// - `allocator`: allocator for the frame, its caches and its images.
    /// - `options`: the size, theme and frame count.
    /// - Returns: the frame, owned by the caller (`destroy`); propagates allocation failure.
    pub fn create(allocator: std.mem.Allocator, options: mod.ScreenshotOptions) !*Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });

        const fonts = try renderer.FontSet.create(allocator);
        errdefer fonts.destroy();
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .options = options,
            .arena = .init(allocator),
            .font = renderer.FontFile.default(),
            .emoji_font = renderer.FontFile.emoji(),
            .icon_font = renderer.FontFile.icons(),
            .cache = undefined,
            .icon_cache = undefined,
            .fonts = fonts,
        };
        self.font.face.fallback = &self.emoji_font.face;
        self.cache = renderer.GlyphCache.init(allocator, &self.font.face);
        self.icon_cache = renderer.GlyphCache.init(allocator, &self.icon_font.face);
        return self;
    }

    /// Frees the frame and its caches.
    ///
    /// - `self`: the frame; invalid afterwards.
    pub fn destroy(self: *Self) void {
        self.fonts.destroy();
        self.icon_cache.deinit();
        self.cache.deinit();
        self.arena.deinit();
        self.allocator.destroy(self);
    }

    /// Builds, lays out and paints `body(state)` for `options.frames` frames
    /// (at least one), as the window would: scroll views learn their extents,
    /// and the rows they show are built the frame after. Each frame publishes
    /// the theme and the image's size as the window's (`BuildScope`), and the
    /// size stays published afterwards. Keeps the last frame's draw commands.
    ///
    /// - `self`: the frame.
    /// - `state`: what `body` builds from, typically a pointer to the app's state.
    /// - `body`: builds the root view from `state`.
    /// - Returns: the last frame's commands, valid until the next `build` or
    ///   `destroy`; propagates allocation and painting failures.
    pub fn build(self: *Self, state: anytype, body: *const fn (@TypeOf(state)) mod.View) ![]const renderer.DrawCommand {
        const theme = self.options.theme;
        const width: f32 = @floatFromInt(self.options.width);
        const height: f32 = @floatFromInt(self.options.height);
        const full: renderer.Rect = .{ .x = 0, .y = 0, .width = width, .height = height };
        for (0..@max(self.options.frames, 1)) |_| {
            _ = self.arena.reset(.retain_capacity);
            const arena = self.arena.allocator();
            mod.BuildScope.shared().setTheme(theme);
            // The window's size, as the runtime publishes it (a title bar folds its menus by it).
            mod.BuildScope.shared().setViewport(width, height);
            mod.BuildScope.shared().begin(arena);
            const root = body(state);
            mod.BuildScope.shared().end();

            var hits: std.ArrayList(mod.HitRegion) = .empty;
            var overlays: std.ArrayList(mod.OverlayRequest) = .empty;
            var scrolls: std.ArrayList(mod.ScrollRegion) = .empty;
            var context = mod.Context.init(theme, &self.cache, arena, &hits);
            context.icon_cache = &self.icon_cache;
            context.overlays = &overlays;
            context.scroll_regions = &scrolls;
            context.fonts = self.fonts;

            var display_list = renderer.DisplayList.init(arena);
            try display_list.fillRect(full, theme.colors.window_background);
            try mod.ViewRenderer.render(&context, root, full, &display_list);
            self.commands = display_list.commands.items;
        }
        return self.commands;
    }

    /// Draws the last built frame's commands over the theme's window
    /// background with the software rasterizer.
    ///
    /// - `self`: the frame.
    /// - Returns: the image as RGBA8, rows top-down, owned by the caller;
    ///   propagates allocation and rasterizing failures.
    pub fn rasterize(self: *const Self) ![]u8 {
        var framebuffer = try renderer.Framebuffer.init(self.allocator, self.options.width, self.options.height);
        defer framebuffer.deinit();
        framebuffer.clear(self.options.theme.colors.window_background);
        try renderer.Rasterizer.init(self.allocator, &framebuffer).render(self.commands);
        return framebuffer.toRgba8Alloc(self.allocator);
    }

    /// Draws the last built frame's commands as `rasterize` does, into
    /// buffers the caller keeps across draws, as a window keeps its own, and
    /// with `pool`'s workers, as a window's software path draws; the bytes
    /// are the same as `rasterize`'s.
    ///
    /// - `self`: the frame.
    /// - `framebuffer`: the pixels drawn into, sized here when they differ.
    /// - `bytes`: receives the image as RGBA8, rows top-down; `width * height * 4` long.
    /// - `pool`: the workers, or null for the calling thread alone.
    /// - Returns: nothing; propagates allocation and rasterizing failures.
    pub fn rasterizeInto(self: *const Self, framebuffer: *renderer.Framebuffer, bytes: []u8, pool: ?*renderer.WorkerPool) !void {
        try framebuffer.ensureSize(self.allocator, self.options.width, self.options.height);
        try renderer.ParallelRasterizer.init(self.allocator, framebuffer, pool).drawFrame(self.options.theme.colors.window_background, self.commands, bytes);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

const Probe = struct {
    const Self = @This();

    builds: u32 = 0,

    /// Counts a build.
    ///
    /// - `self`: the probe.
    /// - Returns: a small red rectangle.
    fn body(self: *Self) mod.View {
        self.builds += 1;
        return mod.Rectangle(renderer.Color.red).frame(4, 2);
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "a frame builds every settling frame and keeps the last one's commands" {
    var probe: Probe = .{};
    const frame = try ScreenshotFrame.create(std.testing.allocator, .{ .width = 8, .height = 4, .theme = renderer.MacosTheme.light, .frames = 3 });
    defer frame.destroy();
    const commands = try frame.build(&probe, Probe.body);
    try std.testing.expectEqual(@as(u32, 3), probe.builds);
    try std.testing.expect(commands.len >= 2); // the background and the rectangle
    const rgba = try frame.rasterize();
    defer std.testing.allocator.free(rgba);
    try std.testing.expectEqual(@as(usize, 8 * 4 * 4), rgba.len);
}

test "rasterizeInto gives rasterize's bytes, with workers or without" {
    const allocator = std.testing.allocator;
    var probe: Probe = .{};
    const frame = try ScreenshotFrame.create(allocator, .{ .width = 40, .height = 90, .theme = renderer.MacosTheme.light });
    defer frame.destroy();
    _ = try frame.build(&probe, Probe.body);
    const expected = try frame.rasterize();
    defer allocator.free(expected);
    var framebuffer: renderer.Framebuffer = .empty;
    defer framebuffer.deinit();
    const bytes = try allocator.alloc(u8, expected.len);
    defer allocator.free(bytes);
    const pool = try renderer.WorkerPool.create(allocator, std.testing.io, 3);
    defer pool.destroy();
    for ([_]?*renderer.WorkerPool{ null, pool }) |maybe_pool| {
        @memset(bytes, 0);
        try frame.rasterizeInto(&framebuffer, bytes, maybe_pool);
        try std.testing.expectEqualSlices(u8, expected, bytes);
    }
}
