//! The set of bundled faces (Inter weights + italic, JetBrains Mono) with one
//! glyph cache each. `Context.fonts` points at one; a view's weight/italic/mono
//! selects the cache every text measure and paint then uses.

const std = @import("std");
const log = std.log.scoped(.ziggui_font_set);
const mod = @import("module.zig");

/// One bundled face of the set.
const Slot = enum {
    const Self = @This();

    regular,
    medium,
    semibold,
    bold,
    italic,
    boldItalic,
    mono,
    monoBold,
    emoji,

    /// How many slots there are.
    const count = std.meta.fieldNames(Self).len;

    /// The slot a style draws with.
    fn forStyle(style: mod.FontStyle) Self {
        const heavy = switch (style.weight) {
            .semibold, .bold, .heavy, .black => true,
            else => false,
        };
        if (style.mono) return if (heavy) .monoBold else .mono;
        if (style.italic) return if (heavy) .boldItalic else .italic;
        return switch (style.weight) {
            .ultraLight, .thin, .light, .regular => .regular,
            .medium => .medium,
            .semibold => .semibold,
            .bold, .heavy, .black => .bold,
        };
    }
};

/// The bundled faces and a glyph cache for each.
pub const FontSet = struct {
    const Self = @This();

    /// The allocator the set and its caches came from.
    allocator: std.mem.Allocator,
    /// The faces, by `Slot`.
    faces: [Slot.count]mod.TtfFont,
    /// One glyph cache per face.
    caches: [Slot.count]mod.GlyphCache,

    /// The font blobs, by `Slot`.
    const blobs = [Slot.count][]const u8{
        mod.TtfFont.inter_ttf,
        @embedFile("inter_medium"),
        @embedFile("inter_semibold"),
        @embedFile("inter_bold"),
        @embedFile("inter_italic"),
        @embedFile("inter_bold_italic"),
        @embedFile("mono_regular"),
        @embedFile("mono_bold"),
        mod.TtfFont.emoji_ttf,
    };

    /// Parse every bundled face. Heap-allocated so the face/cache pointers stay
    /// stable.
    ///
    /// - `allocator`: allocator for the set and its caches.
    /// - Returns: the set; propagates allocation and parse failure.
    pub fn create(allocator: std.mem.Allocator) !*Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = try allocator.create(Self);
        self.allocator = allocator;
        for (Self.blobs, 0..) |blob, index| self.faces[index] = try mod.TtfFont.parse(blob);
        // Text faces fall back to the emoji font for codepoints they lack.
        const emoji = &self.faces[@backingInt(Slot.emoji)];
        for (0..Slot.count - 1) |index| self.faces[index].fallback = emoji;
        for (0..Slot.count) |index| self.caches[index] = mod.GlyphCache.init(allocator, &self.faces[index]);
        return self;
    }

    /// Free the caches and the set.
    ///
    /// - `self`: the set.
    pub fn destroy(self: *Self) void {
        for (&self.caches) |*cache_entry| cache_entry.deinit();
        self.allocator.destroy(self);
    }

    /// Put `face` (e.g. a system CJK font) behind the emoji face, so every style
    /// reaches it for codepoints the bundled faces lack. It must outlive the set.
    ///
    /// - `self`: the set.
    /// - `face`: the fallback face.
    pub fn setFallback(self: *Self, face: *const mod.TtfFont) void {
        self.faces[@backingInt(Slot.emoji)].fallback = face;
    }

    /// The glyph cache a style draws with.
    ///
    /// - `self`: the set.
    /// - `style`: the style.
    /// - Returns: the cache.
    pub fn cache(self: *Self, style: mod.FontStyle) *mod.GlyphCache {
        return &self.caches[@backingInt(Slot.forStyle(style))];
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// An external face that has only U+4E2D.
const FakeCjk = struct {
    const Self = @This();

    fn glyph(_: *const anyopaque, codepoint: u21) u16 {
        return if (codepoint == 0x4E2D) 3 else 0;
    }

    fn advance(_: *const anyopaque, _: u16) u16 {
        return 1000;
    }

    fn raster(_: *const anyopaque, _: std.mem.Allocator, _: u16, _: f32) std.mem.Allocator.Error!mod.RasterGlyph {
        return .{ .width = 0, .height = 0, .data = &.{}, .left = 0, .top = 0, .advance = 0 };
    }

    const external = mod.ExternalFace{ .context = undefined, .glyph_index = FakeCjk.glyph, .advance_width = FakeCjk.advance, .rasterize = FakeCjk.raster };
};

test {
    std.testing.refAllDecls(@This());
}

test "fontset: every bundled face parses and resolves ASCII" {
    const fonts = try FontSet.create(std.testing.allocator);
    defer fonts.destroy();
    for (fonts.faces[0 .. Slot.count - 1]) |face| try std.testing.expect(face.glyphIndex('A') != 0);
}

test "fontset: an attached fallback face serves every style for codepoints the bundled faces lack" {
    const fonts = try FontSet.create(std.testing.allocator);
    defer fonts.destroy();
    const cjk = mod.TtfFont.fromExternal(&FakeCjk.external, 1000, 880, -120, 0);
    fonts.setFallback(&cjk);
    for ([_]mod.FontStyle{ .{}, .{ .weight = .bold }, .{ .italic = true }, .{ .mono = true } }) |style| {
        try std.testing.expect(fonts.cache(style).face.resolve(0x4E2D).face == &cjk);
    }
}

test "fontset: style to slot mapping" {
    try std.testing.expectEqual(Slot.regular, Slot.forStyle(.{}));
    try std.testing.expectEqual(Slot.semibold, Slot.forStyle(.{ .weight = .semibold }));
    try std.testing.expectEqual(Slot.bold, Slot.forStyle(.{ .weight = .heavy }));
    try std.testing.expectEqual(Slot.italic, Slot.forStyle(.{ .italic = true }));
    try std.testing.expectEqual(Slot.boldItalic, Slot.forStyle(.{ .weight = .bold, .italic = true }));
    try std.testing.expectEqual(Slot.monoBold, Slot.forStyle(.{ .weight = .bold, .mono = true }));
}
