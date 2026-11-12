//! A cache of wrapped-text and rich-text layouts, so settled text is a lookup.

const std = @import("std");
const log = std.log.scoped(.ziggui_wrap_cache);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// One cached rich paragraph: its layout and the block its lines' runs live in.
const RichEntry = struct {
    const Self = @This();

    /// The layout, its lines pointing into `runs`.
    layout: mod.RichLayout,

    /// Every line's runs, in one block.
    runs: []mod.RichRun,
};

/// Word-wrapping is recomputed on every measure AND paint of every `WrappedText`,
/// so a long, mostly-static transcript re-wraps all its bubbles 60×/sec. This
/// cache keys the wrap result by (content, font size, width) so settled text is a
/// cheap lookup; only changing text (e.g. a streaming reply) actually re-wraps.
/// The app's render loop owns one and installs it with `BuildScope.setWrapCache`.
///
/// What it hands out stays valid through the next frame boundary: tap
/// regions built from a layout (`SelectHit.layout`, `TextClick.rows`) are
/// read between frames, so a full cache is never emptied mid-frame. At a
/// frame boundary (`beginFrame`, which `BuildScope.begin` calls) a full
/// generation is retired, and freed only at the boundary after, so taps a
/// nested frame (a live-resize redraw) outlives still read live memory.
pub const WrapCache = struct {
    const Self = @This();

    /// Cached wraps past which the next frame boundary retires them.
    const max_wraps: usize = 2048;

    /// Cached rich layouts past which the next frame boundary retires them.
    const max_rich: usize = 4096;

    /// The allocator the cached layouts come from.
    allocator: std.mem.Allocator,

    /// Wrapped lines, by `keyFor`.
    map: std.AutoHashMapUnmanaged(u64, []renderer.WrappedLine) = .empty,

    /// Rich-text (markdown) paragraph layouts, the bulk of a transcript's cost.
    rich: std.AutoHashMapUnmanaged(u64, RichEntry) = .empty,

    /// The wraps the last boundary retired: no longer looked up, freed at the next.
    retired_map: std.AutoHashMapUnmanaged(u64, []renderer.WrappedLine) = .empty,

    /// The rich layouts the last boundary retired, freed at the next.
    retired_rich: std.AutoHashMapUnmanaged(u64, RichEntry) = .empty,

    /// An empty cache.
    ///
    /// - `allocator`: where cached layouts are kept.
    /// - Returns: the cache.
    pub fn init(allocator: std.mem.Allocator) Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const self = Self{ .allocator = allocator };
        return self;
    }

    /// Frees every cached layout.
    ///
    /// - `self`: the cache.
    pub fn deinit(self: *Self) void {
        self.clear(&self.retired_map);
        self.clearRich(&self.retired_rich);
        self.clear(&self.map);
        self.clearRich(&self.rich);
        self.retired_map.deinit(self.allocator);
        self.retired_rich.deinit(self.allocator);
        self.map.deinit(self.allocator);
        self.rich.deinit(self.allocator);
    }

    /// Marks a frame boundary: frees what the last boundary retired, then
    /// retires the cache if it grew past its bound.
    ///
    /// - `self`: the cache.
    pub fn beginFrame(self: *Self) void {
        self.clear(&self.retired_map);
        self.clearRich(&self.retired_rich);
        if (self.map.count() > max_wraps) std.mem.swap(std.AutoHashMapUnmanaged(u64, []renderer.WrappedLine), &self.map, &self.retired_map);
        if (self.rich.count() > max_rich) std.mem.swap(std.AutoHashMapUnmanaged(u64, RichEntry), &self.rich, &self.retired_rich);
    }

    /// Wraps `text`, returning cached line offsets when available. The returned
    /// slice is valid until the next frame begins (cache-owned when cached,
    /// else `arena`-owned).
    ///
    /// - `self`: the cache.
    /// - `arena`: the frame arena, for a fallback when the cache cannot grow.
    /// - `face`: the face the text is measured in.
    /// - `text`: the text.
    /// - `pixel_size`: its size.
    /// - `max_width`: the width it wraps to.
    /// - Returns: the wrapped lines.
    pub fn wrap(self: *Self, arena: std.mem.Allocator, face: *const renderer.TtfFont, text: []const u8, pixel_size: f32, max_width: f32) []renderer.WrappedLine {
        const key = Self.keyFor(text, pixel_size, max_width);
        const slot = self.map.getOrPut(self.allocator, key) catch
            return renderer.TextShaper.init(face).wrapText(arena, text, pixel_size, max_width) catch &.{};
        if (slot.found_existing) {
            const lines = slot.value_ptr.*;
            // Guard against a (vanishingly rare) hash collision yielding offsets past
            // the current string: re-wrap in the arena rather than slice out of
            // bounds, and leave the entry, which this frame may already hold.
            if (lines.len == 0 or lines[lines.len - 1].end <= text.len) return lines;
            return renderer.TextShaper.init(face).wrapText(arena, text, pixel_size, max_width) catch &.{};
        }
        const lines = renderer.TextShaper.init(face).wrapText(self.allocator, text, pixel_size, max_width) catch {
            _ = self.map.remove(key);
            return renderer.TextShaper.init(face).wrapText(arena, text, pixel_size, max_width) catch &.{};
        };
        slot.value_ptr.* = lines;
        return lines;
    }

    /// Lays out a rich paragraph, from the cache when its text, the
    /// font-affecting style of every span, the size and the width all match.
    ///
    /// - `self`: the cache.
    /// - `arena`: the frame arena the layout is made in.
    /// - `spans`: the paragraph.
    /// - `faces`: the faces its spans are drawn in.
    /// - `pixel_size`: its base size.
    /// - `line_multiple`: line height as a multiple of the size.
    /// - `max_width`: the width it wraps to.
    /// - `preformatted`: preformatted (no wrapping).
    /// - Returns: the layout, valid until the next frame begins; propagates
    ///   allocation failure.
    pub fn layoutRich(self: *Self, arena: std.mem.Allocator, spans: []const mod.Span, faces: mod.RichFaces, pixel_size: f32, line_multiple: f32, max_width: f32, preformatted: bool) std.mem.Allocator.Error!mod.RichLayout {
        var hasher = std.hash.Wyhash.init(0x51c4);
        for (spans) |span| {
            hasher.update(span.text);
            const style = [_]u32{ if (span.weight) |weight| @backingInt(weight) + 1 else 0, @intFromBool(span.italic), @intFromBool(span.mono), @bitCast(span.size_scale), @intCast(span.text.len) };
            hasher.update(std.mem.asBytes(&style));
        }
        const rest = [_]u32{ @bitCast(pixel_size), @bitCast(line_multiple), @intFromFloat(@max(0, @min(1.0e9, @round(max_width)))), @intFromBool(preformatted), @backingInt(faces.base_weight), @intFromBool(faces.fonts != null) };
        hasher.update(std.mem.asBytes(&rest));
        const key = hasher.final();
        if (self.rich.get(key)) |entry| {
            // Collision guard: every run must still index into its span. On a
            // collision, lay out in the arena and leave the entry, which this
            // frame may already hold.
            var valid = true;
            for (entry.runs) |run| valid = valid and run.span < spans.len and run.end <= spans[run.span].text.len;
            if (valid) return entry.layout;
            return mod.RichLayout.layOut(arena, spans, faces, pixel_size, line_multiple, max_width, preformatted);
        }
        const laid_out = try mod.RichLayout.layOut(arena, spans, faces, pixel_size, line_multiple, max_width, preformatted);
        // Copy into the cache: one block of runs, lines re-pointed into it.
        var run_count: usize = 0;
        for (laid_out.lines) |line| run_count += line.runs.len;
        const runs = self.allocator.alloc(mod.RichRun, run_count) catch return laid_out;
        const lines = self.allocator.alloc(mod.RichLine, laid_out.lines.len) catch {
            self.allocator.free(runs);
            return laid_out;
        };
        var at: usize = 0;
        for (laid_out.lines, lines) |source, *destination| {
            destination.* = source;
            @memcpy(runs[at..][0..source.runs.len], source.runs);
            destination.runs = runs[at..][0..source.runs.len];
            at += source.runs.len;
        }
        var copy = laid_out;
        copy.lines = lines;
        self.rich.putNoClobber(self.allocator, key, .{ .layout = copy, .runs = runs }) catch {
            self.allocator.free(runs);
            self.allocator.free(lines);
            return laid_out;
        };
        return copy;
    }

    /// Frees every wrap in `generation` and empties it.
    ///
    /// - `self`: the cache.
    /// - `generation`: `map` or `retired_map`.
    fn clear(self: *Self, generation: *std.AutoHashMapUnmanaged(u64, []renderer.WrappedLine)) void {
        var iterator = generation.valueIterator();
        while (iterator.next()) |lines| self.allocator.free(lines.*);
        generation.clearRetainingCapacity();
    }

    /// Frees every rich layout in `generation` and empties it.
    ///
    /// - `self`: the cache.
    /// - `generation`: `rich` or `retired_rich`.
    fn clearRich(self: *Self, generation: *std.AutoHashMapUnmanaged(u64, RichEntry)) void {
        var iterator = generation.valueIterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.layout.lines);
            self.allocator.free(entry.runs);
        }
        generation.clearRetainingCapacity();
    }

    /// The key a wrap is cached under.
    ///
    /// - `text`: the text.
    /// - `pixel_size`: its size.
    /// - `max_width`: the width it wraps to.
    /// - Returns: the hash.
    fn keyFor(text: []const u8, pixel_size: f32, max_width: f32) u64 {
        var hasher = std.hash.Wyhash.init(0x21a17e);
        hasher.update(text);
        const size_bits: u32 = @bitCast(pixel_size);
        const width_bits: u32 = @intFromFloat(@max(0, @round(max_width)));
        hasher.update(std.mem.asBytes(&size_bits));
        hasher.update(std.mem.asBytes(&width_bits));
        return hasher.final();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "a full wrap cache keeps a frame's layouts alive past the next frame boundary" {
    var environment = mod.TestEnvironment.init();
    environment.setup();
    defer environment.deinit();
    const context = environment.context();
    const arena = environment.arena_state.allocator();
    var cache = WrapCache.init(std.testing.allocator);
    defer cache.deinit();
    const scope = mod.BuildScope.shared();
    scope.setWrapCache(&cache);
    defer scope.setWrapCache(null);

    // Early in a frame, a selectable paragraph and an editor's rows are laid
    // out; their tap regions keep pointing at them.
    const held_spans = [_]mod.Span{.{ .text = "selectable paragraph" }};
    const held = try cache.layoutRich(arena, &held_spans, context.richFaces(), 14, 1.2, 300, false);
    const held_runs = held.lines[0].runs.len;
    const held_end = held.lines[0].runs[held_runs - 1].end;
    const rows = cache.wrap(arena, context.cache.face, "an editor's text", 14, 300);
    const rows_end = rows[0].end;

    // Later in the same frame, the cache passes both bounds.
    for (0..WrapCache.max_rich + 2) |index| {
        const spans = try arena.dupe(mod.Span, &.{.{ .text = try arena.print("paragraph {d}", .{index}) }});
        _ = try cache.layoutRich(arena, spans, context.richFaces(), 14, 1.2, 300, false);
    }
    for (0..WrapCache.max_wraps + 2) |index| _ = cache.wrap(arena, context.cache.face, try arena.print("line {d}", .{index}), 14, 300);
    try std.testing.expectEqual(held_runs, held.lines[0].runs.len);
    try std.testing.expectEqual(held_end, held.lines[0].runs[held_runs - 1].end);
    try std.testing.expectEqual(rows_end, rows[0].end);

    // The next frame boundary retires the full generations, still alive.
    scope.begin(arena);
    try std.testing.expectEqual(@as(u32, 0), cache.rich.count());
    try std.testing.expectEqual(@as(u32, 0), cache.map.count());
    try std.testing.expectEqual(held_end, held.lines[0].runs[held_runs - 1].end);
    try std.testing.expectEqual(rows_end, rows[0].end);

    // The boundary after frees them.
    scope.begin(arena);
    try std.testing.expectEqual(@as(u32, 0), cache.retired_rich.count());
    try std.testing.expectEqual(@as(u32, 0), cache.retired_map.count());
}
