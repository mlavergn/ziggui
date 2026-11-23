//! How an image's rows split into bands: small enough to stay in a core's
//! cache while it is worked on, and enough of them to keep every worker busy.

const std = @import("std");
const log = std.log.scoped(.ziggui_row_bands);
const mod = @import("module.zig");

/// An image's rows split into bands of near-equal height for a pool of
/// workers to take one at a time.
///
/// A band is at most `cache_bytes` of pixels (`row_bytes` a row), so work
/// that passes over its pixels many times (drawing one shape over another)
/// does so in a core's cache rather than in main memory; however narrow, a
/// band is at least `min_band_rows` rows, unless the image is shorter. And
/// there are at least `bands_per_worker` bands a worker, so one that
/// finishes early (a band of empty background, a faster core) takes another
/// while a slow one finishes.
pub const RowBands = struct {
    const Self = @This();

    /// The most pixel bytes a band holds, so it stays in a core's L2 cache
    /// (256 KiB is the least among the cores this was tuned on).
    pub const cache_bytes: usize = 256 * 1024;

    /// The bands each worker gets, at least.
    pub const bands_per_worker: usize = 4;

    /// The fewest rows a band holds, unless the image is shorter: below it,
    /// handing a band out costs more than its rows.
    pub const min_band_rows: u32 = 4;

    /// The image's height, in rows.
    height: u32,
    /// How many bands, at least 1.
    count: usize,

    /// Splits `height` rows of `row_bytes` each for `worker_count` workers.
    ///
    /// - `height`: the image's height, in rows.
    /// - `row_bytes`: the bytes one row of pixels takes (0: no cache limit).
    /// - `worker_count`: how many workers take bands.
    /// - Returns: the split.
    pub fn init(height: u32, row_bytes: usize, worker_count: usize) Self {
        const total = @as(usize, height) * row_bytes;
        const for_cache = std.math.divCeil(usize, total, Self.cache_bytes) catch 1;
        const for_workers = if (worker_count <= 1) 1 else worker_count * Self.bands_per_worker;
        const most = @max(std.math.divCeil(usize, height, Self.min_band_rows) catch 1, 1);
        const count = std.math.clamp(@max(for_cache, for_workers), 1, most);
        const self = Self{ .height = height, .count = count };
        return self;
    }

    /// The band at `index`; the bands cover every row once, in order.
    ///
    /// - `self`: the split.
    /// - `index`: the band, below `count`.
    /// - Returns: its rows.
    pub fn band(self: *const Self, index: usize) mod.RowBand {
        std.debug.assert(index < self.count);
        const height: usize = self.height;
        return .{
            .top = @intCast(index * height / self.count),
            .bottom = @intCast((index + 1) * height / self.count),
        };
    }

    /// The band holding `row`: the inverse of `band`.
    ///
    /// - `self`: the split.
    /// - `row`: a row, below `height` (a row past it gives the last band).
    /// - Returns: the band's index, below `count`.
    pub fn indexOf(self: *const Self, row: u32) usize {
        if (self.height == 0) return 0;
        // Band i starts at floor(i * height / count), so the band holding
        // `row` is the last whose start is at or above it.
        const index = ((@as(usize, row) + 1) * self.count - 1) / self.height;
        return @min(index, self.count - 1);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "RowBands: no cache limit and one worker give one band of every row" {
    const bands = mod.RowBands.init(2160, 0, 1);
    try std.testing.expectEqual(@as(usize, 1), bands.count);
    try std.testing.expectEqual(mod.RowBand{ .top = 0, .bottom = 2160 }, bands.band(0));
}

test "RowBands: bands fit the cache, keep every worker busy, and hold a few rows" {
    // A 4K frame of f32 pixels is 132,710,400 bytes: 507 bands of 256 KiB at most (4 or 5 rows).
    try std.testing.expectEqual(@as(usize, 507), mod.RowBands.init(2160, 3840 * 16, 1).count);
    try std.testing.expectEqual(@as(usize, 507), mod.RowBands.init(2160, 3840 * 16, 16).count);
    // A small image: the workers ask for more bands than the cache does.
    try std.testing.expectEqual(@as(usize, 64), mod.RowBands.init(660, 100 * 16, 16).count);
    // 100 rows: four-row bands at the least, so 25, not 64.
    try std.testing.expectEqual(@as(usize, 25), mod.RowBands.init(100, 16, 16).count);
    try std.testing.expectEqual(@as(usize, 1), mod.RowBands.init(3, 1 << 20, 16).count);
    try std.testing.expectEqual(@as(usize, 1), mod.RowBands.init(0, 16, 16).count);
}

test "RowBands: indexOf finds the band holding each row" {
    for ([_]u32{ 1, 31, 33, 660, 1321, 2160 }) |height| {
        for ([_]usize{ 1, 3, 16 }) |workers| {
            for ([_]usize{ 0, 3840 * 16 }) |row_bytes| {
                const bands = mod.RowBands.init(height, row_bytes, workers);
                for (0..bands.count) |index| {
                    const band = bands.band(index);
                    var row = band.top;
                    while (row < band.bottom) : (row += 1) try std.testing.expectEqual(index, bands.indexOf(row));
                }
                try std.testing.expectEqual(bands.count - 1, bands.indexOf(height + 5));
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), mod.RowBands.init(0, 16, 4).indexOf(0));
}

test "RowBands: the bands cover every row once" {
    for ([_]u32{ 0, 1, 31, 33, 660, 1321, 2160 }) |height| {
        for ([_]usize{ 1, 2, 3, 16, 20 }) |workers| {
            for ([_]usize{ 0, 16, 3840 * 16 }) |row_bytes| {
                const bands = mod.RowBands.init(height, row_bytes, workers);
                var next: u32 = 0;
                for (0..bands.count) |index| {
                    const band = bands.band(index);
                    try std.testing.expectEqual(next, band.top);
                    next = band.bottom;
                }
                try std.testing.expectEqual(height, next);
            }
        }
    }
}
