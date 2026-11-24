//! The set of bundled faces (Inter weights + italic, JetBrains Mono) with one
//! glyph cache each, and a cache per registered face it has drawn. `Context.fonts`
//! points at one; a view's family, weight, italic and mono select the cache
//! every text measure and paint then uses.

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
    const count = @typeInfo(Self).@"enum".field_names.len;

    /// The slot a style draws with.
    ///
    /// - `style`: the weight, italic and mono asked for.
    /// - Returns: the slot.
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

/// A registered face as one set draws it: its own copy of the face (so the
/// set's fallback chain applies: the bundled face of the same style, then
/// emoji) and a glyph cache, heap-allocated so the cache's face pointer stays put.
const RegisteredCache = struct {
    const Self = @This();

    /// The registry's face it copies, its key.
    source: *const mod.TtfFont,

    /// The style it was made for, which picks its bundled fallback.
    style: mod.FontStyle,

    /// The copy, its fallback the set's bundled face of the same style.
    face: mod.TtfFont,

    /// The glyph cache over `face`.
    cache: mod.GlyphCache,
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
    /// A cache per registered face drawn so far.
    registered: std.ArrayList(*RegisteredCache),
    /// The last family name `familyCache` did not find, so it warns once.
    missing: [64]u8,
    /// How many of `missing`'s bytes are the name.
    missing_length: usize,

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
        self.registered = .empty;
        self.missing_length = 0;
        return self;
    }

    /// Free the caches and the set.
    ///
    /// - `self`: the set.
    pub fn destroy(self: *Self) void {
        for (&self.caches) |*cache_entry| cache_entry.deinit();
        for (self.registered.items) |entry| {
            entry.cache.deinit();
            self.allocator.destroy(entry);
        }
        self.registered.deinit(self.allocator);
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

    /// The glyph cache a family draws a style with: the bundled faces for
    /// `FontRegistry.bundled_sans` and `bundled_mono`, else the registered
    /// family's face (a cache made on first use). A name not registered
    /// draws in the bundled faces, and is logged once.
    ///
    /// - `self`: the set.
    /// - `name`: the family's name.
    /// - `style`: the weight, italic and mono asked for.
    /// - Returns: the cache.
    pub fn familyCache(self: *Self, name: []const u8, style: mod.FontStyle) *mod.GlyphCache {
        if (std.mem.eql(u8, name, mod.FontRegistry.bundled_sans)) return self.cache(.{ .weight = style.weight, .italic = style.italic });
        if (std.mem.eql(u8, name, mod.FontRegistry.bundled_mono)) return self.cache(.{ .weight = style.weight, .mono = true });
        const source = mod.FontRegistry.shared().face(name, style) orelse {
            if (!std.mem.eql(u8, self.missing[0..self.missing_length], name)) {
                log.warn("no font family named \"{s}\"; drawing in the bundled faces", .{name});
                self.missing_length = @min(name.len, self.missing.len);
                @memcpy(self.missing[0..self.missing_length], name[0..self.missing_length]);
            }
            return self.cache(style);
        };
        // Keyed by face and style: a family lacking bold draws bold text in
        // its regular face, falling back to the bundled bold.
        const fallback_slot = Slot.forStyle(.{ .weight = style.weight, .italic = style.italic });
        for (self.registered.items) |entry| {
            if (entry.source == source and Slot.forStyle(.{ .weight = entry.style.weight, .italic = entry.style.italic }) == fallback_slot) return &entry.cache;
        }
        const entry = self.allocator.create(RegisteredCache) catch |err| {
            log.warn("no cache for \"{s}\": {s}", .{ name, @errorName(err) });
            return self.cache(style);
        };
        self.registered.append(self.allocator, entry) catch |err| {
            log.warn("no cache for \"{s}\": {s}", .{ name, @errorName(err) });
            self.allocator.destroy(entry);
            return self.cache(style);
        };
        entry.* = .{ .source = source, .style = style, .face = source.*, .cache = undefined };
        // Codepoints the family lacks (⌘, arrows) come from the bundled face, then emoji.
        entry.face.fallback = &self.faces[@backingInt(fallback_slot)];
        entry.cache = mod.GlyphCache.init(self.allocator, &entry.face);
        return &entry.cache;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// An external face that has only U+4E2D.
const FakeCjk = struct {
    const Self = @This();

    /// The glyph for `codepoint`: U+4E2D only.
    ///
    /// - `codepoint`: the codepoint.
    /// - Returns: its glyph index, 0 when missing.
    fn glyph(_: *const anyopaque, codepoint: u21) u16 {
        return if (codepoint == 0x4E2D) 3 else 0;
    }

    /// Every glyph's advance.
    ///
    /// - Returns: the advance, in font units.
    fn advance(_: *const anyopaque, _: u16) u16 {
        return 1000;
    }

    /// An empty glyph image.
    ///
    /// - Returns: the raster; never fails.
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

test "a font set draws a registered family in its own cache, and the bundled names in its slots" {
    const allocator = std.testing.allocator;
    const font_set = try FontSet.create(allocator);
    defer font_set.destroy();
    defer mod.FontRegistry.shared().reset();
    try mod.FontRegistry.shared().register(allocator, .{ .name = "Copy", .regular = mod.TtfFont.inter_ttf });
    const registered = font_set.familyCache("Copy", .{});
    try std.testing.expect(registered != font_set.cache(.{}));
    try std.testing.expect(font_set.familyCache("Copy", .{}) == registered);
    try std.testing.expect(registered.face.fallback == &font_set.faces[@backingInt(Slot.regular)]);
    // No bold in the family: bold text draws its regular face, falling back to the bundled bold.
    const bold = font_set.familyCache("Copy", .{ .weight = .bold });
    try std.testing.expect(bold.face.fallback == &font_set.faces[@backingInt(Slot.bold)]);
    try std.testing.expect(font_set.familyCache(mod.FontRegistry.bundled_mono, .{}) == font_set.cache(.{ .mono = true }));
    try std.testing.expect(font_set.familyCache(mod.FontRegistry.bundled_sans, .{ .mono = true }) == font_set.cache(.{}));
    try std.testing.expect(font_set.familyCache("Unknown", .{}) == font_set.cache(.{}));
}
