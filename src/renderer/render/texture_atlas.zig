//! The GPU scene's texture atlas, CPU-side bookkeeping.

const std = @import("std");
const log = std.log.scoped(.ziggui_texture_atlas);
const mod = @import("module.zig");

/// What an atlas entry is keyed by: its stable source pointer and size.
const AtlasKey = struct {
    const Self = @This();

    /// The source pixels' address.
    pointer: usize,
    /// The entry's width.
    width: u32,
    /// The entry's height.
    height: u32,
};

/// Where an entry sits in the atlas.
const AtlasEntry = struct {
    const Self = @This();

    /// The entry's left edge.
    x: u32,
    /// The entry's top edge.
    y: u32,
    /// The entry's width.
    width: u32,
    /// The entry's height.
    height: u32,
};

/// One shelf of the shelf packer: a row of entries.
const AtlasShelf = struct {
    const Self = @This();

    /// The shelf's top edge.
    y: u32,
    /// The shelf's height (its tallest entry, padded).
    height: u32,
    /// Where the next entry on the shelf goes.
    x: u32,
};

/// Shelf-packed RGBA8 atlas bookkeeping. Glyph coverage bitmaps and images are
/// packed side by side; entries are keyed by their stable source pointer (the
/// `GlyphCache` owns glyph bitmaps for the app's lifetime, so a pointer key is
/// a content key). The GPU backend mirrors this state into a real texture by
/// applying `pendingUploads` each frame.
pub const TextureAtlas = struct {
    const Self = @This();

    /// 1px transparent border around every entry so linear/nearest sampling at
    /// the edge never bleeds a neighbour.
    pub const padding = 1;
    /// The largest the atlas grows to, per side.
    pub const max_size = 8192;

    /// The atlas's side, in pixels.
    size: u32,
    /// The allocator the bookkeeping grows with.
    allocator: std.mem.Allocator,
    /// The shelves packed so far, top-down.
    shelves: std.ArrayList(AtlasShelf) = .empty,
    /// Every packed entry, by key.
    map: std.AutoHashMapUnmanaged(AtlasKey, AtlasEntry) = .empty,
    /// The uploads staged since `clearPending`.
    pending: std.ArrayList(mod.AtlasUpload) = .empty,
    /// Bumped every `reset`/`grow`; the GPU backend recreates its texture when
    /// the generation it last uploaded doesn't match.
    generation: u32 = 0,

    /// An empty atlas of the given side.
    ///
    /// - `allocator`: allocator for the bookkeeping.
    /// - `size`: the atlas's side, in pixels.
    /// - Returns: the atlas.
    pub fn init(allocator: std.mem.Allocator, size: u32) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .size = size, .allocator = allocator };
        return self;
    }

    /// Free the bookkeeping.
    ///
    /// - `self`: the atlas.
    pub fn deinit(self: *Self) void {
        self.shelves.deinit(self.allocator);
        self.map.deinit(self.allocator);
        self.pending.deinit(self.allocator);
    }

    /// Drop every packed entry (the texture is stale) and double the size, up
    /// to `max_size`. The caller can still `reset()` to evict entries from
    /// earlier frames when this fails.
    ///
    /// - `self`: the atlas.
    /// - Returns: false when already at the maximum.
    pub fn grow(self: *Self) bool {
        if (self.size >= max_size) return false;
        self.size = @min(self.size * 2, max_size);
        self.reset();
        return true;
    }

    /// Evict everything (entries re-pack lazily as they are next referenced).
    ///
    /// - `self`: the atlas.
    pub fn reset(self: *Self) void {
        self.shelves.clearRetainingCapacity();
        self.map.clearRetainingCapacity();
        self.pending.clearRetainingCapacity();
        self.generation +%= 1;
    }

    /// The uploads staged since `clearPending`. Pixel slices are arena-owned;
    /// the GPU backend must consume them (then `clearPending`) within the frame.
    ///
    /// - `self`: the atlas.
    /// - Returns: the uploads.
    pub fn pendingUploads(self: *const Self) []const mod.AtlasUpload {
        return self.pending.items;
    }

    /// Forget the staged uploads once the GPU backend has applied them.
    ///
    /// - `self`: the atlas.
    pub fn clearPending(self: *Self) void {
        self.pending.clearRetainingCapacity();
    }

    /// The UV rect of the entry keyed by `pointer`, when it is already packed;
    /// lets a caller skip building the pixels `place` would stage on a miss.
    ///
    /// - `self`: the atlas.
    /// - `pointer`: the source pixels' stable address.
    /// - `width`: the entry's width.
    /// - `height`: the entry's height.
    /// - Returns: the normalized UV rect, or null when the entry is not packed.
    pub fn lookup(self: *const Self, pointer: usize, width: u32, height: u32) ?[4]f32 {
        const entry = self.map.get(.{ .pointer = pointer, .width = width, .height = height }) orelse return null;
        return self.uvRect(entry);
    }

    /// Pack (or find) an entry keyed by `pointer`, staging `rgba` for upload on
    /// a miss.
    ///
    /// - `self`: the atlas.
    /// - `pointer`: the source pixels' stable address.
    /// - `width`: the entry's width.
    /// - `height`: the entry's height.
    /// - `rgba`: the entry's RGBA8 pixels.
    /// - Returns: the normalized UV rect; `error.AtlasFull` when it does not
    ///   fit; propagates allocation failure.
    pub fn place(self: *Self, pointer: usize, width: u32, height: u32, rgba: []const u8) error{ OutOfMemory, AtlasFull }![4]f32 {
        const key = AtlasKey{ .pointer = pointer, .width = width, .height = height };
        const slot = try self.map.getOrPut(self.allocator, key);
        if (!slot.found_existing) {
            slot.value_ptr.* = self.pack(width, height) catch |err| {
                _ = self.map.remove(key);
                return err;
            };
            try self.pending.append(self.allocator, .{
                .x = slot.value_ptr.x,
                .y = slot.value_ptr.y,
                .width = width,
                .height = height,
                .pixels = rgba,
            });
        }
        return self.uvRect(slot.value_ptr.*);
    }

    /// An entry's place as a normalized UV rect (left, top, right, bottom).
    ///
    /// - `self`: the atlas.
    /// - `entry`: the entry.
    /// - Returns: the UV rect.
    fn uvRect(self: *const Self, entry: AtlasEntry) [4]f32 {
        const side: f32 = @floatFromInt(self.size);
        return .{
            @as(f32, @floatFromInt(entry.x)) / side,
            @as(f32, @floatFromInt(entry.y)) / side,
            @as(f32, @floatFromInt(entry.x + entry.width)) / side,
            @as(f32, @floatFromInt(entry.y + entry.height)) / side,
        };
    }

    /// Find room for a `width` × `height` entry on a shelf, opening a new
    /// shelf when none has room.
    ///
    /// - `self`: the atlas.
    /// - `width`: the entry's width.
    /// - `height`: the entry's height.
    /// - Returns: the entry's place; `error.AtlasFull` when it does not fit;
    ///   propagates allocation failure.
    fn pack(self: *Self, width: u32, height: u32) error{ OutOfMemory, AtlasFull }!AtlasEntry {
        const padded_width = width + 2 * padding;
        const padded_height = height + 2 * padding;
        if (padded_width > self.size or padded_height > self.size) return error.AtlasFull;
        for (self.shelves.items) |*shelf| {
            if (padded_height <= shelf.height and shelf.x + padded_width <= self.size) {
                const entry = AtlasEntry{ .x = shelf.x + padding, .y = shelf.y + padding, .width = width, .height = height };
                shelf.x += padded_width;
                return entry;
            }
        }
        const top = if (self.shelves.items.len > 0) blk: {
            const last = self.shelves.items[self.shelves.items.len - 1];
            break :blk last.y + last.height;
        } else 0;
        if (top + padded_height > self.size) return error.AtlasFull;
        try self.shelves.append(self.allocator, .{ .y = top, .height = padded_height, .x = padded_width });
        return .{ .x = padding, .y = top + padding, .width = width, .height = height };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "gpu_scene: shelf packer separates entries with padding" {
    var atlas = mod.TextureAtlas.init(std.testing.allocator, 32);
    defer atlas.deinit();
    const pixels: [64]u8 = @splat(0);
    const first = try atlas.place(1, 4, 4, &pixels);
    const second = try atlas.place(2, 4, 4, &pixels);
    try std.testing.expect(first[0] != second[0] or first[1] != second[1]); // distinct slots
    // entries are 1px-padded: second entry starts at x = 1 + (4 + 2*1)
    const pending = atlas.pendingUploads();
    try std.testing.expectEqual(@as(u32, 1), pending[0].x);
    try std.testing.expectEqual(@as(u32, 7), pending[1].x);
}

test "texture_atlas: lookup finds a placed entry's UVs and misses an unplaced one" {
    var atlas = mod.TextureAtlas.init(std.testing.allocator, 32);
    defer atlas.deinit();
    const pixels: [64]u8 = @splat(0);
    try std.testing.expectEqual(@as(?[4]f32, null), atlas.lookup(1, 4, 4));
    const placed = try atlas.place(1, 4, 4, &pixels);
    try std.testing.expectEqual(@as(?[4]f32, placed), atlas.lookup(1, 4, 4));
    try std.testing.expectEqual(@as(?[4]f32, null), atlas.lookup(1, 4, 5)); // the size is part of the key
}
