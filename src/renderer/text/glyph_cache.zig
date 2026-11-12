//! Glyph cache. Rasterizing a glyph outline is relatively expensive, so the
//! `GlyphCache` memoizes `RasterGlyph` coverage bitmaps keyed by (glyph index,
//! pixel size). The GPU backend will additionally pack these into a texture
//! atlas; for the software rasterizer and tests, the cached coverage bitmaps are
//! consumed directly. The cache owns the bitmaps and frees them on `deinit`.

const std = @import("std");
const log = std.log.scoped(.ziggui_glyph_cache);
const mod = @import("module.zig");

/// A cache key. Glyph indices are per-face, so the face is part of the key:
/// one cache can hold glyphs from the primary face and any fallback (emoji)
/// faces.
const GlyphKey = struct {
    const Self = @This();

    /// The face's address.
    face: usize,
    /// The glyph index within the face.
    glyph: u16,
    /// The pixel size in thousandths.
    size_milli: u32,
};

/// Rasterized glyphs of a face (and its fallbacks), by glyph and pixel size.
pub const GlyphCache = struct {
    const Self = @This();

    /// Primary face — the default for `get` and what metrics callers read.
    face: *const mod.TtfFont,
    /// The cached bitmaps.
    map: std.AutoHashMapUnmanaged(GlyphKey, mod.RasterGlyph) = .empty,
    /// The allocator the bitmaps and map grow with.
    allocator: std.mem.Allocator,

    /// The largest pixel size the cache rasterizes at (its key holds
    /// thousandths in a u32).
    const max_pixel_size: f32 = 1_000_000;
    /// What `getFace` returns for a pixel size it does not rasterize at.
    const empty_glyph = mod.RasterGlyph{ .width = 0, .height = 0, .data = &.{}, .left = 0, .top = 0, .advance = 0 };

    /// An empty cache over `face`.
    ///
    /// - `allocator`: allocator for the bitmaps and map.
    /// - `face`: the primary face; it must outlive the cache.
    /// - Returns: the cache.
    pub fn init(allocator: std.mem.Allocator, face: *const mod.TtfFont) Self {
        const self = Self{ .face = face, .allocator = allocator };
        return self;
    }

    /// Free every bitmap and the map.
    ///
    /// - `self`: the cache.
    pub fn deinit(self: *Self) void {
        var iterator = self.map.valueIterator();
        while (iterator.next()) |glyph| glyph.deinit(self.allocator);
        self.map.deinit(self.allocator);
    }

    /// Get (rasterizing & caching on miss) the coverage bitmap for a glyph of
    /// the primary face at a pixel size. The returned pointer is valid until the
    /// cache is mutated for the same size class or deinited.
    ///
    /// - `self`: the cache.
    /// - `glyph`: the glyph index.
    /// - `pixel_size`: the em size in pixels.
    /// - Returns: the bitmap; propagates allocation failure.
    pub fn get(self: *Self, glyph: u16, pixel_size: f32) !*const mod.RasterGlyph {
        return self.getFace(self.face, glyph, pixel_size);
    }

    /// Like `get`, but for a glyph of an arbitrary `face` (e.g. a fallback emoji
    /// face returned by `TtfFont.resolve`). Rasterizes at that face's own scale.
    /// A pixel size that is not positive (or NaN, or past a million) yields an
    /// empty glyph, uncached.
    ///
    /// - `self`: the cache.
    /// - `face`: the face the glyph belongs to.
    /// - `glyph`: the glyph index.
    /// - `pixel_size`: the em size in pixels.
    /// - Returns: the bitmap; propagates allocation failure.
    pub fn getFace(self: *Self, face: *const mod.TtfFont, glyph: u16, pixel_size: f32) !*const mod.RasterGlyph {
        if (!(pixel_size > 0) or !(pixel_size <= max_pixel_size)) return &empty_glyph;
        const key = GlyphKey{
            .face = @intFromPtr(face),
            .glyph = glyph,
            .size_milli = @intFromFloat(@round(pixel_size * 1000)),
        };
        const entry = try self.map.getOrPut(self.allocator, key);
        if (!entry.found_existing) {
            // A failed rasterize must not leave an undefined glyph cached.
            errdefer self.map.removeByPtr(entry.key_ptr);
            const scale = face.scaleForPixelSize(pixel_size);
            entry.value_ptr.* = try face.rasterizeGlyph(self.allocator, glyph, scale);
        }
        return entry.value_ptr;
    }

    /// How many bitmaps the cache holds.
    ///
    /// - `self`: the cache.
    /// - Returns: the count.
    pub fn count(self: *const Self) usize {
        return self.map.count();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "GlyphCache: caches rasterized glyphs (one entry per glyph+size)" {
    var face = try mod.TtfFont.parse(mod.TtfFont.inter_ttf);
    var cache = GlyphCache.init(std.testing.allocator, &face);
    defer cache.deinit();

    const letter = face.glyphIndex('A');
    const first = try cache.get(letter, 32);
    const second = try cache.get(letter, 32); // cache hit -> same pointer
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(@as(usize, 1), cache.count());

    _ = try cache.get(letter, 48); // different size -> new entry
    _ = try cache.get(face.glyphIndex('B'), 32); // different glyph -> new entry
    try std.testing.expectEqual(@as(usize, 3), cache.count());

    try std.testing.expect(first.width > 0 and first.height > 0);
}

test "GlyphCache: a failed rasterize caches nothing, and the next get rasterizes" {
    var face = try mod.TtfFont.parse(mod.TtfFont.inter_ttf);
    // Allocation 0 grows the map; allocation 1 (the rasterizer's first) fails.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var cache = GlyphCache.init(failing.allocator(), &face);
    defer cache.deinit();
    const letter = face.glyphIndex('A');
    try std.testing.expectError(error.OutOfMemory, cache.get(letter, 14));
    try std.testing.expectEqual(@as(usize, 0), cache.count());

    failing.fail_index = std.math.maxInt(usize);
    const glyph = try cache.get(letter, 14);
    try std.testing.expect(glyph.width > 0 and glyph.data.len == @as(usize, glyph.width) * glyph.height);
    try std.testing.expectEqual(@as(usize, 1), cache.count());
}

test "GlyphCache: a pixel size that is not positive and finite yields an empty glyph" {
    var face = try mod.TtfFont.parse(mod.TtfFont.inter_ttf);
    var cache = GlyphCache.init(std.testing.allocator, &face);
    defer cache.deinit();
    for ([_]f32{ 0, -4, std.math.nan(f32), std.math.inf(f32), -std.math.inf(f32), 5e9 }) |pixel_size| {
        const glyph = try cache.get(face.glyphIndex('A'), pixel_size);
        try std.testing.expectEqual(@as(u32, 0), glyph.width);
    }
    try std.testing.expectEqual(@as(usize, 0), cache.count());
}
