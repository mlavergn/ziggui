//! A pure-Zig TrueType (`glyf`-flavored) font parser and glyph rasterizer.
//!
//! Supports the subset ziggui needs to render UI text: the offset/table
//! directory, `head`/`maxp`/`hhea`/`hmtx`, `cmap` (formats 4 and 12), `loca`,
//! and `glyf` (simple + composite glyphs). Outlines are flattened (quadratic
//! beziers) and rasterized to an 8-bit coverage bitmap with supersampled
//! anti-aliasing. No C dependencies — works identically on every platform and
//! in headless tests. Variable fonts parse fine: we read the default-master
//! outlines from `glyf` and ignore `gvar`.
//!
//! The blob may be untrusted (`Font.fromBytes`): every read is bounds-checked,
//! `parse` rejects a font whose tables do not fit, and a malformed glyph
//! rasterizes as an empty one instead of reading out of range.

const std = @import("std");
const log = std.log.scoped(.ziggui_ttf_font);
const mod = @import("module.zig");

/// Why a blob failed to parse as a TrueType font.
pub const TtfParseError = error{
    InvalidFont,
    UnsupportedFormat,
    TableMissing,
};

/// A read past the end of the blob (or of the table or glyph read).
const FontReadError = error{InvalidFont};

/// Why a glyph outline could not be collected: malformed data, or no memory.
const OutlineError = error{ InvalidFont, OutOfMemory };

/// A codepoint resolved to the face that actually carries its glyph.
pub const ResolvedGlyph = struct {
    const Self = @This();

    /// The face the glyph belongs to.
    face: *const TtfFont,
    /// The glyph index within `face`.
    glyph: u16,
};

/// Bounds-checked big-endian byte reader over the font blob. A read that does
/// not fit inside `data` fails with `error.InvalidFont`.
const BigEndianReader = struct {
    const Self = @This();

    /// The bytes reads may touch (the blob, or a prefix of it).
    data: []const u8,

    /// A reader over the first `end` bytes only, so reads past `end` fail.
    fn bounded(self: *const Self, end: usize) Self {
        const reader = Self{ .data = self.data[0..@min(end, self.data.len)] };
        return reader;
    }

    /// Fail unless `length` bytes from `offset` lie inside the data.
    fn require(self: *const Self, offset: usize, length: usize) FontReadError!void {
        if (offset > self.data.len or self.data.len - offset < length) return error.InvalidFont;
    }

    /// The `length` bytes at `offset`.
    fn bytes(self: *const Self, offset: usize, comptime length: usize) FontReadError!*const [length]u8 {
        try self.require(offset, length);
        return self.data[offset..][0..length];
    }

    /// The byte at `offset`.
    fn byteAt(self: *const Self, offset: usize) FontReadError!u8 {
        return (try self.bytes(offset, 1))[0];
    }

    /// The big-endian u16 at `offset`.
    fn readU16(self: *const Self, offset: usize) FontReadError!u16 {
        return std.mem.readInt(u16, try self.bytes(offset, 2), .big);
    }

    /// The big-endian i16 at `offset`.
    fn readI16(self: *const Self, offset: usize) FontReadError!i16 {
        return std.mem.readInt(i16, try self.bytes(offset, 2), .big);
    }

    /// The big-endian u32 at `offset`.
    fn readU32(self: *const Self, offset: usize) FontReadError!u32 {
        return std.mem.readInt(u32, try self.bytes(offset, 4), .big);
    }

    /// The 2.14 fixed-point number at `offset`, as a float.
    fn readF2Dot14(self: *const Self, offset: usize) FontReadError!f32 {
        return @as(f32, @floatFromInt(try self.readI16(offset))) / 16384.0;
    }
};

/// A table's byte range in the blob, checked to lie inside it.
const TableRange = struct {
    const Self = @This();

    /// The table's offset in the blob.
    offset: usize,
    /// The table's length in bytes.
    length: usize,

    /// One past the table's last byte.
    fn end(self: *const Self) usize {
        return self.offset + self.length;
    }
};

/// The tables `parse` reads, as found in the table directory.
const TableDirectory = struct {
    const Self = @This();

    /// `head`: units per em and the `loca` format.
    head: ?TableRange = null,
    /// `maxp`: the glyph count.
    maxp: ?TableRange = null,
    /// `hhea`: vertical metrics and the `hmtx` count.
    hhea: ?TableRange = null,
    /// `loca`: each glyph's offset in `glyf`.
    loca: ?TableRange = null,
    /// `glyf`: the outlines.
    glyf: ?TableRange = null,
    /// `hmtx`: the advances.
    hmtx: ?TableRange = null,
    /// `cmap`: codepoints to glyphs.
    cmap: ?TableRange = null,

    /// Read the directory, checking each table this parser uses lies inside
    /// the blob.
    fn read(reader: *const BigEndianReader) TtfParseError!Self {
        var self = Self{};
        const table_count = try reader.readU16(4);
        var table_index: usize = 0;
        while (table_index < table_count) : (table_index += 1) {
            const record = 12 + table_index * 16;
            const tag = try reader.bytes(record, 4);
            const offset = try reader.readU32(record + 8);
            const length = try reader.readU32(record + 12);
            const slot = self.slotFor(tag) orelse continue;
            if (@as(u64, offset) + length > reader.data.len) return error.InvalidFont;
            slot.* = .{ .offset = offset, .length = length };
        }
        return self;
    }

    /// The field a used table's tag fills, or null for a table this parser
    /// ignores.
    fn slotFor(self: *Self, tag: *const [4]u8) ?*?TableRange {
        if (std.mem.eql(u8, tag, "head")) return &self.head;
        if (std.mem.eql(u8, tag, "maxp")) return &self.maxp;
        if (std.mem.eql(u8, tag, "hhea")) return &self.hhea;
        if (std.mem.eql(u8, tag, "loca")) return &self.loca;
        if (std.mem.eql(u8, tag, "glyf")) return &self.glyf;
        if (std.mem.eql(u8, tag, "hmtx")) return &self.hmtx;
        if (std.mem.eql(u8, tag, "cmap")) return &self.cmap;
        return null;
    }

    /// A table that must be present (a zero offset counts as absent) and at
    /// least `min_length` bytes long.
    fn required(table: ?TableRange, min_length: usize) TtfParseError!TableRange {
        const range = table orelse return error.TableMissing;
        if (range.offset == 0) return error.TableMissing;
        if (range.length < min_length) return error.InvalidFont;
        return range;
    }
};

/// Where a usable `cmap` subtable starts and which format it is.
const CmapSubtable = struct {
    const Self = @This();

    /// The subtable's offset in the blob.
    offset: usize,
    /// The subtable format (4 or 12).
    format: u16,
};

/// A glyph's byte range in the blob.
const GlyfRange = struct {
    const Self = @This();

    /// The first byte.
    start: usize,
    /// One past the last byte.
    end: usize,
};

/// A 2D affine transform (font units).
const Transform = struct {
    const Self = @This();

    /// x scale.
    scale_x: f32 = 1,
    /// y contribution of x.
    skew_y: f32 = 0,
    /// x contribution of y.
    skew_x: f32 = 0,
    /// y scale.
    scale_y: f32 = 1,
    /// x translation.
    translate_x: f32 = 0,
    /// y translation.
    translate_y: f32 = 0,

    /// The identity transform.
    const identity = Self{};

    /// Transform a point.
    fn apply(self: *const Self, x: f32, y: f32) [2]f32 {
        return .{ self.scale_x * x + self.skew_x * y + self.translate_x, self.skew_y * x + self.scale_y * y + self.translate_y };
    }

    /// self ∘ other  (apply other first, then self).
    fn compose(self: *const Self, other: Self) Self {
        return .{
            .scale_x = self.scale_x * other.scale_x + self.skew_x * other.skew_y,
            .skew_y = self.skew_y * other.scale_x + self.scale_y * other.skew_y,
            .skew_x = self.scale_x * other.skew_x + self.skew_x * other.scale_y,
            .scale_y = self.skew_y * other.skew_x + self.scale_y * other.scale_y,
            .translate_x = self.scale_x * other.translate_x + self.skew_x * other.translate_y + self.translate_x,
            .translate_y = self.skew_y * other.translate_x + self.scale_y * other.translate_y + self.translate_y,
        };
    }
};

/// One straight outline segment.
const Edge = struct {
    const Self = @This();

    /// The start's x.
    start_x: f32,
    /// The start's y.
    start_y: f32,
    /// The end's x.
    end_x: f32,
    /// The end's y.
    end_y: f32,

    /// The smaller of the edge's two y values.
    fn topY(self: *const Self) f32 {
        return @min(self.start_y, self.end_y);
    }

    /// The larger of the edge's two y values.
    fn bottomY(self: *const Self) f32 {
        return @max(self.start_y, self.end_y);
    }
};

/// What one glyph's outline may still cost: composite components and edges are
/// capped so a hostile font cannot make one glyph do unbounded work.
const OutlineBudget = struct {
    const Self = @This();

    /// The most composite components (at every depth) one glyph may reference.
    const max_components = 1024;
    /// The most edges one glyph may flatten to.
    const max_edges = 1 << 16;

    /// Components referenced so far.
    components: usize = 0,

    /// Count one more component; fail past `max_components`.
    fn takeComponent(self: *Self) FontReadError!void {
        if (self.components >= max_components) return error.InvalidFont;
        self.components += 1;
    }
};

/// Flattens a glyph's contours into transformed edges.
const ContourEmitter = struct {
    const Self = @This();

    /// The allocator the edge list grows with.
    allocator: std.mem.Allocator,
    /// The edges collected so far.
    edges: *std.ArrayList(Edge),
    /// The transform applied to every point.
    transform: Transform,

    /// Whether a point flag marks an on-curve point.
    fn isOnCurve(flag: u8) bool {
        return flag & 0x01 != 0;
    }

    /// Emit one contour's edges (quadratic segments flattened).
    fn emitContour(self: *const Self, x_coordinates: []const f32, y_coordinates: []const f32, flags: []const u8) OutlineError!void {
        const point_count = x_coordinates.len;
        if (point_count == 0) return;

        var start_x: f32 = undefined;
        var start_y: f32 = undefined;
        var first_index: usize = undefined;
        if (ContourEmitter.isOnCurve(flags[0])) {
            start_x = x_coordinates[0];
            start_y = y_coordinates[0];
            first_index = 1;
        } else if (ContourEmitter.isOnCurve(flags[point_count - 1])) {
            start_x = x_coordinates[point_count - 1];
            start_y = y_coordinates[point_count - 1];
            first_index = 0;
        } else {
            start_x = (x_coordinates[0] + x_coordinates[point_count - 1]) / 2;
            start_y = (y_coordinates[0] + y_coordinates[point_count - 1]) / 2;
            first_index = 0;
        }

        var current_x = start_x;
        var current_y = start_y;
        var has_control = false;
        var control_x: f32 = 0;
        var control_y: f32 = 0;

        var index = first_index;
        while (index < point_count) : (index += 1) {
            if (ContourEmitter.isOnCurve(flags[index])) {
                try self.lineOrQuadratic(&current_x, &current_y, &has_control, control_x, control_y, x_coordinates[index], y_coordinates[index]);
                has_control = false;
            } else {
                if (has_control) {
                    const middle_x = (control_x + x_coordinates[index]) / 2;
                    const middle_y = (control_y + y_coordinates[index]) / 2;
                    try self.lineOrQuadratic(&current_x, &current_y, &has_control, control_x, control_y, middle_x, middle_y);
                }
                has_control = true;
                control_x = x_coordinates[index];
                control_y = y_coordinates[index];
            }
        }
        // close the contour back to the start point
        try self.lineOrQuadratic(&current_x, &current_y, &has_control, control_x, control_y, start_x, start_y);
    }

    /// Emit a line to the target, or a flattened quadratic through the pending
    /// control point.
    fn lineOrQuadratic(
        self: *const Self,
        current_x: *f32,
        current_y: *f32,
        has_control: *bool,
        control_x: f32,
        control_y: f32,
        target_x: f32,
        target_y: f32,
    ) OutlineError!void {
        if (has_control.*) {
            // flatten quadratic from (current) via (control) to (target)
            const steps: usize = 8;
            var step: usize = 1;
            while (step <= steps) : (step += 1) {
                const fraction = @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(steps));
                const inverse_fraction = 1 - fraction;
                const point_x = inverse_fraction * inverse_fraction * current_x.* + 2 * inverse_fraction * fraction * control_x + fraction * fraction * target_x;
                const point_y = inverse_fraction * inverse_fraction * current_y.* + 2 * inverse_fraction * fraction * control_y + fraction * fraction * target_y;
                try self.pushEdge(current_x.*, current_y.*, point_x, point_y);
                current_x.* = point_x;
                current_y.* = point_y;
            }
            has_control.* = false;
        } else {
            try self.pushEdge(current_x.*, current_y.*, target_x, target_y);
            current_x.* = target_x;
            current_y.* = target_y;
        }
    }

    /// Append one transformed edge; fail past the glyph's edge budget.
    fn pushEdge(self: *const Self, start_x: f32, start_y: f32, end_x: f32, end_y: f32) OutlineError!void {
        if (self.edges.items.len >= OutlineBudget.max_edges) return error.InvalidFont;
        const start = self.transform.apply(start_x, start_y);
        const end = self.transform.apply(end_x, end_y);
        try self.edges.append(self.allocator, .{ .start_x = start[0], .start_y = start[1], .end_x = end[0], .end_y = end[1] });
    }
};

/// Where a scanline crosses an edge, and which way the edge winds.
const Crossing = struct {
    const Self = @This();

    /// The crossing's x.
    x: f32,
    /// +1 for an edge going down the bitmap, -1 for one going up.
    direction: i32,

    /// Order crossings left to right.
    fn lessThan(_: void, left: Self, right: Self) bool {
        return left.x < right.x;
    }
};

/// Scanline coverage over a glyph's edges, with 4x4 supersampling and nonzero
/// winding. A sample is inside when the edges crossing its sample row to its
/// right wind to nonzero; each sample row's crossings are computed once and
/// swept left to right, from only the edges that span the row.
const CoverageScanner = struct {
    const Self = @This();

    /// Sample rows and columns per pixel.
    const samples: u32 = 4;

    /// The glyph's edges in bitmap pixel space.
    edges: []const Edge,
    /// The allocator the scratch lists grow with.
    allocator: std.mem.Allocator,

    /// Fill `bitmap` (`width` x `height`) with the edges' coverage.
    fn rasterize(self: *const Self, bitmap: []u8, width: u32, height: u32) std.mem.Allocator.Error!void {
        const samples_float: f32 = @floatFromInt(samples);
        const inverse_samples: f32 = 1.0 / @as(f32, @floatFromInt(samples * samples));

        // Edges by their top, so each sample row admits the edges reaching it.
        const by_top = try self.allocator.alloc(u32, self.edges.len);
        defer self.allocator.free(by_top);
        for (by_top, 0..) |*slot, index| slot.* = @intCast(index);
        std.mem.sort(u32, by_top, self, Self.topLessThan);

        var active: std.ArrayList(u32) = .empty;
        defer active.deinit(self.allocator);
        var crossings: std.ArrayList(Crossing) = .empty;
        defer crossings.deinit(self.allocator);
        const inside_counts = try self.allocator.alloc(u32, width);
        defer self.allocator.free(inside_counts);

        var next_edge: usize = 0;
        var pixel_y: u32 = 0;
        while (pixel_y < height) : (pixel_y += 1) {
            @memset(inside_counts, 0);
            var sample_y: u32 = 0;
            while (sample_y < samples) : (sample_y += 1) {
                const float_y = @as(f32, @floatFromInt(pixel_y)) + (@as(f32, @floatFromInt(sample_y)) + 0.5) / samples_float;
                while (next_edge < by_top.len and self.edges[by_top[next_edge]].topY() <= float_y) : (next_edge += 1) {
                    try active.append(self.allocator, by_top[next_edge]);
                }
                try self.rowCrossings(float_y, &active, &crossings);
                Self.sweepRow(crossings.items, inside_counts, samples_float);
            }
            var pixel_x: u32 = 0;
            while (pixel_x < width) : (pixel_x += 1) {
                const coverage = @as(f32, @floatFromInt(inside_counts[pixel_x])) * inverse_samples;
                bitmap[pixel_y * width + pixel_x] = @intFromFloat(@round(coverage * 255.0));
            }
        }
    }

    /// Whether edge `left` starts above edge `right`.
    fn topLessThan(self: *const Self, left: u32, right: u32) bool {
        return self.edges[left].topY() < self.edges[right].topY();
    }

    /// The crossings of the sample row at `sample_y`, sorted left to right;
    /// drops active edges that end at or above the row (rows only go down).
    fn rowCrossings(self: *const Self, sample_y: f32, active: *std.ArrayList(u32), crossings: *std.ArrayList(Crossing)) std.mem.Allocator.Error!void {
        crossings.clearRetainingCapacity();
        var kept: usize = 0;
        for (active.items) |edge_index| {
            const edge = self.edges[edge_index];
            if (edge.bottomY() <= sample_y) continue;
            active.items[kept] = edge_index;
            kept += 1;
            if (edge.start_y <= sample_y and edge.end_y > sample_y) {
                const fraction = (sample_y - edge.start_y) / (edge.end_y - edge.start_y);
                const intersect_x = edge.start_x + fraction * (edge.end_x - edge.start_x);
                try crossings.append(self.allocator, .{ .x = intersect_x, .direction = 1 });
            } else if (edge.end_y <= sample_y and edge.start_y > sample_y) {
                const fraction = (sample_y - edge.start_y) / (edge.end_y - edge.start_y);
                const intersect_x = edge.start_x + fraction * (edge.end_x - edge.start_x);
                try crossings.append(self.allocator, .{ .x = intersect_x, .direction = -1 });
            }
        }
        active.shrinkRetainingCapacity(kept);
        std.mem.sort(Crossing, crossings.items, {}, Crossing.lessThan);
    }

    /// Count, per pixel, the row's samples inside the outline: a sample's
    /// winding is the sum of the directions of the crossings right of it.
    fn sweepRow(crossings: []const Crossing, inside_counts: []u32, samples_float: f32) void {
        var total: i32 = 0;
        for (crossings) |crossing| total += crossing.direction;
        var passed: i32 = 0; // the directions of the crossings at or left of the sample
        var crossing_index: usize = 0;
        for (inside_counts, 0..) |*inside_count, pixel_x| {
            var sample_x: u32 = 0;
            while (sample_x < samples) : (sample_x += 1) {
                const float_x = @as(f32, @floatFromInt(pixel_x)) + (@as(f32, @floatFromInt(sample_x)) + 0.5) / samples_float;
                while (crossing_index < crossings.len and !(crossings[crossing_index].x > float_x)) : (crossing_index += 1) {
                    passed += crossings[crossing_index].direction;
                }
                if (total - passed != 0) inside_count.* += 1;
            }
        }
    }
};

/// A parsed TrueType face (or one backed by an `ExternalFace`).
pub const TtfFont = struct {
    const Self = @This();

    /// The widest or tallest glyph bitmap `rasterizeGlyph` makes, in pixels;
    /// a glyph that would be larger rasterizes empty.
    const max_bitmap_side = 4096;
    /// How deep composite glyphs may nest.
    const max_composite_depth = 5;

    /// The font blob.
    data: []const u8,
    /// Font units per em.
    units_per_em: u16,
    /// How many glyphs the face holds.
    glyph_count: u16,
    /// Whether `loca` uses 32-bit offsets.
    long_loca: bool,
    /// The `loca` table's offset.
    loca_offset: usize,
    /// The `glyf` table's offset.
    glyf_offset: usize,
    /// The `glyf` table's length.
    glyf_length: usize = 0,
    /// The `hmtx` table's offset.
    hmtx_offset: usize,
    /// How many long horizontal metrics `hmtx` holds.
    horizontal_metric_count: u16,
    /// The chosen `cmap` subtable's offset.
    cmap_subtable_offset: usize,
    /// The chosen `cmap` subtable's format.
    cmap_format: u16,
    /// One past the `cmap` table's last byte; lookups read no further.
    cmap_end: usize = 0,
    /// Ascent in font units.
    ascent: i16,
    /// Descent in font units (negative below the baseline).
    descent: i16,
    /// Line gap in font units.
    line_gap: i16,
    /// Optional fallback face, consulted by `resolve` for codepoints this font
    /// lacks (e.g. a monochrome emoji font behind a Latin UI font). The pointee
    /// must outlive this font. Glyph indices are per-face, so callers must
    /// rasterize each glyph from the face `resolve` returns — not this one.
    fallback: ?*const Self = null,
    /// The engine that reads this face's outlines, when it is not parsed here.
    external: ?*const mod.ExternalFace = null,

    /// The bundled Inter font blob.
    pub const inter_ttf = @embedFile("inter_font");
    /// The bundled Lucide icon font blob.
    pub const icon_ttf = @embedFile("icon_font");
    /// The bundled Noto Emoji font blob.
    pub const emoji_ttf = @embedFile("emoji_font");

    /// A face backed by `external`; vertical metrics in font units.
    ///
    /// - `external`: the engine's callbacks.
    /// - `units_per_em`: font units per em.
    /// - `ascent`: ascent in font units.
    /// - `descent`: descent in font units.
    /// - `line_gap`: line gap in font units.
    /// - Returns: the face.
    pub fn fromExternal(external: *const mod.ExternalFace, units_per_em: u16, ascent: i16, descent: i16, line_gap: i16) Self {
        const self = Self{
            .data = &.{},
            .units_per_em = units_per_em,
            .glyph_count = 0,
            .long_loca = false,
            .loca_offset = 0,
            .glyf_offset = 0,
            .hmtx_offset = 0,
            .horizontal_metric_count = 0,
            .cmap_subtable_offset = 0,
            .cmap_format = 0,
            .ascent = ascent,
            .descent = descent,
            .line_gap = line_gap,
            .external = external,
        };
        return self;
    }

    /// Parse a TrueType blob. The blob may be untrusted: every table read must
    /// lie inside it, and the header fields must be sane (`unitsPerEm` in
    /// 16...16384, at least one horizontal metric, `loca` long enough for every
    /// glyph, a well-formed Unicode `cmap` subtable).
    ///
    /// - `data`: the blob; it must outlive the face.
    /// - Returns: the face; fails when the blob is not a usable TrueType font.
    pub fn parse(data: []const u8) TtfParseError!Self {
        if (data.len < 12) return error.InvalidFont;
        const reader = BigEndianReader{ .data = data };
        const sfnt = try reader.readU32(0);
        // 0x00010000 (TrueType) or 'true'. 'OTTO' (CFF) unsupported.
        if (sfnt != 0x00010000 and sfnt != 0x74727565) return error.UnsupportedFormat;

        const directory = try TableDirectory.read(&reader);
        const head = try TableDirectory.required(directory.head, 54);
        const maxp = try TableDirectory.required(directory.maxp, 6);
        const hhea = try TableDirectory.required(directory.hhea, 36);
        const loca = try TableDirectory.required(directory.loca, 0);
        const glyf = try TableDirectory.required(directory.glyf, 0);
        const hmtx = try TableDirectory.required(directory.hmtx, 0);
        const cmap = try TableDirectory.required(directory.cmap, 4);

        const units_per_em = try reader.readU16(head.offset + 18);
        if (units_per_em < 16 or units_per_em > 16384) return error.InvalidFont;
        const index_to_loc = try reader.readI16(head.offset + 50);
        if (index_to_loc != 0 and index_to_loc != 1) return error.InvalidFont;
        const glyph_count = try reader.readU16(maxp.offset + 4);
        const ascent = try reader.readI16(hhea.offset + 4);
        const descent = try reader.readI16(hhea.offset + 6);
        const line_gap = try reader.readI16(hhea.offset + 8);
        const horizontal_metric_count = try reader.readU16(hhea.offset + 34);
        if (horizontal_metric_count == 0) return error.InvalidFont;
        if (hmtx.length < @as(usize, horizontal_metric_count) * 4) return error.InvalidFont;
        const loca_entry_size: usize = if (index_to_loc != 0) 4 else 2;
        if (loca.length < (@as(usize, glyph_count) + 1) * loca_entry_size) return error.InvalidFont;

        const cmap_subtable = try Self.findCmapSubtable(&reader.bounded(cmap.end()), cmap);

        const self = Self{
            .data = data,
            .units_per_em = units_per_em,
            .glyph_count = glyph_count,
            .long_loca = index_to_loc != 0,
            .loca_offset = loca.offset,
            .glyf_offset = glyf.offset,
            .glyf_length = glyf.length,
            .hmtx_offset = hmtx.offset,
            .horizontal_metric_count = horizontal_metric_count,
            .cmap_subtable_offset = cmap_subtable.offset,
            .cmap_format = cmap_subtable.format,
            .cmap_end = cmap.end(),
            .ascent = ascent,
            .descent = descent,
            .line_gap = line_gap,
        };
        return self;
    }

    /// Resolve a codepoint to a (face, glyph) pair: this font if it has the
    /// glyph, else the `fallback` chain. Returns this font's .notdef (glyph 0)
    /// when nothing has it. Since glyph indices are per-face, render the glyph
    /// from the returned `face`, not necessarily `self`.
    ///
    /// - `self`: the primary face.
    /// - `codepoint`: the codepoint.
    /// - Returns: the face carrying the glyph and its index.
    pub fn resolve(self: *const Self, codepoint: u21) ResolvedGlyph {
        const glyph = self.glyphIndex(codepoint);
        if (glyph != 0) return .{ .face = self, .glyph = glyph };
        var next = self.fallback;
        while (next) |face| : (next = face.fallback) {
            const fallback_glyph = face.glyphIndex(codepoint);
            if (fallback_glyph != 0) return .{ .face = face, .glyph = fallback_glyph };
        }
        return .{ .face = self, .glyph = glyph };
    }

    /// Map a Unicode codepoint to a glyph index (0 = .notdef / missing). A
    /// malformed mapping, or one to a glyph the face lacks, is missing.
    ///
    /// - `self`: the face.
    /// - `codepoint`: the codepoint.
    /// - Returns: the glyph index.
    pub fn glyphIndex(self: *const Self, codepoint: u21) u16 {
        if (self.external) |external| return external.glyph_index(external.context, codepoint);
        const reader = BigEndianReader{ .data = self.data[0..@min(self.cmap_end, self.data.len)] };
        const glyph: u32 = switch (self.cmap_format) {
            4 => self.cmapFormat4(&reader, codepoint) catch 0,
            12 => self.cmapFormat12(&reader, codepoint) catch 0,
            else => 0,
        };
        if (glyph >= self.glyph_count) return 0;
        return @intCast(glyph);
    }

    /// Horizontal advance for a glyph in font units.
    ///
    /// - `self`: the face.
    /// - `glyph`: the glyph index.
    /// - Returns: the advance (0 when the face has no metrics).
    pub fn advanceWidth(self: *const Self, glyph: u16) u16 {
        if (self.external) |external| return external.advance_width(external.context, glyph);
        if (self.horizontal_metric_count == 0) return 0;
        const reader = BigEndianReader{ .data = self.data };
        const index: usize = if (glyph < self.horizontal_metric_count) glyph else self.horizontal_metric_count - 1;
        return reader.readU16(self.hmtx_offset + index * 4) catch 0;
    }

    /// Em-units → pixels scale for a target em size in pixels.
    ///
    /// - `self`: the face.
    /// - `pixel_size`: the em size in pixels.
    /// - Returns: the scale.
    pub fn scaleForPixelSize(self: *const Self, pixel_size: f32) f32 {
        return pixel_size / @as(f32, @floatFromInt(self.units_per_em));
    }

    /// Rasterize a glyph to a coverage bitmap at `scale` (font units → pixels).
    /// A glyph whose outline is malformed, or whose bitmap would be wider or
    /// taller than 4096 pixels, and any scale that is not a positive finite
    /// number, rasterize empty (no bitmap).
    ///
    /// - `self`: the face.
    /// - `allocator`: allocator for the bitmap (the caller owns it).
    /// - `glyph`: the glyph index.
    /// - `scale`: font units to pixels.
    /// - Returns: the glyph; propagates allocation failure.
    pub fn rasterizeGlyph(self: *const Self, allocator: std.mem.Allocator, glyph: u16, scale: f32) std.mem.Allocator.Error!mod.RasterGlyph {
        if (self.external) |external| return external.rasterize(external.context, allocator, glyph, scale);
        if (!(scale > 0) or !std.math.isFinite(scale)) return .{ .width = 0, .height = 0, .data = &.{}, .left = 0, .top = 0, .advance = 0 };
        const advance = @as(f32, @floatFromInt(self.advanceWidth(glyph))) * scale;
        return self.rasterizeOutline(allocator, glyph, scale, advance) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidFont => {
                log.debug("glyph {d} is malformed; drawn empty", .{glyph});
                return .{ .width = 0, .height = 0, .data = &.{}, .left = 0, .top = 0, .advance = advance };
            },
        };
    }

    /// Rasterize a glyph's outline; `error.InvalidFont` when it is malformed.
    fn rasterizeOutline(self: *const Self, allocator: std.mem.Allocator, glyph: u16, scale: f32, advance: f32) OutlineError!mod.RasterGlyph {
        const empty = mod.RasterGlyph{ .width = 0, .height = 0, .data = &.{}, .left = 0, .top = 0, .advance = advance };
        var edges: std.ArrayList(Edge) = .empty;
        defer edges.deinit(allocator);
        var budget = OutlineBudget{};
        try self.collectEdges(allocator, glyph, &edges, Transform.identity, 0, &budget);

        if (edges.items.len == 0) return empty;

        // Bounds from the actual edges (font units).
        var min_x: f32 = std.math.floatMax(f32);
        var min_y: f32 = std.math.floatMax(f32);
        var max_x: f32 = -std.math.floatMax(f32);
        var max_y: f32 = -std.math.floatMax(f32);
        for (edges.items) |edge| {
            min_x = @min(min_x, @min(edge.start_x, edge.end_x));
            min_y = @min(min_y, @min(edge.start_y, edge.end_y));
            max_x = @max(max_x, @max(edge.start_x, edge.end_x));
            max_y = @max(max_y, @max(edge.start_y, edge.end_y));
        }

        // A bitmap past `max_bitmap_side` (and any bound past i32) draws empty.
        const left_bound = @floor(min_x * scale);
        const bottom_bound = @floor(min_y * scale);
        const right_bound = @ceil(max_x * scale);
        const top_bound = @ceil(max_y * scale);
        if (!(right_bound - left_bound <= max_bitmap_side) or !(top_bound - bottom_bound <= max_bitmap_side)) return empty;
        const i32_limit: f32 = 1 << 30;
        if (!(@abs(left_bound) < i32_limit and @abs(bottom_bound) < i32_limit and @abs(right_bound) < i32_limit and @abs(top_bound) < i32_limit)) return empty;

        const left: i32 = @intFromFloat(left_bound);
        const bottom: i32 = @intFromFloat(bottom_bound);
        const right: i32 = @intFromFloat(right_bound);
        const top: i32 = @intFromFloat(top_bound);
        const width: u32 = @intCast(@max(right - left, 1));
        const height: u32 = @intCast(@max(top - bottom, 1));

        const bitmap = try allocator.alloc(u8, @as(usize, width) * height);
        errdefer allocator.free(bitmap);
        @memset(bitmap, 0);

        // Transform edges into bitmap pixel space (y flipped: font up → row down).
        const left_float: f32 = @floatFromInt(left);
        const top_float: f32 = @floatFromInt(top);
        for (edges.items) |*edge| {
            edge.start_x = edge.start_x * scale - left_float;
            edge.start_y = top_float - edge.start_y * scale;
            edge.end_x = edge.end_x * scale - left_float;
            edge.end_y = top_float - edge.end_y * scale;
        }

        const scanner = CoverageScanner{ .edges = edges.items, .allocator = allocator };
        try scanner.rasterize(bitmap, width, height);

        return .{
            .width = width,
            .height = height,
            .data = bitmap,
            .left = left,
            .top = top,
            .advance = advance,
        };
    }

    /// The first usable Unicode `cmap` subtable (format 12 preferred, else 4),
    /// checked to fit inside the `cmap` table (`reader` ends with it).
    fn findCmapSubtable(reader: *const BigEndianReader, cmap: TableRange) TtfParseError!CmapSubtable {
        const record_count = try reader.readU16(cmap.offset + 2);
        var best: ?CmapSubtable = null;
        var record_index: usize = 0;
        while (record_index < record_count) : (record_index += 1) {
            const record = cmap.offset + 4 + record_index * 8;
            const platform = try reader.readU16(record);
            const encoding = try reader.readU16(record + 2);
            const is_unicode = (platform == 0) or
                (platform == 3 and (encoding == 1 or encoding == 10));
            if (!is_unicode) continue;
            const relative_offset = try reader.readU32(record + 4);
            if (relative_offset >= cmap.length) return error.InvalidFont;
            const subtable_offset = cmap.offset + relative_offset;
            const format = try reader.readU16(subtable_offset);
            if (format == 12) {
                try Self.checkFormat12(reader, subtable_offset);
                return .{ .offset = subtable_offset, .format = 12 }; // prefer full
            }
            if (format == 4 and best == null) best = .{ .offset = subtable_offset, .format = 4 };
        }
        const subtable = best orelse return error.UnsupportedFormat;
        try Self.checkFormat4(reader, subtable.offset);
        return subtable;
    }

    /// Fail unless a format-4 subtable's segment arrays fit in the reader.
    fn checkFormat4(reader: *const BigEndianReader, base: usize) FontReadError!void {
        const segment_count_x2 = try reader.readU16(base + 6);
        if (segment_count_x2 == 0 or segment_count_x2 % 2 != 0) return error.InvalidFont;
        // header (14) + endCode + reservedPad (2) + startCode + idDelta + idRangeOffset
        try reader.require(base, 16 + 4 * @as(usize, segment_count_x2));
    }

    /// Fail unless a format-12 subtable's groups fit in the reader.
    fn checkFormat12(reader: *const BigEndianReader, base: usize) FontReadError!void {
        try reader.require(base, 16);
        const group_count = try reader.readU32(base + 12);
        if (group_count > (reader.data.len - base - 16) / 12) return error.InvalidFont;
    }

    /// Look a codepoint up in a format-4 (segmented BMP) subtable: the first
    /// segment whose end code is at or past it (segments are sorted by end
    /// code). The result is the raw glyph id, unchecked against `glyph_count`.
    fn cmapFormat4(self: *const Self, reader: *const BigEndianReader, codepoint: u21) FontReadError!u16 {
        if (codepoint > 0xFFFF) return 0;
        const code: u16 = @intCast(codepoint);
        const base = self.cmap_subtable_offset;
        const segment_count_x2: usize = try reader.readU16(base + 6);
        const segment_count = segment_count_x2 / 2;
        const end_codes = base + 14;
        const start_codes = end_codes + segment_count_x2 + 2; // +2 reservedPad
        const id_deltas = start_codes + segment_count_x2;
        const id_ranges = id_deltas + segment_count_x2;

        var low: usize = 0;
        var high: usize = segment_count;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (try reader.readU16(end_codes + middle * 2) < code) low = middle + 1 else high = middle;
        }
        if (low == segment_count) return 0;
        const segment = low;
        const start_code = try reader.readU16(start_codes + segment * 2);
        if (code < start_code) return 0;
        // idDelta arithmetic is modulo 65536.
        const id_delta: u16 = @bitCast(try reader.readI16(id_deltas + segment * 2));
        const id_range = try reader.readU16(id_ranges + segment * 2);
        if (id_range == 0) return code +% id_delta;
        const glyph_address = id_ranges + segment * 2 + id_range + @as(usize, code - start_code) * 2;
        const glyph = try reader.readU16(glyph_address);
        if (glyph == 0) return 0;
        return glyph +% id_delta;
    }

    /// Look a codepoint up in a format-12 (segmented coverage) subtable: the
    /// group holding it (groups are sorted and do not overlap). The result is
    /// the raw glyph id, unchecked against `glyph_count`.
    fn cmapFormat12(self: *const Self, reader: *const BigEndianReader, codepoint: u21) FontReadError!u32 {
        const base = self.cmap_subtable_offset;
        const group_count: usize = try reader.readU32(base + 12);
        var low: usize = 0;
        var high: usize = group_count;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (try reader.readU32(base + 16 + middle * 12 + 4) < codepoint) low = middle + 1 else high = middle;
        }
        if (low == group_count) return 0;
        const group = base + 16 + low * 12;
        const start_char = try reader.readU32(group);
        if (codepoint < start_char) return 0;
        const start_glyph = try reader.readU32(group + 8);
        const glyph = @as(u64, start_glyph) + (codepoint - start_char);
        return std.math.cast(u32, glyph) orelse 0;
    }

    /// A glyph's byte range in `glyf`, or null for an empty glyph; fails for a
    /// glyph past `glyph_count` or `loca` entries out of order or past `glyf`.
    fn glyfRange(self: *const Self, glyph: u16) FontReadError!?GlyfRange {
        if (glyph >= self.glyph_count) return error.InvalidFont;
        const reader = BigEndianReader{ .data = self.data };
        const index: usize = glyph;
        const start: usize, const end: usize = if (self.long_loca) .{
            try reader.readU32(self.loca_offset + index * 4),
            try reader.readU32(self.loca_offset + (index + 1) * 4),
        } else .{
            @as(usize, try reader.readU16(self.loca_offset + index * 2)) * 2,
            @as(usize, try reader.readU16(self.loca_offset + (index + 1) * 2)) * 2,
        };
        if (end < start or end > self.glyf_length) return error.InvalidFont;
        if (end == start) return null; // empty glyph (e.g. space)
        return .{ .start = self.glyf_offset + start, .end = self.glyf_offset + end };
    }

    /// Append a glyph's outline edges, recursing into composite components.
    fn collectEdges(self: *const Self, allocator: std.mem.Allocator, glyph: u16, edges: *std.ArrayList(Edge), transform: Transform, depth: u8, budget: *OutlineBudget) OutlineError!void {
        if (depth > max_composite_depth) return; // guard against pathological recursion
        const range = try self.glyfRange(glyph) orelse return;
        // Reads stop at the glyph's end.
        const reader = BigEndianReader{ .data = self.data[0..range.end] };
        const contour_count = try reader.readI16(range.start);
        if (contour_count >= 0) {
            try Self.simpleGlyphEdges(allocator, &reader, range.start, @intCast(contour_count), edges, transform);
        } else {
            try self.compositeGlyphEdges(allocator, &reader, glyph, range.start, edges, transform, depth, budget);
        }
    }

    /// Append a simple glyph's edges. `endPtsOfContours` must increase, and
    /// flags and coordinates must lie inside the glyph (`reader` ends with it).
    fn simpleGlyphEdges(allocator: std.mem.Allocator, reader: *const BigEndianReader, glyph_start: usize, contour_count: u16, edges: *std.ArrayList(Edge), transform: Transform) OutlineError!void {
        var position = glyph_start + 10; // skip numContours(2) + bbox(8)
        const end_points_offset = position;
        var last_end_point: i32 = -1;
        for (0..contour_count) |contour| {
            const end_point = try reader.readU16(end_points_offset + contour * 2);
            if (end_point <= last_end_point) return error.InvalidFont;
            last_end_point = end_point;
        }
        const point_count: usize = @intCast(last_end_point + 1);
        position += @as(usize, contour_count) * 2;
        const instruction_length = try reader.readU16(position);
        position += 2 + @as(usize, instruction_length);

        // Read flags (with repeat).
        var flags = try allocator.alloc(u8, point_count);
        defer allocator.free(flags);
        {
            var index: usize = 0;
            while (index < point_count) {
                const flag = try reader.byteAt(position);
                position += 1;
                flags[index] = flag;
                index += 1;
                if (flag & 0x08 != 0) { // REPEAT
                    var repeat = try reader.byteAt(position);
                    position += 1;
                    while (repeat > 0 and index < point_count) : (repeat -= 1) {
                        flags[index] = flag;
                        index += 1;
                    }
                }
            }
        }

        // Read x coords (delta-encoded).
        const x_coordinates = try allocator.alloc(f32, point_count);
        defer allocator.free(x_coordinates);
        var x: i32 = 0;
        for (0..point_count) |index| {
            const flag = flags[index];
            if (flag & 0x02 != 0) { // X_SHORT
                const delta_x: i32 = try reader.byteAt(position);
                position += 1;
                x += if (flag & 0x10 != 0) delta_x else -delta_x;
            } else if (flag & 0x10 == 0) { // not SAME -> i16 delta
                x += try reader.readI16(position);
                position += 2;
            }
            x_coordinates[index] = @floatFromInt(x);
        }
        // Read y coords.
        const y_coordinates = try allocator.alloc(f32, point_count);
        defer allocator.free(y_coordinates);
        var y: i32 = 0;
        for (0..point_count) |index| {
            const flag = flags[index];
            if (flag & 0x04 != 0) { // Y_SHORT
                const delta_y: i32 = try reader.byteAt(position);
                position += 1;
                y += if (flag & 0x20 != 0) delta_y else -delta_y;
            } else if (flag & 0x20 == 0) {
                y += try reader.readI16(position);
                position += 2;
            }
            y_coordinates[index] = @floatFromInt(y);
        }

        // Emit edges per contour (end points checked increasing above).
        const emitter = ContourEmitter{ .allocator = allocator, .edges = edges, .transform = transform };
        var start: usize = 0;
        for (0..contour_count) |contour| {
            const last: usize = try reader.readU16(end_points_offset + contour * 2);
            try emitter.emitContour(x_coordinates[start .. last + 1], y_coordinates[start .. last + 1], flags[start .. last + 1]);
            start = last + 1;
        }
    }

    /// Append a composite glyph's components' edges. A component must be
    /// another glyph of the face, and the components (at every depth) must
    /// stay within the glyph's `budget`.
    fn compositeGlyphEdges(self: *const Self, allocator: std.mem.Allocator, reader: *const BigEndianReader, glyph: u16, glyph_start: usize, edges: *std.ArrayList(Edge), transform: Transform, depth: u8, budget: *OutlineBudget) OutlineError!void {
        var position = glyph_start + 10;
        while (true) {
            const flags = try reader.readU16(position);
            const component_glyph = try reader.readU16(position + 2);
            if (component_glyph == glyph or component_glyph >= self.glyph_count) return error.InvalidFont;
            try budget.takeComponent();
            position += 4;
            var delta_x: f32 = 0;
            var delta_y: f32 = 0;
            if (flags & 0x0001 != 0) { // ARG_1_AND_2_ARE_WORDS
                if (flags & 0x0002 != 0) { // ARGS_ARE_XY_VALUES
                    delta_x = @floatFromInt(try reader.readI16(position));
                    delta_y = @floatFromInt(try reader.readI16(position + 2));
                }
                position += 4;
            } else {
                if (flags & 0x0002 != 0) {
                    delta_x = @floatFromInt(@as(i8, @bitCast(try reader.byteAt(position))));
                    delta_y = @floatFromInt(@as(i8, @bitCast(try reader.byteAt(position + 1))));
                }
                position += 2;
            }
            var scale_x: f32 = 1;
            var skew_y: f32 = 0;
            var skew_x: f32 = 0;
            var scale_y: f32 = 1;
            if (flags & 0x0008 != 0) { // WE_HAVE_A_SCALE
                scale_x = try reader.readF2Dot14(position);
                scale_y = scale_x;
                position += 2;
            } else if (flags & 0x0040 != 0) { // X_AND_Y_SCALE
                scale_x = try reader.readF2Dot14(position);
                scale_y = try reader.readF2Dot14(position + 2);
                position += 4;
            } else if (flags & 0x0080 != 0) { // TWO_BY_TWO
                scale_x = try reader.readF2Dot14(position);
                skew_y = try reader.readF2Dot14(position + 2);
                skew_x = try reader.readF2Dot14(position + 4);
                scale_y = try reader.readF2Dot14(position + 6);
                position += 8;
            }
            const component_transform = transform.compose(.{
                .scale_x = scale_x,
                .skew_y = skew_y,
                .skew_x = skew_x,
                .scale_y = scale_y,
                .translate_x = delta_x,
                .translate_y = delta_y,
            });
            try self.collectEdges(allocator, component_glyph, edges, component_transform, depth + 1, budget);
            if (flags & 0x0020 == 0) break; // no MORE_COMPONENTS
        }
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// Test helpers.
const TestGlyphs = struct {
    const Self = @This();

    /// The sum of a glyph's coverage.
    fn coverageSum(glyph: mod.RasterGlyph) u64 {
        var sum: u64 = 0;
        for (glyph.data) |value| sum += value;
        return sum;
    }
};

/// A stand-in external face: maps 'あ' to glyph 7, 1000 units per em, a 2x3 ink block.
const FakeExternal = struct {
    const Self = @This();

    fn fakeGlyph(_: *const anyopaque, codepoint: u21) u16 {
        return if (codepoint == 0x3042) 7 else 0;
    }

    fn fakeAdvance(_: *const anyopaque, glyph: u16) u16 {
        return if (glyph == 7) 1000 else 0;
    }

    fn fakeRasterize(_: *const anyopaque, allocator: std.mem.Allocator, glyph: u16, scale: f32) std.mem.Allocator.Error!mod.RasterGlyph {
        const data = try allocator.alloc(u8, 6);
        @memset(data, 255);
        return .{ .width = 2, .height = 3, .data = data, .left = 1, .top = 3, .advance = @as(f32, @floatFromInt(FakeExternal.fakeAdvance(undefined, glyph))) * scale };
    }

    const external = mod.ExternalFace{ .context = undefined, .glyph_index = FakeExternal.fakeGlyph, .advance_width = FakeExternal.fakeAdvance, .rasterize = FakeExternal.fakeRasterize };
};

/// What `TestFontBuilder.build` puts in a font. Glyph 0 is empty, glyph 1 is a
/// composite of `component_count` references to `component_glyph` followed by
/// glyph 2, and glyph 2 is a triangle reaching `extent`; 'A' maps to glyph 2
/// through `cmap_delta`.
const TestFontOptions = struct {
    const Self = @This();

    /// `head.unitsPerEm`.
    units_per_em: u16 = 1000,
    /// How many glyphs `loca` holds (and `maxp` declares, unless overridden).
    glyph_count: u16 = 3,
    /// What `maxp` declares instead of `glyph_count`, when set.
    declared_glyph_count: ?u16 = null,
    /// `hhea.numberOfHMetrics` (each metric is written to `hmtx`).
    metric_count: u16 = 1,
    /// The composite's references before its final one to glyph 2.
    component_count: usize = 0,
    /// The glyph those references point at.
    component_glyph: u16 = 2,
    /// The triangle's size in font units.
    extent: i16 = 100,
    /// The triangle's `endPtsOfContours`.
    end_points: []const u16 = &.{2},
    /// The 'A' segment's `idDelta`.
    cmap_delta: i16 = 2 - 0x41,
};

/// Builds small TrueType fonts, well-formed or deliberately broken.
const TestFontBuilder = struct {
    const Self = @This();

    /// The tables, in directory order.
    const tags = [_]*const [4]u8{ "cmap", "glyf", "head", "hhea", "hmtx", "loca", "maxp" };

    /// The allocator the bytes grow with.
    allocator: std.mem.Allocator,
    /// The font built so far.
    bytes: std.ArrayList(u8) = .empty,

    /// An empty builder.
    fn init(allocator: std.mem.Allocator) Self {
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Free the bytes.
    fn deinit(self: *Self) void {
        self.bytes.deinit(self.allocator);
    }

    /// Build a font from `options`; the bytes live until `deinit`.
    fn build(self: *Self, options: TestFontOptions) ![]u8 {
        self.bytes.clearRetainingCapacity();
        try self.writeU32(0x00010000);
        try self.writeU16(tags.len);
        try self.writeZeros(6);
        const directory = self.bytes.items.len;
        try self.writeZeros(tags.len * 16);
        var offsets: [tags.len]usize = undefined;

        // cmap: one Unicode BMP format-4 subtable with 'A' and the 0xFFFF end segment.
        offsets[0] = self.bytes.items.len;
        for ([_]u16{ 0, 1, 3, 1 }) |value| try self.writeU16(value);
        try self.writeU32(12);
        for ([_]u16{ 4, 32, 0, 4 }) |value| try self.writeU16(value);
        try self.writeZeros(6);
        for ([_]u16{ 0x41, 0xFFFF, 0, 0x41, 0xFFFF }) |value| try self.writeU16(value);
        try self.writeI16(options.cmap_delta);
        try self.writeI16(1);
        try self.writeZeros(4);

        // glyf: glyph 1 (composite), then glyph 2 (triangle).
        offsets[1] = self.bytes.items.len;
        const composite_start = self.bytes.items.len - offsets[1];
        try self.writeI16(-1);
        try self.writeZeros(8);
        for (0..options.component_count) |_| {
            try self.writeU16(0x0020 | 0x0002);
            try self.writeU16(options.component_glyph);
            try self.writeZeros(2);
        }
        try self.writeU16(0x0002);
        try self.writeU16(2);
        try self.writeZeros(2);
        const triangle_start = self.bytes.items.len - offsets[1];
        try self.writeI16(@intCast(options.end_points.len));
        try self.writeZeros(8);
        for (options.end_points) |end_point| try self.writeU16(end_point);
        try self.writeU16(0);
        try self.bytes.appendSlice(self.allocator, &.{ 1, 1, 1 });
        for ([_]i16{ 0, options.extent, -options.extent, 0, 0, options.extent }) |value| try self.writeI16(value);
        const glyf_end = self.bytes.items.len - offsets[1];
        if (self.bytes.items.len % 2 == 1) try self.writeZeros(1);

        // head: unitsPerEm and long loca.
        offsets[2] = self.bytes.items.len;
        try self.writeZeros(54);
        self.patchU16(offsets[2] + 18, options.units_per_em);
        self.patchU16(offsets[2] + 50, 1);

        // hhea: ascent, descent, numberOfHMetrics.
        offsets[3] = self.bytes.items.len;
        try self.writeZeros(36);
        self.patchU16(offsets[3] + 4, 800);
        self.patchU16(offsets[3] + 6, @bitCast(@as(i16, -200)));
        self.patchU16(offsets[3] + 34, options.metric_count);

        // hmtx: every metric advances 500.
        offsets[4] = self.bytes.items.len;
        for (0..options.metric_count) |_| {
            try self.writeU16(500);
            try self.writeU16(0);
        }

        // loca (long): glyph 0 empty, 1 composite, 2 triangle, the rest empty.
        offsets[5] = self.bytes.items.len;
        for (0..@as(usize, options.glyph_count) + 1) |index| {
            const offset: usize = if (index <= 1) composite_start else if (index == 2) triangle_start else glyf_end;
            try self.writeU32(@intCast(offset));
        }

        // maxp.
        offsets[6] = self.bytes.items.len;
        try self.writeU32(0x00005000);
        try self.writeU16(options.declared_glyph_count orelse options.glyph_count);
        const end = self.bytes.items.len;

        for (tags, 0..) |tag, index| {
            const record = directory + index * 16;
            @memcpy(self.bytes.items[record..][0..4], tag);
            const table_end = if (index + 1 < tags.len) offsets[index + 1] else end;
            self.patchU32(record + 8, @intCast(offsets[index]));
            self.patchU32(record + 12, @intCast(table_end - offsets[index]));
        }
        return self.bytes.items;
    }

    /// Append a big-endian u16.
    fn writeU16(self: *Self, value: u16) !void {
        var buffer: [2]u8 = undefined;
        std.mem.writeInt(u16, &buffer, value, .big);
        try self.bytes.appendSlice(self.allocator, &buffer);
    }

    /// Append a big-endian i16.
    fn writeI16(self: *Self, value: i16) !void {
        try self.writeU16(@bitCast(value));
    }

    /// Append a big-endian u32.
    fn writeU32(self: *Self, value: u32) !void {
        var buffer: [4]u8 = undefined;
        std.mem.writeInt(u32, &buffer, value, .big);
        try self.bytes.appendSlice(self.allocator, &buffer);
    }

    /// Append `count` zero bytes.
    fn writeZeros(self: *Self, count: usize) !void {
        try self.bytes.appendNTimes(self.allocator, 0, count);
    }

    /// Overwrite the big-endian u16 at `offset`.
    fn patchU16(self: *Self, offset: usize, value: u16) void {
        std.mem.writeInt(u16, self.bytes.items[offset..][0..2], value, .big);
    }

    /// Overwrite the big-endian u32 at `offset`.
    fn patchU32(self: *Self, offset: usize, value: u32) void {
        std.mem.writeInt(u32, self.bytes.items[offset..][0..4], value, .big);
    }
};

/// The rasterizer before its scanline sweep: every sample tests every edge.
/// The tests check the sweep against it bit for bit.
const TestReferenceScanner = struct {
    const Self = @This();

    /// The glyph's edges in bitmap pixel space.
    edges: []const Edge,

    /// Fill `bitmap` (`width` x `height`) with the edges' coverage.
    fn rasterize(self: *const Self, bitmap: []u8, width: u32, height: u32) void {
        const samples: u32 = 4;
        const samples_float: f32 = @floatFromInt(samples);
        const inverse_samples: f32 = 1.0 / @as(f32, @floatFromInt(samples * samples));
        var pixel_y: u32 = 0;
        while (pixel_y < height) : (pixel_y += 1) {
            var pixel_x: u32 = 0;
            while (pixel_x < width) : (pixel_x += 1) {
                var inside_count: u32 = 0;
                var sample_y: u32 = 0;
                while (sample_y < samples) : (sample_y += 1) {
                    const float_y = @as(f32, @floatFromInt(pixel_y)) + (@as(f32, @floatFromInt(sample_y)) + 0.5) / samples_float;
                    var sample_x: u32 = 0;
                    while (sample_x < samples) : (sample_x += 1) {
                        const float_x = @as(f32, @floatFromInt(pixel_x)) + (@as(f32, @floatFromInt(sample_x)) + 0.5) / samples_float;
                        if (self.windingInside(float_x, float_y)) inside_count += 1;
                    }
                }
                const coverage = @as(f32, @floatFromInt(inside_count)) * inverse_samples;
                bitmap[pixel_y * width + pixel_x] = @intFromFloat(@round(coverage * 255.0));
            }
        }
    }

    /// Whether a sample point is inside the outline (nonzero winding).
    fn windingInside(self: *const Self, sample_x: f32, sample_y: f32) bool {
        var winding: i32 = 0;
        for (self.edges) |edge| {
            if (edge.start_y <= sample_y and edge.end_y > sample_y) {
                const fraction = (sample_y - edge.start_y) / (edge.end_y - edge.start_y);
                const intersect_x = edge.start_x + fraction * (edge.end_x - edge.start_x);
                if (intersect_x > sample_x) winding += 1;
            } else if (edge.end_y <= sample_y and edge.start_y > sample_y) {
                const fraction = (sample_y - edge.start_y) / (edge.end_y - edge.start_y);
                const intersect_x = edge.start_x + fraction * (edge.end_x - edge.start_x);
                if (intersect_x > sample_x) winding -= 1;
            }
        }
        return winding != 0;
    }

    /// Rasterize `glyph` of `font` at `pixel_size` with both scanners and
    /// fail unless the bitmaps match byte for byte.
    fn expectSameCoverage(font: *const TtfFont, glyph: u16, pixel_size: f32) !void {
        const allocator = std.testing.allocator;
        const scale = font.scaleForPixelSize(pixel_size);
        const raster = try font.rasterizeGlyph(allocator, glyph, scale);
        defer raster.deinit(allocator);
        var edges: std.ArrayList(Edge) = .empty;
        defer edges.deinit(allocator);
        var budget = OutlineBudget{};
        try font.collectEdges(allocator, glyph, &edges, Transform.identity, 0, &budget);
        if (raster.width == 0) return std.testing.expectEqual(@as(usize, 0), edges.items.len);
        const left_float: f32 = @floatFromInt(raster.left);
        const top_float: f32 = @floatFromInt(raster.top);
        for (edges.items) |*edge| {
            edge.start_x = edge.start_x * scale - left_float;
            edge.start_y = top_float - edge.start_y * scale;
            edge.end_x = edge.end_x * scale - left_float;
            edge.end_y = top_float - edge.end_y * scale;
        }
        const expected = try allocator.alloc(u8, raster.data.len);
        defer allocator.free(expected);
        @memset(expected, 0);
        const reference = Self{ .edges = edges.items };
        reference.rasterize(expected, raster.width, raster.height);
        try std.testing.expectEqualSlices(u8, expected, raster.data);
    }
};

/// The `cmap` lookups before binary search: a linear scan. The tests check the
/// binary search against it.
const TestLinearCmap = struct {
    const Self = @This();

    /// The glyph a linear scan of `font`'s `cmap` subtable maps `codepoint` to.
    fn lookup(font: *const TtfFont, codepoint: u21) !u32 {
        const reader = BigEndianReader{ .data = font.data[0..font.cmap_end] };
        const base = font.cmap_subtable_offset;
        if (font.cmap_format == 12) {
            const group_count = try reader.readU32(base + 12);
            for (0..group_count) |group_index| {
                const group = base + 16 + group_index * 12;
                const start_char = try reader.readU32(group);
                const end_char = try reader.readU32(group + 4);
                if (codepoint >= start_char and codepoint <= end_char) return try reader.readU32(group + 8) + (codepoint - start_char);
            }
            return 0;
        }
        if (codepoint > 0xFFFF) return 0;
        const code: u16 = @intCast(codepoint);
        const segment_count_x2: usize = try reader.readU16(base + 6);
        const end_codes = base + 14;
        const start_codes = end_codes + segment_count_x2 + 2;
        const id_deltas = start_codes + segment_count_x2;
        const id_ranges = id_deltas + segment_count_x2;
        for (0..segment_count_x2 / 2) |segment| {
            if (code > try reader.readU16(end_codes + segment * 2)) continue;
            const start_code = try reader.readU16(start_codes + segment * 2);
            if (code < start_code) return 0;
            const id_delta: u16 = @bitCast(try reader.readI16(id_deltas + segment * 2));
            const id_range = try reader.readU16(id_ranges + segment * 2);
            if (id_range == 0) return code +% id_delta;
            const glyph = try reader.readU16(id_ranges + segment * 2 + id_range + @as(usize, code - start_code) * 2);
            return if (glyph == 0) 0 else glyph +% id_delta;
        }
        return 0;
    }
};

/// The bundled font blobs.
const TestBundledFonts = struct {
    const Self = @This();

    /// Every face the renderer embeds.
    const blobs = [_][]const u8{
        TtfFont.inter_ttf,
        TtfFont.icon_ttf,
        TtfFont.emoji_ttf,
        @embedFile("inter_medium"),
        @embedFile("inter_semibold"),
        @embedFile("inter_bold"),
        @embedFile("inter_italic"),
        @embedFile("inter_bold_italic"),
        @embedFile("mono_regular"),
        @embedFile("mono_bold"),
    };
};

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "ttf: parse Inter header" {
    const font = try TtfFont.parse(TtfFont.inter_ttf);
    try std.testing.expect(font.units_per_em >= 1000);
    try std.testing.expect(font.glyph_count > 100);
    try std.testing.expect(font.ascent > 0);
}

test "ttf: emoji font parses and resolves via fallback chain" {
    const inter = try TtfFont.parse(TtfFont.inter_ttf);
    var emoji = try TtfFont.parse(TtfFont.emoji_ttf);
    // The bundled emoji font carries a real glyph for U+1F600 (😀)…
    try std.testing.expect(emoji.glyphIndex(0x1F600) != 0);
    // …which Inter lacks, so resolve falls through to it.
    try std.testing.expect(inter.glyphIndex(0x1F600) == 0);

    var primary = inter;
    primary.fallback = &emoji;
    const resolved = primary.resolve(0x1F600);
    try std.testing.expect(resolved.face == &emoji);
    try std.testing.expect(resolved.glyph == emoji.glyphIndex(0x1F600));
    // ASCII still resolves to the primary face.
    const letter = primary.resolve('A');
    try std.testing.expect(letter.face == &primary);
    try std.testing.expect(letter.glyph == inter.glyphIndex('A'));
    // A rasterized emoji glyph actually inks pixels.
    const scale = emoji.scaleForPixelSize(48);
    const glyph = try emoji.rasterizeGlyph(std.testing.allocator, resolved.glyph, scale);
    defer glyph.deinit(std.testing.allocator);
    try std.testing.expect(glyph.width > 5 and glyph.height > 5);
    try std.testing.expect(TestGlyphs.coverageSum(glyph) > 0);
}

test "ttf: a codepoint past the emoji face resolves to an external face, which metrics and rasterizes it" {
    var inter = try TtfFont.parse(TtfFont.inter_ttf);
    var emoji = try TtfFont.parse(TtfFont.emoji_ttf);
    const cjk = TtfFont.fromExternal(&FakeExternal.external, 1000, 880, -120, 0);
    inter.fallback = &emoji;
    emoji.fallback = &cjk;

    const resolved = inter.resolve(0x3042);
    try std.testing.expect(resolved.face == &cjk);
    try std.testing.expectEqual(@as(u16, 7), resolved.glyph);
    try std.testing.expectEqual(@as(u16, 1000), resolved.face.advanceWidth(resolved.glyph));
    const glyph = try resolved.face.rasterizeGlyph(std.testing.allocator, resolved.glyph, resolved.face.scaleForPixelSize(20));
    defer glyph.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 2), glyph.width);
    try std.testing.expectEqual(@as(f32, 20), glyph.advance);
    // A codepoint nobody has stays the primary face's .notdef.
    const miss = inter.resolve(0x10FFFF);
    try std.testing.expect(miss.face == &inter and miss.glyph == 0);
}

test "ttf: cmap maps ASCII letters to nonzero glyphs" {
    const font = try TtfFont.parse(TtfFont.inter_ttf);
    try std.testing.expect(font.glyphIndex('A') != 0);
    try std.testing.expect(font.glyphIndex('g') != 0);
    try std.testing.expect(font.glyphIndex('0') != 0);
    // 'A' and 'B' map to distinct glyphs
    try std.testing.expect(font.glyphIndex('A') != font.glyphIndex('B'));
}

test "ttf: advance widths are positive and proportional" {
    const font = try TtfFont.parse(TtfFont.inter_ttf);
    const narrow = font.advanceWidth(font.glyphIndex('i'));
    const wide = font.advanceWidth(font.glyphIndex('M'));
    try std.testing.expect(narrow > 0 and wide > 0);
    try std.testing.expect(wide > narrow); // 'M' is wider than 'i'
}

test "ttf: rasterize 'A' produces a non-empty inked bitmap" {
    const font = try TtfFont.parse(TtfFont.inter_ttf);
    const scale = font.scaleForPixelSize(48);
    const glyph = try font.rasterizeGlyph(std.testing.allocator, font.glyphIndex('A'), scale);
    defer glyph.deinit(std.testing.allocator);
    try std.testing.expect(glyph.width > 5 and glyph.height > 5);
    try std.testing.expect(TestGlyphs.coverageSum(glyph) > 0); // some pixels inked
    // 'A' top should be above the baseline
    try std.testing.expect(glyph.top > 0);
}

test "ttf: space glyph has zero ink but positive advance" {
    const font = try TtfFont.parse(TtfFont.inter_ttf);
    const scale = font.scaleForPixelSize(48);
    const glyph = try font.rasterizeGlyph(std.testing.allocator, font.glyphIndex(' '), scale);
    defer glyph.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 0), TestGlyphs.coverageSum(glyph));
    try std.testing.expect(glyph.advance > 0);
}

test "ttf: unmapped codepoint returns glyph 0" {
    const font = try TtfFont.parse(TtfFont.inter_ttf);
    // a Plane-1 codepoint Inter almost certainly lacks
    try std.testing.expectEqual(@as(u16, 0), font.glyphIndex(0x10FFFF));
}

test "ttf: rejects non-TrueType data" {
    var junk: [16]u8 = @splat(0);
    junk[0] = 'O';
    junk[1] = 'T';
    junk[2] = 'T';
    junk[3] = 'O';
    try std.testing.expectError(error.UnsupportedFormat, TtfFont.parse(&junk));
}

test "ttf: a built font parses, maps 'A' and rasterizes its triangle and composite" {
    var builder = TestFontBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const font = try TtfFont.parse(try builder.build(.{}));
    try std.testing.expectEqual(@as(u16, 2), font.glyphIndex('A'));
    try std.testing.expectEqual(@as(u16, 500), font.advanceWidth(2));
    const scale = font.scaleForPixelSize(14);
    const triangle = try font.rasterizeGlyph(std.testing.allocator, 2, scale);
    defer triangle.deinit(std.testing.allocator);
    try std.testing.expect(TestGlyphs.coverageSum(triangle) > 0);
    const composite = try font.rasterizeGlyph(std.testing.allocator, 1, scale);
    defer composite.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, triangle.data, composite.data);
}

test "ttf: a table past the end of the blob, or any truncation, fails without reading out of range" {
    var builder = TestFontBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const bytes = try builder.build(.{});
    // maxp is the last table: cutting its last bytes leaves it past the end.
    try std.testing.expectError(error.InvalidFont, TtfFont.parse(bytes[0 .. bytes.len - 6]));
    for (0..bytes.len) |length| {
        const font = TtfFont.parse(bytes[0..length]) catch continue;
        _ = font.glyphIndex('A');
    }
}

test "ttf: header fields out of range are rejected" {
    var builder = TestFontBuilder.init(std.testing.allocator);
    defer builder.deinit();
    for ([_]u16{ 0, 1, 15, 16385 }) |units_per_em| {
        try std.testing.expectError(error.InvalidFont, TtfFont.parse(try builder.build(.{ .units_per_em = units_per_em })));
    }
    _ = try TtfFont.parse(try builder.build(.{ .units_per_em = 16 }));
    _ = try TtfFont.parse(try builder.build(.{ .units_per_em = 16384 }));
    // numberOfHMetrics 0 (hmtx then has no advance to fall back to).
    try std.testing.expectError(error.InvalidFont, TtfFont.parse(try builder.build(.{ .metric_count = 0 })));
    // maxp declares more glyphs than loca holds.
    try std.testing.expectError(error.InvalidFont, TtfFont.parse(try builder.build(.{ .declared_glyph_count = 50 })));
    // A face built by hand with no metrics advances nothing instead of reading hmtx[-1].
    var font = try TtfFont.parse(try builder.build(.{}));
    font.horizontal_metric_count = 0;
    try std.testing.expectEqual(@as(u16, 0), font.advanceWidth(2));
}

test "ttf: cmap format 4 idDelta wraps modulo 65536" {
    var builder = TestFontBuilder.init(std.testing.allocator);
    defer builder.deinit();
    // 'A' (0x41) + -0x50 is -15, which is 65521 modulo 65536.
    const font = try TtfFont.parse(try builder.build(.{ .cmap_delta = -0x50 }));
    const reader = BigEndianReader{ .data = font.data[0..font.cmap_end] };
    try std.testing.expectEqual(@as(u16, 65521), try font.cmapFormat4(&reader, 'A'));
    // A glyph the face lacks is missing.
    try std.testing.expectEqual(@as(u16, 0), font.glyphIndex('A'));
}

test "ttf: cmap binary search maps every codepoint as a linear scan does" {
    // Inter's weights share one cmap; JetBrains Mono's two do too.
    for ([_][]const u8{ TtfFont.inter_ttf, TtfFont.icon_ttf, TtfFont.emoji_ttf, @embedFile("mono_regular") }) |blob| {
        const font = try TtfFont.parse(blob);
        for ([_][2]u21{ .{ 0, 0x600 }, .{ 0x2000, 0x2800 }, .{ 0xE000, 0xE400 }, .{ 0xFFF0, 0x10010 }, .{ 0x1F300, 0x1F700 } }) |range| {
            var codepoint = range[0];
            while (codepoint < range[1]) : (codepoint += 1) {
                const linear = try TestLinearCmap.lookup(&font, codepoint);
                const expected: u16 = if (linear < font.glyph_count) @intCast(linear) else 0;
                try std.testing.expectEqual(expected, font.glyphIndex(codepoint));
            }
        }
    }
}

test "ttf: loca and hmtx offsets past glyph 16383 do not overflow" {
    var builder = TestFontBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const font = try TtfFont.parse(try builder.build(.{ .glyph_count = 20000, .metric_count = 20000 }));
    try std.testing.expectEqual(@as(u16, 500), font.advanceWidth(19999));
    const empty = try font.rasterizeGlyph(std.testing.allocator, 19999, font.scaleForPixelSize(14));
    defer empty.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0), empty.width);
    try std.testing.expectEqual(@as(f32, 7), empty.advance);
}

test "ttf: composite glyphs reject self-references and missing glyphs, and cap their components" {
    var builder = TestFontBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const scale: f32 = 14.0 / 1000.0;
    // Three more references to the triangle ink; a self-reference, a missing
    // glyph, or more components than the budget allows draw nothing.
    const options = [_]TestFontOptions{
        .{ .component_count = 3 },
        .{ .component_count = 1, .component_glyph = 1 },
        .{ .component_count = 1, .component_glyph = 7 },
        .{ .component_count = OutlineBudget.max_components + 1 },
    };
    for (options, [_]bool{ true, false, false, false }) |option, inked| {
        const font = try TtfFont.parse(try builder.build(option));
        const glyph = try font.rasterizeGlyph(std.testing.allocator, 1, scale);
        defer glyph.deinit(std.testing.allocator);
        try std.testing.expectEqual(inked, TestGlyphs.coverageSum(glyph) > 0);
    }
    // A glyph id past the face's glyphs rasterizes empty.
    const font = try TtfFont.parse(try builder.build(.{}));
    const missing = try font.rasterizeGlyph(std.testing.allocator, 3, scale);
    try std.testing.expectEqual(@as(u32, 0), missing.width);
}

test "ttf: contour end points out of order or past the glyph rasterize empty" {
    var builder = TestFontBuilder.init(std.testing.allocator);
    defer builder.deinit();
    for ([_][]const u16{ &.{ 2, 1 }, &.{ 1, 1, 2 }, &.{0xFFF0} }) |end_points| {
        const font = try TtfFont.parse(try builder.build(.{ .end_points = end_points }));
        const glyph = try font.rasterizeGlyph(std.testing.allocator, 2, font.scaleForPixelSize(14));
        try std.testing.expectEqual(@as(u32, 0), glyph.width);
        try std.testing.expectEqual(@as(f32, 7), glyph.advance);
    }
}

test "ttf: an oversized bitmap and a scale that is not positive and finite rasterize empty" {
    var builder = TestFontBuilder.init(std.testing.allocator);
    defer builder.deinit();
    // 32767 units at 16 per em and 14 px is about 28700 px square.
    const font = try TtfFont.parse(try builder.build(.{ .units_per_em = 16, .extent = 32767 }));
    const huge = try font.rasterizeGlyph(std.testing.allocator, 2, font.scaleForPixelSize(14));
    try std.testing.expectEqual(@as(u32, 0), huge.width);
    for ([_]f32{ 0, -1, std.math.nan(f32), std.math.inf(f32) }) |scale| {
        const glyph = try font.rasterizeGlyph(std.testing.allocator, 2, scale);
        try std.testing.expectEqual(@as(u32, 0), glyph.width);
    }
}

test "ttf: corrupted fonts parse or fail, and rasterize or draw empty, without reading out of range" {
    var builder = TestFontBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const pristine = try std.testing.allocator.dupe(u8, try builder.build(.{ .component_count = 2 }));
    defer std.testing.allocator.free(pristine);
    var prng = std.Random.DefaultPrng.init(0x7A16);
    const random = prng.random();
    for (0..2000) |_| {
        const bytes = builder.bytes.items;
        @memcpy(bytes, pristine);
        for (0..random.intRangeAtMost(usize, 1, 4)) |_| bytes[random.uintLessThan(usize, bytes.len)] = random.int(u8);
        const font = TtfFont.parse(bytes) catch continue;
        _ = font.resolve('A');
        _ = font.glyphIndex(0x10000);
        for (0..5) |glyph| {
            _ = font.advanceWidth(@intCast(glyph));
            const raster = try font.rasterizeGlyph(std.testing.allocator, @intCast(glyph), font.scaleForPixelSize(14));
            raster.deinit(std.testing.allocator);
        }
    }
}

test "ttf: every bundled glyph's outline is well formed and within the budget" {
    var edges: std.ArrayList(Edge) = .empty;
    defer edges.deinit(std.testing.allocator);
    // Every glyph of the first two faces, a sample of the rest (Debug is slow).
    for (TestBundledFonts.blobs, 0..) |blob, index| {
        const font = try TtfFont.parse(blob);
        const stride: u16 = if (index < 2) 1 else 13;
        var glyph: u16 = 0;
        while (glyph < font.glyph_count) : (glyph += stride) {
            edges.clearRetainingCapacity();
            var budget = OutlineBudget{};
            try font.collectEdges(std.testing.allocator, glyph, &edges, Transform.identity, 0, &budget);
        }
    }
}

test "ttf: the scanline sweep matches the per-sample reference bit for bit" {
    const inter = try TtfFont.parse(TtfFont.inter_ttf);
    var codepoint: u21 = 0x21;
    while (codepoint < 0x7F) : (codepoint += 1) {
        try TestReferenceScanner.expectSameCoverage(&inter, inter.glyphIndex(codepoint), 13);
    }
    for ("Ag@&%") |letter| {
        try TestReferenceScanner.expectSameCoverage(&inter, inter.glyphIndex(letter), 17.5);
        try TestReferenceScanner.expectSameCoverage(&inter, inter.glyphIndex(letter), 48);
    }
    const emoji = try TtfFont.parse(TtfFont.emoji_ttf);
    for ([_]u21{ 0x1F600, 0x1F680, 0x2764 }) |emoji_codepoint| {
        try TestReferenceScanner.expectSameCoverage(&emoji, emoji.glyphIndex(emoji_codepoint), 14);
        try TestReferenceScanner.expectSameCoverage(&emoji, emoji.glyphIndex(emoji_codepoint), 40);
    }
    const icons = try TtfFont.parse(TtfFont.icon_ttf);
    try TestReferenceScanner.expectSameCoverage(&icons, icons.glyphIndex(0xE0F2), 24);
}
