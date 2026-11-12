//! A headless frame for the view engine's unit tests (a barrel test fixture).

const std = @import("std");
const log = std.log.scoped(.ziggui_test_environment);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Fonts, glyph caches, a tap sink and a build arena for one test: `init`,
/// then `setup` (which opens the build), `context` for each frame, `deinit`.
pub const TestEnvironment = struct {
    const Self = @This();

    /// The text face.
    font: renderer.Font,
    /// The icon face.
    icon_font: renderer.Font,
    /// Glyphs of `font`.
    cache: renderer.GlyphCache,
    /// Glyphs of `icon_font`.
    icon_cache: renderer.GlyphCache,
    /// The tap regions frames register.
    hits: std.ArrayList(mod.HitRegion),
    /// The build and frame arena.
    arena_state: std.heap.ArenaAllocator,

    /// A fixture whose caches are not set up yet (they point into it: call
    /// `setup` once it is in place).
    ///
    /// - Returns: the fixture.
    pub fn init() Self {
        const self = Self{
            .font = renderer.Font.default(),
            .icon_font = renderer.Font.icons(),
            .cache = undefined,
            .icon_cache = undefined,
            .hits = .empty,
            .arena_state = std.heap.ArenaAllocator.init(std.testing.allocator),
        };
        return self;
    }

    /// Builds the glyph caches and opens the build arena.
    ///
    /// - `self`: the fixture, at its final address.
    pub fn setup(self: *Self) void {
        self.cache = renderer.GlyphCache.init(std.testing.allocator, &self.font.face);
        self.icon_cache = renderer.GlyphCache.init(std.testing.allocator, &self.icon_font.face);
        mod.BuildScope.shared().begin(self.arena_state.allocator());
    }

    /// Closes the build arena and frees the caches and the arena.
    ///
    /// - `self`: the fixture.
    pub fn deinit(self: *Self) void {
        mod.BuildScope.shared().end();
        self.cache.deinit();
        self.icon_cache.deinit();
        // hit regions are appended via the arena, freed by arena_state.deinit()
        self.arena_state.deinit();
    }

    /// A macOS light context over the fixture's caches, arena and tap sink.
    ///
    /// - `self`: the fixture.
    /// - Returns: the context.
    pub fn context(self: *Self) mod.Context {
        var result = mod.Context.init(renderer.MacosTheme.light, &self.cache, self.arena_state.allocator(), &self.hits);
        result.icon_cache = &self.icon_cache;
        return result;
    }

    /// Renders `tree` into `rect` and rasterizes it into a white framebuffer.
    ///
    /// - `self`: the fixture.
    /// - `frame_context`: the context to render with.
    /// - `tree`: the view.
    /// - `rect`: where it is laid out.
    /// - `width`: the framebuffer's width.
    /// - `height`: the framebuffer's height.
    /// - Returns: the framebuffer, owned by the caller; propagates failure.
    pub fn renderToFramebuffer(self: *Self, frame_context: *mod.Context, tree: mod.View, rect: renderer.Rect, width: u32, height: u32) !renderer.Framebuffer {
        _ = self;
        var canvas = renderer.Canvas.init(std.testing.allocator);
        defer canvas.deinit();
        try mod.ViewRenderer.render(frame_context, tree, rect, &canvas);
        var framebuffer = try renderer.Framebuffer.init(std.testing.allocator, width, height);
        framebuffer.clear(renderer.Color.white);
        try renderer.Rasterizer.init(std.testing.allocator, &framebuffer).render(canvas.commands.items);
        return framebuffer;
    }

    /// The pixels that read as blue.
    ///
    /// - `framebuffer`: the pixels.
    /// - Returns: how many.
    pub fn countBlue(framebuffer: *const renderer.Framebuffer) u32 {
        var count: u32 = 0;
        for (framebuffer.pixels) |pixel| {
            if (pixel.b > pixel.r + 0.2 and pixel.b > 0.4) count += 1;
        }
        return count;
    }

    /// The pixels that read as red.
    ///
    /// - `framebuffer`: the pixels.
    /// - Returns: how many.
    pub fn countRed(framebuffer: *const renderer.Framebuffer) u32 {
        var count: u32 = 0;
        for (framebuffer.pixels) |pixel| {
            if (pixel.r > pixel.b + 0.2 and pixel.r > 0.4) count += 1;
        }
        return count;
    }

    /// The pixels darker than mid-grey.
    ///
    /// - `framebuffer`: the pixels.
    /// - Returns: how many.
    pub fn countDark(framebuffer: *const renderer.Framebuffer) u32 {
        var count: u32 = 0;
        for (framebuffer.pixels) |pixel| {
            if (pixel.luminance() < 0.5) count += 1;
        }
        return count;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}
