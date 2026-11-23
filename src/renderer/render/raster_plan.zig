//! A command list made ready to rasterize in any order of rows: each drawing
//! command paired with the clip stack it is drawn under.

const std = @import("std");
const log = std.log.scoped(.ziggui_raster_plan);
const mod = @import("module.zig");

/// One clip region on a clip stack.
pub const RasterClip = struct {
    const Self = @This();

    /// The clip's rect.
    rect: mod.Rect,
    /// The clip's corner radius.
    radius: f32,
};

/// A drawing command and the clips around it, innermost last.
pub const RasterItem = struct {
    const Self = @This();

    /// The command: never a clip push or pop, nor a scene (its placeholder
    /// stands in, as its own items).
    command: mod.DrawCommand,
    /// The clip stack it is drawn under.
    clips: []const RasterClip,
    /// At or above every row the command paints, within its clips; a margin
    /// past them, so a band it misses can skip it unseen.
    min_y: f32,
    /// At or below every row the command paints, within its clips, with a margin.
    max_y: f32,

    /// An item for `command` under `clips`, its vertical reach worked out.
    ///
    /// - `command`: the drawing command.
    /// - `clips`: the clip stack around it.
    /// - Returns: the item.
    pub fn init(command: mod.DrawCommand, clips: []const RasterClip) Self {
        // Each command's rows as the rasterizer bounds them (its rect, grown
        // by its anti-aliasing reach), a pixel more either way for rounding.
        const reach: struct { top: f32, bottom: f32 } = switch (command) {
            .fillRoundedRect => |fill| .{ .top = fill.rect.minY() - 1, .bottom = fill.rect.maxY() + 1 },
            .linearGradient => |gradient| .{ .top = gradient.rect.minY() - 1, .bottom = gradient.rect.maxY() + 1 },
            .eraseRect => |erase| .{ .top = erase.rect.minY() - 1, .bottom = erase.rect.maxY() + 1 },
            .strokeRoundedRect => |stroke| .{ .top = stroke.rect.minY() - stroke.width / 2 - 1, .bottom = stroke.rect.maxY() + stroke.width / 2 + 1 },
            .line => |segment| .{ .top = @min(segment.start.y, segment.end.y) - segment.width / 2 - 1, .bottom = @max(segment.start.y, segment.end.y) + segment.width / 2 + 1 },
            .glyph => |glyph| .{ .top = glyph.rect.minY(), .bottom = glyph.rect.maxY() },
            .image => |image| .{ .top = image.rect.minY(), .bottom = image.rect.maxY() },
            .videoFrame => |frame| .{ .top = frame.rect.minY(), .bottom = frame.rect.maxY() },
            .blurRect => |blur| .{ .top = blur.rect.minY(), .bottom = blur.rect.maxY() },
            .pushClip, .popClip, .scene => unreachable,
        };
        var min_y = reach.top - 1;
        var max_y = reach.bottom + 1;
        for (clips) |clip| {
            min_y = @max(min_y, clip.rect.minY() - 2);
            max_y = @min(max_y, clip.rect.maxY() + 2);
        }
        const self = Self{ .command = command, .clips = clips, .min_y = min_y, .max_y = max_y };
        return self;
    }

    /// Whether the command may paint a row of `rows`: false only when it
    /// certainly paints none, so skipping it changes nothing.
    ///
    /// - `self`: the item.
    /// - `rows`: the band.
    /// - Returns: false when the band can skip it.
    pub fn mayTouch(self: *const Self, rows: mod.RowBand) bool {
        // Written so a NaN extent never skips: what the rasterizer makes of it is its own.
        return !(self.max_y < @as(f32, @floatFromInt(rows.top)) or self.min_y > @as(f32, @floatFromInt(rows.bottom)));
    }

    /// Whether the item reads pixels it does not draw (a blur reads around
    /// itself), so the items before it must be finished everywhere first.
    ///
    /// - `self`: the item.
    /// - Returns: true for a blur.
    pub fn readsNeighbours(self: *const Self) bool {
        return self.command == .blurRect;
    }
};

/// A command list flattened for the rasterizer: the clip pushes and pops
/// resolved into each item's clip stack, a scene replaced by its placeholder.
/// Built once, on one thread; then any number of rasterizers, each limited to
/// its own rows, draw the items without allocating or tracking clips, which
/// is what lets bands of one frame draw at once.
///
/// Every clip stack is a slice of its own, shared by the items under it, so
/// the plan costs a copy of the commands and a little per push.
pub const RasterPlan = struct {
    const Self = @This();

    /// Owns `items` and the clip stacks.
    arena: std.heap.ArenaAllocator,
    /// The drawing commands in order, each with its clips.
    items: []const RasterItem,

    /// Flattens `commands`.
    ///
    /// - `allocator`: allocator for the plan.
    /// - `commands`: the commands, in drawing order.
    /// - Returns: the plan, owned by the caller (`deinit`); propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator, commands: []const mod.DrawCommand) !Self {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const memory = arena.allocator();
        var items: std.ArrayList(RasterItem) = try .initCapacity(memory, commands.len);
        // The stack of clip stacks: each push's stack, so a pop returns to its parent.
        var stacks: std.ArrayList([]const RasterClip) = .empty;
        try stacks.append(memory, &.{});
        for (commands) |command| {
            const clips = stacks.items[stacks.items.len - 1];
            switch (command) {
                .pushClip => |clip| {
                    const pushed = try memory.alloc(RasterClip, clips.len + 1);
                    @memcpy(pushed[0..clips.len], clips);
                    pushed[clips.len] = .{ .rect = clip.rect, .radius = clip.radius };
                    try stacks.append(memory, pushed);
                },
                .popClip => {
                    if (stacks.items.len > 1) _ = stacks.pop();
                },
                // No 3D here: the placeholder stands in for the scene, under the clips around it.
                .scene => |scene| for (scene.placeholder()) |placeholder| try items.append(memory, .init(placeholder, clips)),
                else => try items.append(memory, .init(command, clips)),
            }
        }
        const self = Self{ .arena = arena, .items = items.items };
        return self;
    }

    /// Frees the plan.
    ///
    /// - `self`: the plan; invalid afterwards.
    pub fn deinit(self: *Self) void {
        self.arena.deinit();
        self.* = undefined;
    }

    /// The end of the run of items starting at `start` that reads no
    /// neighbouring pixels: the index of the next blur, or the end.
    ///
    /// - `self`: the plan.
    /// - `start`: the run's first item.
    /// - Returns: one past the run's last item.
    pub fn runEnd(self: *const Self, start: usize) usize {
        var index = start;
        while (index < self.items.len and !self.items[index].readsNeighbours()) index += 1;
        return index;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "RasterPlan: items carry the clips around them" {
    var display_list = mod.DisplayList.init(std.testing.allocator);
    defer display_list.deinit();
    const outer: mod.Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const inner: mod.Rect = .{ .x = 2, .y = 2, .width = 4, .height = 4 };
    try display_list.fillRect(outer, mod.Color.red);
    try display_list.pushClip(outer, 0);
    try display_list.pushClip(inner, 2);
    try display_list.fillRect(inner, mod.Color.blue);
    try display_list.popClip();
    try display_list.fillRect(outer, mod.Color.green);
    try display_list.popClip();
    try display_list.popClip(); // unbalanced: ignored
    try display_list.blurRect(outer, 0, 4, mod.Color.transparent);
    try display_list.fillRect(outer, mod.Color.black);

    var plan = try mod.RasterPlan.init(std.testing.allocator, display_list.commands.items);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 5), plan.items.len);
    try std.testing.expectEqual(@as(usize, 0), plan.items[0].clips.len);
    try std.testing.expectEqual(@as(usize, 2), plan.items[1].clips.len);
    try std.testing.expectEqual(@as(f32, 2), plan.items[1].clips[1].radius);
    try std.testing.expectEqual(@as(usize, 1), plan.items[2].clips.len);
    try std.testing.expectEqual(@as(usize, 0), plan.items[3].clips.len);
    try std.testing.expectEqual(@as(usize, 3), plan.runEnd(0));
    try std.testing.expectEqual(@as(usize, 3), plan.runEnd(3));
    try std.testing.expectEqual(@as(usize, 5), plan.runEnd(4));
}

test "RasterItem: a band skips only what it cannot touch" {
    const clip: mod.RasterClip = .{ .rect = .{ .x = 0, .y = 100, .width = 50, .height = 50 }, .radius = 0 };
    const fill: mod.DrawCommand = .{ .fillRoundedRect = .{ .rect = .{ .x = 0, .y = 20, .width = 10, .height = 200 }, .radius = 0, .color = mod.Color.red } };
    const clipped = mod.RasterItem.init(fill, &.{clip});
    try std.testing.expect(!clipped.mayTouch(.{ .top = 0, .bottom = 90 }));
    try std.testing.expect(clipped.mayTouch(.{ .top = 90, .bottom = 100 }));
    try std.testing.expect(clipped.mayTouch(.{ .top = 149, .bottom = 160 }));
    try std.testing.expect(!clipped.mayTouch(.{ .top = 160, .bottom = 200 }));
    const line: mod.DrawCommand = .{ .line = .{ .start = .{ .x = 0, .y = 300 }, .end = .{ .x = 9, .y = 280 }, .width = 4, .color = mod.Color.red } };
    const unclipped = mod.RasterItem.init(line, &.{});
    try std.testing.expect(unclipped.mayTouch(.{ .top = 270, .bottom = 280 }));
    try std.testing.expect(!unclipped.mayTouch(.{ .top = 310, .bottom = 400 }));
    const nan: mod.DrawCommand = .{ .glyph = .{ .rect = .{ .x = 0, .y = std.math.nan(f32), .width = 1, .height = 1 }, .color = mod.Color.red, .coverage = undefined, .gamma = 1 } };
    try std.testing.expect(mod.RasterItem.init(nan, &.{}).mayTouch(.{ .top = 0, .bottom = 1 }));
}
