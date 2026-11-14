//! What a frame is laid out and painted with: the theme, glyph caches, the
//! frame arena, the inherited environment, and the sinks input regions,
//! overlays and the accessibility tree are collected into.

const std = @import("std");
const log = std.log.scoped(.ziggui_context);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// Where the input-region sinks stood before some clipped content painted
/// (see `Context.clipInput`).
pub const InputMarks = struct {
    const Self = @This();

    /// Tap regions.
    hits: usize,

    /// Hover regions.
    hovers: usize,

    /// Scroll regions.
    scrolls: usize,

    /// Popover passthrough frames.
    passthrough: usize,

    /// Modal passthrough frames.
    modal_passthrough: usize,

    /// Cuts the items of `list` from `from` on to `clip` (a `Rect`, or a region
    /// with a `rect`), dropping those wholly outside it.
    ///
    /// - `T`: the item type.
    /// - `list`: the sink.
    /// - `from`: the first item to cut.
    /// - `clip`: the clip.
    fn clipRegions(comptime T: type, list: *std.ArrayList(T), from: usize, clip: renderer.Rect) void {
        var kept = from;
        for (list.items[from..]) |region| {
            var cut = region;
            if (T == renderer.Rect) {
                cut = region.intersection(clip) orelse continue;
            } else {
                cut.rect = region.rect.intersection(clip) orelse continue;
            }
            list.items[kept] = cut;
            kept += 1;
        }
        list.shrinkRetainingCapacity(kept);
    }
};

/// The render context: the theme and caches a frame paints with, the
/// environment a subtree inherits, and the sinks painting fills.
pub const Context = struct {
    const Self = @This();

    /// The theme.
    theme: renderer.Theme,
    /// The text face's glyphs (the styled face once font modifiers apply).
    cache: *renderer.GlyphCache,
    /// The frame arena.
    arena: std.mem.Allocator,
    /// Where tap regions are collected.
    hit_regions: *std.ArrayList(mod.HitRegion),
    /// The inherited text and glyph color.
    foreground: renderer.Color,
    /// The color the view being painted asked for with its own `.foreground()`,
    /// or null (never inherited): a `.plain` button draws its label in it (a
    /// red "Delete…" with no fill).
    tint: ?renderer.Color = null,
    /// The inherited text size.
    font_size: f32,
    /// The inherited opacity.
    opacity: f32 = 1,
    /// The subtree is disabled.
    disabled: bool = false,
    /// Optional sink for overlay requests (sheets/alerts/popovers). When null,
    /// overlay modifiers are silently ignored — the 0-overlay fast path.
    overlays: ?*std.ArrayList(mod.OverlayRequest) = null,
    /// Optional sink for the accessibility tree.
    a11y: ?*std.ArrayList(mod.A11yNode) = null,
    /// Optional sink for scrollable regions. When set, `ScrollViewState`
    /// registers its viewport so the app can route wheel events with
    /// `PointerInput.scroll`.
    scroll_regions: ?*std.ArrayList(mod.ScrollRegion) = null,
    /// Optional sink for `onHover` regions. When set, each view with an
    /// `onHover` callback registers its frame so the app can route pointer
    /// motion with `PointerInput.hover`; when null, `onHover` is ignored.
    hover_regions: ?*std.ArrayList(mod.HoverRegion) = null,
    /// Frames of `popoverPassthrough` views, which popover dismiss regions
    /// leave out. `ViewRenderer.render` supplies a list when this is null.
    passthrough: ?*std.ArrayList(renderer.Rect) = null,
    /// Frames of `modalPassthrough` views, which sheet and alert dismiss
    /// regions leave out. `ViewRenderer.render` supplies a list when this is null.
    modal_passthrough: ?*std.ArrayList(renderer.Rect) = null,
    /// The on-screen part of the current scroll viewport (null = everything is
    /// visible). Views wholly outside it skip painting; see `ViewPainter.paint`.
    visible: ?renderer.Rect = null,
    /// Device-pixel scale used by `ViewRenderer.renderScaled` (1 = logical points == pixels).
    scale: f32 = 1,
    /// The cursor's current location in layout points, or null when the pointer
    /// is outside the window. Drives `Modifiers.hover_fill`. The app updates it
    /// on mouse-motion (and the main loop already redraws per event, so hover
    /// highlights track the cursor for free).
    hover_point: ?renderer.Point = null,
    /// Glyph cache for the bundled icon font (`Font.icons()`). When null, `Icon`
    /// and `IconButton` paint nothing — wire it (app + tests) to draw icons.
    icon_cache: ?*renderer.GlyphCache = null,
    /// Bundled faces; when set, weight/italic/mono pick the glyph cache (`cache`
    /// is then the primary-weight fallback used before any style applies).
    fonts: ?*renderer.FontSet = null,
    /// The inherited text weight.
    font_weight: renderer.FontWeight = .regular,
    /// The inherited italic.
    font_italic: bool = false,
    /// The inherited monospace.
    font_mono: bool = false,
    /// The cursor is inside the nearest enclosing `hoverScope`.
    in_hover_scope: bool = false,

    /// A context over a theme, a text cache, the frame arena and a tap sink.
    ///
    /// - `theme`: the theme.
    /// - `cache`: the text face's glyphs.
    /// - `arena`: the frame arena.
    /// - `hit_regions`: where tap regions are collected.
    /// - Returns: the context, with the theme's label color and body size.
    pub fn init(theme: renderer.Theme, cache: *renderer.GlyphCache, arena: std.mem.Allocator, hit_regions: *std.ArrayList(mod.HitRegion)) Self {
        const self = Self{
            .theme = theme,
            .cache = cache,
            .arena = arena,
            .hit_regions = hit_regions,
            .foreground = theme.colors.label,
            .font_size = theme.typography.body.size,
        };
        return self;
    }

    /// Like `init`, but also wires the overlay and accessibility sinks. Used by
    /// the app runtime; tests typically set the fields directly.
    ///
    /// - `theme`: the theme.
    /// - `cache`: the text face's glyphs.
    /// - `arena`: the frame arena.
    /// - `hit_regions`: where tap regions are collected.
    /// - `overlays`: where overlay requests are collected.
    /// - `a11y`: where accessibility nodes are collected.
    /// - Returns: the context.
    pub fn initFull(
        theme: renderer.Theme,
        cache: *renderer.GlyphCache,
        arena: std.mem.Allocator,
        hit_regions: *std.ArrayList(mod.HitRegion),
        overlays: ?*std.ArrayList(mod.OverlayRequest),
        a11y: ?*std.ArrayList(mod.A11yNode),
    ) Self {
        var self = Self.init(theme, cache, arena, hit_regions);
        self.overlays = overlays;
        self.a11y = a11y;
        return self;
    }

    /// A `Surface` for the theme's painter to draw chrome into — bundling the
    /// canvas with the active palette/metrics/scheme and the inherited
    /// opacity. The palette/metrics are borrowed from `self.theme`, valid for
    /// the duration of the painter call.
    ///
    /// - `self`: the context.
    /// - `canvas`: where the painter draws.
    /// - Returns: the surface.
    pub fn surface(self: *const Self, canvas: *renderer.Canvas) renderer.Surface {
        return .{
            .canvas = canvas,
            .palette = &self.theme.colors,
            .metrics = &self.theme.metrics,
            .scheme = self.theme.scheme,
            .opacity = self.opacity,
        };
    }

    /// The text size `view` is drawn at: its own size, its font token's, or
    /// the inherited one.
    ///
    /// - `self`: the context.
    /// - `view`: the view.
    /// - Returns: the size.
    pub fn resolvedFontSize(self: *const Self, view: mod.View) f32 {
        if (view.modifiers.size) |size| return size;
        if (view.modifiers.font) |token| return token.style(self.theme).size;
        return self.font_size;
    }

    /// Folds a view's font modifiers into the inherited context: size, weight,
    /// italic, mono — and picks the matching glyph cache so every measure/paint
    /// below uses the right face.
    ///
    /// - `self`: the context, changed in place.
    /// - `view`: the view.
    pub fn applyFontModifiers(self: *Self, view: mod.View) void {
        const modifiers = view.modifiers;
        if (modifiers.font) |token| {
            const style = token.style(self.theme);
            self.font_size = style.size;
            self.font_weight = style.weight;
        }
        if (modifiers.size) |size| self.font_size = size;
        if (modifiers.weight) |weight| self.font_weight = weight;
        if (modifiers.italic) self.font_italic = true;
        if (modifiers.mono) self.font_mono = true;
        if (self.fonts) |font_set| {
            if (modifiers.font != null or modifiers.size != null or modifiers.weight != null or modifiers.italic or modifiers.mono) {
                self.cache = font_set.cache(.{ .weight = self.font_weight, .italic = self.font_italic, .mono = self.font_mono });
            }
        }
    }

    /// The faces rich text is drawn in.
    ///
    /// - `self`: the context.
    /// - Returns: the bundled faces, the current face as the fallback.
    pub fn richFaces(self: *const Self) mod.RichFaces {
        return .{ .fonts = self.fonts, .fallback = self.cache.face, .base_weight = self.font_weight };
    }

    /// Draws text honoring the context scale: at scale 1 the normal path;
    /// otherwise the HiDPI path that rasterizes glyphs at device resolution (the
    /// command list is uniformly scaled afterward by `ViewRenderer.renderScaled`).
    ///
    /// - `self`: the context.
    /// - `canvas`: where it draws.
    /// - `text`: the line.
    /// - `pixel_size`: its size.
    /// - `color`: its color.
    /// - `origin`: its top-left.
    /// - Returns: nothing; propagates the text painter's failure.
    pub fn drawText(self: *const Self, canvas: *renderer.Canvas, text: []const u8, pixel_size: f32, color: renderer.Color, origin: renderer.Point) !void {
        if (self.scale == 1) {
            try renderer.TextPainter.shared().drawText(canvas, self.cache, text, pixel_size, color, origin);
        } else {
            try renderer.TextPainter.shared().drawTextScaled(canvas, self.cache, text, pixel_size, self.scale, color, origin);
        }
    }

    /// Appends an accessibility node for `view` (no-op when the a11y sink is
    /// off). The label defaults to `default_label` unless the view carries an
    /// explicit `.accessibilityLabel(...)` override.
    ///
    /// - `self`: the context.
    /// - `view`: the view.
    /// - `rect`: its frame.
    /// - `role`: what it is.
    /// - `default_label`: its label without an override.
    /// - `value`: its value.
    /// - Returns: nothing; propagates allocation failure.
    pub fn emitAccessibility(self: *const Self, view: mod.View, rect: renderer.Rect, role: mod.A11yRole, default_label: []const u8, value: []const u8) std.mem.Allocator.Error!void {
        const list = self.a11y orelse return;
        try list.append(self.arena, .{
            .rect = rect,
            .role = role,
            .label = view.modifiers.a11y_label orelse default_label,
            .value = value,
        });
    }

    /// Tail-truncates `string` to fit `max_width` at `pixel_size`, appending an
    /// ellipsis (returns `string` unchanged when it already fits). The clipped
    /// string is built in the frame arena. Used for `.truncated()` single-line Text.
    ///
    /// - `self`: the context.
    /// - `string`: the text.
    /// - `pixel_size`: its size.
    /// - `max_width`: the width it must fit.
    /// - Returns: the text, shortened when needed; propagates allocation failure.
    pub fn truncateToWidth(self: *const Self, string: []const u8, pixel_size: f32, max_width: f32) std.mem.Allocator.Error![]const u8 {
        // Layout hands a text exactly its measured width back, give or take float
        // rounding, so a tolerance keeps a string that fits from losing its tail.
        if (renderer.TextShaper.init(self.cache.face).measureLineWidth(string, pixel_size) <= max_width + 0.01) return string;
        const ellipsis = "…";
        const ellipsis_width = renderer.TextShaper.init(self.cache.face).measureLineWidth(ellipsis, pixel_size);
        if (max_width <= ellipsis_width) return ellipsis; // no room even for the body — just the ellipsis
        const budget = max_width - ellipsis_width;
        // Longest UTF-8 prefix (whole codepoints) whose width fits the budget.
        // Each step is one codepoint, so over valid UTF-8 adding its width to
        // the running sum repeats measureLineWidth's own additions, in order:
        // the same width a prefix measures to, in one pass instead of one per
        // prefix. A bad byte steps alone, as the caret does over it.
        var fit: usize = 0;
        var index: usize = 0;
        var width: f32 = 0;
        while (index < string.len) {
            const next = mod.TextLines.init(string).nextCodepointEnd(index);
            width += renderer.TextShaper.init(self.cache.face).measureLineWidth(string[index..next], pixel_size);
            if (width > budget) break;
            fit = next;
            index = next;
        }
        return self.arena.print("{s}{s}", .{ string[0..fit], ellipsis });
    }

    /// Where the input sinks stand now, before some clipped content paints.
    ///
    /// - `self`: the context.
    /// - Returns: the marks for `clipInput`.
    pub fn markInput(self: *const Self) InputMarks {
        return .{
            .hits = self.hit_regions.items.len,
            .hovers = if (self.hover_regions) |list| list.items.len else 0,
            .scrolls = if (self.scroll_regions) |list| list.items.len else 0,
            .passthrough = if (self.passthrough) |list| list.items.len else 0,
            .modal_passthrough = if (self.modal_passthrough) |list| list.items.len else 0,
        };
    }

    /// Cuts the tap, hover and scroll regions and passthrough frames content
    /// added since `marks` to `clip`, dropping those wholly outside it: what a
    /// clip hides takes no input either, so a row scrolled up under a toolbar
    /// cannot steal the toolbar's taps, nor keep a popover open through them.
    ///
    /// - `self`: the context.
    /// - `marks`: where the sinks stood before the content painted.
    /// - `clip`: the clip.
    pub fn clipInput(self: *const Self, marks: InputMarks, clip: renderer.Rect) void {
        InputMarks.clipRegions(mod.HitRegion, self.hit_regions, marks.hits, clip);
        if (self.hover_regions) |list| InputMarks.clipRegions(mod.HoverRegion, list, marks.hovers, clip);
        if (self.scroll_regions) |list| InputMarks.clipRegions(mod.ScrollRegion, list, marks.scrolls, clip);
        if (self.passthrough) |list| InputMarks.clipRegions(renderer.Rect, list, marks.passthrough, clip);
        if (self.modal_passthrough) |list| InputMarks.clipRegions(renderer.Rect, list, marks.modal_passthrough, clip);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "truncateToWidth cuts where measuring every prefix would" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const context = environment.context();
    const shaper = renderer.TextShaper.init(context.cache.face);
    // Mixed widths, multi-byte code points and a fallback glyph.
    const strings = [_][]const u8{ "The quick brown fox jumps over the lazy dog", "naïve café — señor Øresund ✓ 漢字", "WWWWiiiiWWWWiiii", "emoji 😀 and more 😀😀" };
    for (strings) |string| {
        const full = shaper.measureLineWidth(string, 13);
        var max_width: f32 = 0;
        while (max_width < full + 4) : (max_width += 0.37) {
            // The cut as it was found before: every prefix measured afresh.
            const ellipsis_width = shaper.measureLineWidth("…", 13);
            var fit: usize = 0;
            var index: usize = 0;
            while (index < string.len) {
                const next = @min(index + (std.unicode.utf8ByteSequenceLength(string[index]) catch 1), string.len);
                if (shaper.measureLineWidth(string[0..next], 13) > max_width - ellipsis_width) break;
                fit = next;
                index = next;
            }
            const out = try context.truncateToWidth(string, 13, max_width);
            if (full <= max_width + 0.01) {
                try std.testing.expectEqualStrings(string, out);
            } else if (max_width <= ellipsis_width) {
                try std.testing.expectEqualStrings("…", out);
            } else {
                try std.testing.expectEqualStrings(string[0..fit], out[0 .. out.len - "…".len]);
            }
        }
    }
}

test "truncateToWidth steps over bad UTF-8 a byte at a time" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const context = environment.context();
    const shaper = renderer.TextShaper.init(context.cache.face);
    // A stray continuation byte, a lead byte cut short at the end, and a lead
    // byte before plain letters (which must not be swallowed with it).
    const strings = [_][]const u8{ "x\x80y\xc3", "\xe2\x80", "\xe2abcdefgh" };
    for (strings) |string| {
        const full = shaper.measureLineWidth(string, 13);
        var max_width: f32 = 0;
        while (max_width < full + 4) : (max_width += 0.37) {
            const out = try context.truncateToWidth(string, 13, max_width);
            if (std.mem.eql(u8, out, string) or std.mem.eql(u8, out, "…")) continue;
            // The body is a prefix cut at a step boundary.
            const body = out[0 .. out.len - "…".len];
            try std.testing.expect(std.mem.startsWith(u8, string, body));
            var boundary: usize = 0;
            while (boundary < body.len) boundary = mod.TextLines.init(string).nextCodepointEnd(boundary);
            try std.testing.expectEqual(body.len, boundary);
        }
    }
    // The lead byte steps alone, so the letters after it are kept as they fit.
    const ellipsis_width = shaper.measureLineWidth("…", 13);
    const cut = try context.truncateToWidth("\xe2abcdefgh", 13, ellipsis_width + shaper.measureLineWidth("\xe2", 13) + shaper.measureLineWidth("a", 13) + 0.01);
    try std.testing.expectEqualStrings("\xe2a…", cut);
}
