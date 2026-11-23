//! The software rasterizer split across a worker pool, band by band of rows.

const std = @import("std");
const log = std.log.scoped(.ziggui_parallel_rasterizer);
const mod = @import("module.zig");

/// A pool task: fill one band with a color.
const ClearJob = struct {
    const Self = @This();

    /// The framebuffer cleared.
    framebuffer: *mod.Framebuffer,
    /// How its rows split.
    bands: mod.RowBands,
    /// The color.
    color: mod.Color,

    /// Clears band `index`.
    ///
    /// - `self`: the job.
    /// - `index`: the band.
    fn task(self: *const Self, index: usize) void {
        self.framebuffer.clearRows(self.color, self.bands.band(index));
    }
};

/// A run of a plan's items sorted into the bands each may reach, so a band
/// draws only its own bucket instead of testing every item: the work is the
/// sum of the bands each item reaches, not every item times every band.
/// Each bucket keeps drawing order.
const BandBuckets = struct {
    const Self = @This();

    /// Where each band's bucket starts in `indices`; one entry more, the end.
    starts: []usize,
    /// The items' indices into the run, bucket after bucket.
    indices: []usize,

    /// Sorts `items` into the buckets of `bands`.
    ///
    /// - `allocator`: allocator for the buckets (an arena: nothing is freed apart).
    /// - `items`: the run.
    /// - `bands`: how the rows split.
    /// - Returns: the buckets; propagates allocation failure.
    fn init(allocator: std.mem.Allocator, items: []const mod.RasterItem, bands: mod.RowBands) !Self {
        const starts = try allocator.alloc(usize, bands.count + 1);
        @memset(starts, 0);
        for (items) |*item| {
            const reach = Self.reachOf(item, bands) orelse continue;
            for (reach.first..reach.last + 1) |band| starts[band + 1] += 1;
        }
        for (1..starts.len) |band| starts[band] += starts[band - 1];
        const indices = try allocator.alloc(usize, starts[bands.count]);
        const next = try allocator.dupe(usize, starts[0..bands.count]);
        for (items, 0..) |*item, index| {
            const reach = Self.reachOf(item, bands) orelse continue;
            for (reach.first..reach.last + 1) |band| {
                indices[next[band]] = index;
                next[band] += 1;
            }
        }
        const self = Self{ .starts = starts, .indices = indices };
        return self;
    }

    /// The indices of the items band `index` draws, in drawing order.
    ///
    /// - `self`: the buckets.
    /// - `index`: the band.
    /// - Returns: the bucket.
    fn bucket(self: *const Self, index: usize) []const usize {
        return self.indices[self.starts[index]..self.starts[index + 1]];
    }

    /// The bands an item may reach: every band `RasterItem.mayTouch` would
    /// let it draw in, and perhaps one more either side (where `mayTouch`
    /// still skips it), so the image is what testing every band makes.
    ///
    /// - `item`: the item.
    /// - `bands`: how the rows split.
    /// - Returns: the first and last band, or null when it reaches none.
    fn reachOf(item: *const mod.RasterItem, bands: mod.RowBands) ?struct { first: usize, last: usize } {
        if (bands.height == 0) return null;
        const height: f32 = @floatFromInt(bands.height);
        // A NaN extent reaches every band, as `mayTouch` never skips it.
        if (std.math.isNan(item.min_y) or std.math.isNan(item.max_y)) return .{ .first = 0, .last = bands.count - 1 };
        if (item.max_y < 0 or item.min_y > height) return null;
        const last_row = height - 1;
        const first = bands.indexOf(@intFromFloat(std.math.clamp(@floor(item.min_y) - 1, 0, last_row)));
        const last = bands.indexOf(@intFromFloat(std.math.clamp(@ceil(item.max_y), 0, last_row)));
        // Past each other (a shape wholly outside its clip): `mayTouch` passes no band.
        if (first > last) return null;
        return .{ .first = first, .last = last };
    }
};

/// A pool task: one stage of a frame in one band, start to finish while
/// the band's pixels are in the core's cache: clear it (the first stage),
/// draw a run of a plan's items into it, convert it to RGBA8 (the last stage).
const DrawJob = struct {
    const Self = @This();

    /// The rasterizer of every row, narrowed per band.
    rasterizer: mod.Rasterizer,
    /// How its rows split.
    bands: mod.RowBands,
    /// The color the band is cleared to first, or null to keep its pixels.
    background: ?mod.Color = null,
    /// The items, none reading its neighbours.
    items: []const mod.RasterItem,
    /// The items each band draws.
    buckets: BandBuckets,
    /// The whole image's RGBA8 pixels, the band converted into them last, or null.
    bytes: ?[]u8 = null,

    /// Runs the stage in band `index`.
    ///
    /// - `self`: the job.
    /// - `index`: the band.
    fn task(self: *const Self, index: usize) void {
        const band = self.bands.band(index);
        const framebuffer = self.rasterizer.framebuffer;
        if (self.background) |color| framebuffer.clearRows(color, band);
        self.rasterizer.limitedTo(band).drawSelected(self.items, self.buckets.bucket(index));
        if (self.bytes) |bytes| framebuffer.toRgba8Rows(bytes, band);
    }
};

/// A pool task: convert one band to RGBA8.
const ConvertJob = struct {
    const Self = @This();

    /// The framebuffer converted.
    framebuffer: *const mod.Framebuffer,
    /// How its rows split.
    bands: mod.RowBands,
    /// The whole image's RGBA8 pixels.
    bytes: []u8,

    /// Converts band `index`.
    ///
    /// - `self`: the job.
    /// - `index`: the band.
    fn task(self: *const Self, index: usize) void {
        self.framebuffer.toRgba8Rows(self.bytes, self.bands.band(index));
    }
};

/// The software rasterizer with its work split into bands of rows that a
/// `WorkerPool` draws at once: clearing, drawing and converting to RGBA8.
///
/// Every band draws every command, limited to its own rows
/// (`Rasterizer.limitedTo`), so each pixel sees the same commands in the same
/// order as with one `Rasterizer`, and the image is byte-identical to it. A
/// blur reads pixels around it, which other bands may still be drawing, so
/// the bands all finish the commands before it, the blur runs on the calling
/// thread over every row, and the bands go on after it.
///
/// Without a pool (or with one worker) it does the same work on the calling
/// thread, one band.
pub const ParallelRasterizer = struct {
    const Self = @This();

    /// Allocator for the plan and the blur's scratch; used on the calling thread only.
    allocator: std.mem.Allocator,
    /// The framebuffer painted into.
    framebuffer: *mod.Framebuffer,
    /// The workers, or null to work on the calling thread alone.
    pool: ?*mod.WorkerPool,

    /// A rasterizer painting `framebuffer` with `pool`'s workers.
    ///
    /// - `allocator`: allocator for the plan and the blur's scratch.
    /// - `framebuffer`: the framebuffer painted into; sized before the calls.
    /// - `pool`: the workers, or null for the calling thread alone.
    /// - Returns: the rasterizer.
    pub fn init(allocator: std.mem.Allocator, framebuffer: *mod.Framebuffer, pool: ?*mod.WorkerPool) Self {
        const self = Self{ .allocator = allocator, .framebuffer = framebuffer, .pool = pool };
        return self;
    }

    /// Sets every pixel to `color`, band by band.
    ///
    /// - `self`: the rasterizer.
    /// - `color`: the color.
    pub fn clear(self: *const Self, color: mod.Color) void {
        const job: ClearJob = .{ .framebuffer = self.framebuffer, .bands = self.bands(), .color = color };
        self.runBands(ClearJob, &job, ClearJob.task);
    }

    /// Renders `commands` into the framebuffer, as `Rasterizer.render` does.
    ///
    /// - `self`: the rasterizer.
    /// - `commands`: the commands, in drawing order.
    /// - Returns: nothing; propagates allocation failure.
    pub fn render(self: *const Self, commands: []const mod.DrawCommand) !void {
        try self.drawFrame(null, commands, null);
    }

    /// A whole frame at once: clears the framebuffer to `background`, renders
    /// `commands`, and converts it to RGBA8 into `bytes`, each band doing all
    /// three while its pixels are in its core's cache, so a shape drawn over
    /// another costs no trip to main memory. The same bytes as `clear`,
    /// `render` and `toRgba8` one after the other.
    ///
    /// - `self`: the rasterizer.
    /// - `background`: the color cleared to first, or null to draw over the pixels there.
    /// - `commands`: the commands, in drawing order.
    /// - `bytes`: receives the pixels (`width * height * 4` long), or null to leave them in the framebuffer.
    /// - Returns: nothing; propagates allocation failure.
    pub fn drawFrame(self: *const Self, background: ?mod.Color, commands: []const mod.DrawCommand, bytes: ?[]u8) !void {
        var plan = try mod.RasterPlan.init(self.allocator, commands);
        defer plan.deinit();
        const whole = mod.Rasterizer.init(self.allocator, self.framebuffer);
        const row_bands = self.bands();
        // The buckets of one stage at a time.
        var bucket_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer bucket_arena.deinit();
        // Stage by stage, a blur between each: it reads pixels around it, so
        // every band must be done with what is under it first.
        var start: usize = 0;
        var first = true;
        while (true) {
            const end = plan.runEnd(start);
            const last = end == plan.items.len;
            _ = bucket_arena.reset(.retain_capacity);
            const items = plan.items[start..end];
            const job: DrawJob = .{
                .rasterizer = whole,
                .bands = row_bands,
                .background = if (first) background else null,
                .items = items,
                .buckets = try .init(bucket_arena.allocator(), items, row_bands),
                .bytes = if (last) bytes else null,
            };
            if (job.background != null or job.items.len > 0 or job.bytes != null) self.runBands(DrawJob, &job, DrawJob.task);
            if (last) break;
            // The blur, over every row, on this thread.
            try whole.drawItem(&plan.items[end]);
            start = end + 1;
            first = false;
        }
    }

    /// Converts the framebuffer into a tightly-packed RGBA8 buffer, band by band.
    ///
    /// - `self`: the rasterizer.
    /// - `bytes`: receives the pixels; `width * height * 4` long.
    pub fn toRgba8(self: *const Self, bytes: []u8) void {
        const job: ConvertJob = .{ .framebuffer = self.framebuffer, .bands = self.bands(), .bytes = bytes };
        self.runBands(ConvertJob, &job, ConvertJob.task);
    }

    /// How the framebuffer's rows split for the pool's workers.
    ///
    /// - `self`: the rasterizer.
    /// - Returns: the bands.
    fn bands(self: *const Self) mod.RowBands {
        const workers = if (self.pool) |pool| pool.workerCount() else 1;
        return .init(self.framebuffer.height, @as(usize, self.framebuffer.width) * @sizeOf(mod.Color), workers);
    }

    /// Runs `function` once per band of `job`, on the pool or the calling thread.
    ///
    /// - `self`: the rasterizer.
    /// - `T`: the job's type.
    /// - `job`: the job; holds its `bands`.
    /// - `function`: the task, given the job and a band's index.
    fn runBands(self: *const Self, comptime T: type, job: *const T, comptime function: fn (*const T, usize) void) void {
        if (self.pool) |pool| return pool.run(T, job, function, job.bands.count);
        for (0..job.bands.count) |index| function(job, index);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// Draws a scene of every kind of command, a blur between them, under clips.
const TestScene = struct {
    const Self = @This();

    /// Fills `display_list` with the scene for a `width` × `height` image.
    ///
    /// - `display_list`: receives the commands.
    /// - `width`: the image's width.
    /// - `height`: the image's height.
    /// - Returns: nothing; propagates allocation failure.
    fn build(display_list: *mod.DisplayList, width: f32, height: f32) !void {
        const whole: mod.Rect = .{ .x = 0, .y = 0, .width = width, .height = height };
        try display_list.fillRect(whole, mod.Color.white);
        var index: f32 = 0;
        while (index < 40) : (index += 1) {
            const rect: mod.Rect = .{ .x = index * 7.3, .y = index * 5.1 + 0.4, .width = 60.5, .height = 33.25 };
            try display_list.fillRoundedRect(rect, 9, mod.Color.fromRgba8(30, @intFromFloat(index * 5), 200, 180));
            try display_list.strokeRoundedRect(rect, 9, 1.5, mod.Color.black);
            try display_list.line(.{ .x = 0, .y = index * 6 }, .{ .x = width, .y = height - index * 3 }, 1.25, mod.Color.red);
        }
        try display_list.pushClip(.{ .x = 20.5, .y = 30.5, .width = 150, .height = 120 }, 14);
        try display_list.fillCircle(.{ .x = 90, .y = 90 }, 70, mod.Color.blue.withAlpha(0.5));
        try display_list.blurRect(.{ .x = 40, .y = 50, .width = 120, .height = 90 }, 10, 12, mod.Color.white.withAlpha(0.3));
        try display_list.fillRoundedRect(.{ .x = 60, .y = 70, .width = 50, .height = 50 }, 25, mod.Color.green.withAlpha(0.7));
        // Wholly below the clip: its rows and the clip's never meet.
        try display_list.fillRect(.{ .x = 30, .y = 200, .width = 40, .height = 20 }, mod.Color.red);
        try display_list.popClip();
        try display_list.eraseRect(.{ .x = 200, .y = 20, .width = 40, .height = 60 }, 6);
    }
};

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "ParallelRasterizer: bands make the image one rasterizer makes, byte for byte" {
    const allocator = std.testing.allocator;
    const width: u32 = 301;
    const height: u32 = 257;
    var display_list = mod.DisplayList.init(allocator);
    defer display_list.deinit();
    try TestScene.build(&display_list, @floatFromInt(width), @floatFromInt(height));

    var single = try mod.Framebuffer.init(allocator, width, height);
    defer single.deinit();
    single.clear(mod.Color.transparent);
    try mod.Rasterizer.init(allocator, &single).render(display_list.commands.items);
    const expected = try single.toRgba8Alloc(allocator);
    defer allocator.free(expected);

    const pool = try mod.WorkerPool.create(allocator, std.testing.io, 6);
    defer pool.destroy();
    var banded = try mod.Framebuffer.init(allocator, width, height);
    defer banded.deinit();
    const actual = try allocator.alloc(u8, expected.len);
    defer allocator.free(actual);
    for ([_]?*mod.WorkerPool{ null, pool }) |maybe_pool| {
        const parallel = mod.ParallelRasterizer.init(allocator, &banded, maybe_pool);
        @memset(actual, 0);
        parallel.clear(mod.Color.transparent);
        try parallel.render(display_list.commands.items);
        parallel.toRgba8(actual);
        try std.testing.expectEqualSlices(u8, expected, actual);
        @memset(actual, 0);
        try parallel.drawFrame(mod.Color.transparent, display_list.commands.items, actual);
        try std.testing.expectEqualSlices(u8, expected, actual);
    }
}
