//! GPU scene translation: turns a `Canvas` command list into the flat,
//! GPU-friendly form the SDL_GPU backend (`sdl/gpu/gpu.zig`) consumes —
//! a packed per-instance array (one `Instance` per draw command, rendered as an
//! instanced quad whose fragment shader evaluates the same rounded-box /
//! segment SDFs as the `Rasterizer`), a glyph/image texture atlas, and a `Step`
//! list that splits the instance stream wherever a `blurRect` needs the
//! pixels rendered so far.
//!
//! This module is pure Zig with no GPU or C dependency, so the whole
//! translation layer (packing, clip resolution, padding, atlas growth) is
//! unit-tested headlessly; only the thin SDL_GPU shell remains build-verified.

const std = @import("std");
const log = std.log.scoped(.ziggui_gpu_scene);
const mod = @import("module.zig");

/// Shader instance kinds; must match the `switch` in `prim.frag`/`prim.metal`.
const InstanceKind = enum(u32) {
    const Self = @This();

    /// A filled rounded rect.
    fill = 0,
    /// A stroked rounded rect.
    stroke = 1,
    /// A linear gradient in a rounded rect.
    gradient = 2,
    /// A tinted atlas coverage mask.
    glyph = 3,
    /// An atlas image.
    image = 4,
    /// A line segment.
    line = 5,
};

/// The clip state distilled to what one shader instance can evaluate: the
/// axis-aligned intersection of every clip rect, plus the innermost clip that
/// has a nonzero corner radius (evaluated as a rounded-box SDF). This matches
/// the software rasterizer exactly except when two *rounded* clips nest, where
/// only the inner radius is honored — a case the component layer never emits.
const ClipState = struct {
    const Self = @This();

    /// The intersection of every clip rect (x, y, width, height).
    rect: [4]f32,
    /// The innermost rounded clip's rect.
    rounded_rect: [4]f32,
    /// The innermost rounded clip's radius.
    radius: f32,

    /// Distill a clip stack.
    ///
    /// - `clips`: the clip rects, outermost first.
    /// - `radii`: each clip's corner radius.
    /// - `framebuffer_width`: the framebuffer's width (the unclipped extent).
    /// - `framebuffer_height`: the framebuffer's height.
    /// - Returns: the clip state.
    fn resolve(clips: []const mod.Rect, radii: []const f32, framebuffer_width: f32, framebuffer_height: f32) Self {
        var left: f32 = 0;
        var top: f32 = 0;
        var right: f32 = framebuffer_width;
        var bottom: f32 = framebuffer_height;
        var rounded: [4]f32 = .{ 0, 0, framebuffer_width, framebuffer_height };
        var radius: f32 = 0;
        for (clips, radii) |clip, clip_radius| {
            left = @max(left, clip.minX());
            top = @max(top, clip.minY());
            right = @min(right, clip.maxX());
            bottom = @min(bottom, clip.maxY());
            if (clip_radius > 0) {
                rounded = GpuScene.rectArray(clip);
                radius = clip_radius;
            }
        }
        const self = Self{
            .rect = .{ left, top, @max(0, right - left), @max(0, bottom - top) },
            .rounded_rect = rounded,
            .radius = radius,
        };
        return self;
    }
};

/// A canvas translated for the GPU: instances and the steps that draw them.
pub const GpuScene = struct {
    const Self = @This();

    /// One instance per drawn command, in paint order.
    instances: []const mod.Instance,
    /// The draw runs and blur breaks, in paint order.
    steps: []const mod.Step,

    /// Translate `commands` into a scene. Instance/step storage is allocated
    /// in `arena` (per-frame); atlas bookkeeping persists in the atlas's own
    /// allocator. On `error.AtlasFull` the caller should `atlas.grow()` (or
    /// `reset()`) and retry — entries staged so far were invalidated by the
    /// reset.
    ///
    /// - `arena`: per-frame allocator for the instances and steps.
    /// - `commands`: the commands.
    /// - `atlas`: the texture atlas glyphs and images are packed into.
    /// - `framebuffer_width`: the framebuffer's width (the unclipped extent).
    /// - `framebuffer_height`: the framebuffer's height.
    /// - Returns: the scene; `error.AtlasFull` when the atlas has no room;
    ///   propagates allocation failure.
    pub fn translate(
        arena: std.mem.Allocator,
        commands: []const mod.DrawCommand,
        atlas: *mod.TextureAtlas,
        framebuffer_width: f32,
        framebuffer_height: f32,
    ) error{ OutOfMemory, AtlasFull }!Self {
        var instances: std.ArrayList(mod.Instance) = .empty;
        var steps: std.ArrayList(mod.Step) = .empty;
        var clip_rects: std.ArrayList(mod.Rect) = .empty;
        var clip_radii: std.ArrayList(f32) = .empty;
        var run_start: u32 = 0;

        for (commands) |command| {
            switch (command) {
                .pushClip => |clip| {
                    try clip_rects.append(arena, clip.rect);
                    try clip_radii.append(arena, clip.radius);
                },
                .popClip => {
                    if (clip_rects.items.len > 0) {
                        _ = clip_rects.pop();
                        _ = clip_radii.pop();
                    }
                },
                .blurRect => |blur| {
                    const count: u32 = @intCast(instances.items.len);
                    if (count > run_start) {
                        try steps.append(arena, .{ .draw = .{ .first = run_start, .count = count - run_start } });
                        run_start = count;
                    }
                    const clip = ClipState.resolve(clip_rects.items, clip_radii.items, framebuffer_width, framebuffer_height);
                    try steps.append(arena, .{ .blur = .{
                        .rect = Self.rectArray(blur.rect),
                        .radius = blur.radius,
                        .sigma = blur.sigma,
                        .tint = Self.colorArray(blur.tint),
                        .clip = clip.rect,
                        .clip_rounded_rect = clip.rounded_rect,
                        .clip_radius = clip.radius,
                    } });
                },
                else => {
                    const clip = ClipState.resolve(clip_rects.items, clip_radii.items, framebuffer_width, framebuffer_height);
                    var instance = mod.Instance{
                        .quad = undefined,
                        .shape = .{ 0, 0, 0, 0 },
                        .color0 = .{ 0, 0, 0, 0 },
                        .color1 = .{ 0, 0, 0, 0 },
                        .points = .{ 0, 0, 0, 0 },
                        .atlas_rect = .{ 0, 0, 0, 0 },
                        .clip = clip.rect,
                        .clip_rounded_rect = clip.rounded_rect,
                        .parameters = .{ 0, 0, 0, clip.radius },
                    };
                    switch (command) {
                        .fillRoundedRect => |fill| {
                            instance.quad = Self.paddedQuad(fill.rect, 1);
                            instance.shape = Self.rectArray(fill.rect);
                            instance.color0 = Self.colorArray(fill.color);
                            instance.parameters[0] = @floatFromInt(@backingInt(InstanceKind.fill));
                            instance.parameters[1] = fill.radius;
                        },
                        .strokeRoundedRect => |stroke| {
                            instance.quad = Self.paddedQuad(stroke.rect, stroke.width / 2 + 1);
                            instance.shape = Self.rectArray(stroke.rect);
                            instance.color0 = Self.colorArray(stroke.color);
                            instance.parameters[0] = @floatFromInt(@backingInt(InstanceKind.stroke));
                            instance.parameters[1] = stroke.radius;
                            instance.parameters[2] = stroke.width / 2;
                        },
                        .linearGradient => |gradient| {
                            instance.quad = Self.paddedQuad(gradient.rect, 1);
                            instance.shape = Self.rectArray(gradient.rect);
                            instance.color0 = Self.colorArray(gradient.start_color);
                            instance.color1 = Self.colorArray(gradient.end_color);
                            instance.points = .{ gradient.start.x, gradient.start.y, gradient.end.x, gradient.end.y };
                            instance.parameters[0] = @floatFromInt(@backingInt(InstanceKind.gradient));
                            instance.parameters[1] = gradient.radius;
                        },
                        .line => |segment| {
                            const bounding_box = mod.Rect{
                                .x = @min(segment.start.x, segment.end.x),
                                .y = @min(segment.start.y, segment.end.y),
                                .width = @abs(segment.end.x - segment.start.x),
                                .height = @abs(segment.end.y - segment.start.y),
                            };
                            instance.quad = Self.paddedQuad(bounding_box, segment.width / 2 + 1);
                            instance.color0 = Self.colorArray(segment.color);
                            instance.points = .{ segment.start.x, segment.start.y, segment.end.x, segment.end.y };
                            instance.parameters[0] = @floatFromInt(@backingInt(InstanceKind.line));
                            instance.parameters[2] = segment.width / 2;
                        },
                        .glyph => |glyph| {
                            if (glyph.coverage.width == 0 or glyph.coverage.height == 0) continue;
                            instance.quad = Self.glyphQuad(glyph.rect, glyph.coverage);
                            instance.color0 = Self.colorArray(glyph.color);
                            // Expand the coverage to RGBA only when the atlas lacks it.
                            const pointer = @intFromPtr(glyph.coverage.data.ptr);
                            instance.atlas_rect = atlas.lookup(pointer, glyph.coverage.width, glyph.coverage.height) orelse
                                try atlas.place(pointer, glyph.coverage.width, glyph.coverage.height, try Self.coverageToRgba(arena, glyph.coverage));
                            instance.parameters[0] = @floatFromInt(@backingInt(InstanceKind.glyph));
                            // parameters[1] (unused by glyphs — no corner radius) carries
                            // the coverage gamma the fragment shader applies, matching
                            // the software rasterizer's `drawGlyph`.
                            instance.parameters[1] = glyph.gamma;
                        },
                        .image => |image| {
                            if (image.image.width == 0 or image.image.height == 0) continue;
                            instance.quad = Self.rectArray(image.rect);
                            instance.atlas_rect = try atlas.place(
                                @intFromPtr(image.image.pixels.ptr),
                                image.image.width,
                                image.image.height,
                                image.image.pixels,
                            );
                            instance.parameters[0] = @floatFromInt(@backingInt(InstanceKind.image));
                        },
                        else => unreachable,
                    }
                    try instances.append(arena, instance);
                },
            }
        }
        const count: u32 = @intCast(instances.items.len);
        if (count > run_start) {
            try steps.append(arena, .{ .draw = .{ .first = run_start, .count = count - run_start } });
        }
        const self = Self{ .instances = instances.items, .steps = steps.items };
        return self;
    }

    /// A color as a shader float4.
    ///
    /// - `color`: the color.
    /// - Returns: r, g, b, a.
    fn colorArray(color: mod.Color) [4]f32 {
        return .{ color.r, color.g, color.b, color.a };
    }

    /// A rect as a shader float4.
    ///
    /// - `rect`: the rect.
    /// - Returns: x, y, width, height.
    fn rectArray(rect: mod.Rect) [4]f32 {
        return .{ rect.x, rect.y, rect.width, rect.height };
    }

    /// A glyph's quad, as a shader float4. A glyph drawn at its coverage's own
    /// size lands on the whole pixel the software rasterizer starts it at
    /// (`ceil(x - 0.5)`): left fractional, the GPU snaps the quad's corners to
    /// its subpixel grid, and a glyph just past a half pixel (338.5005) snaps
    /// onto the tie and samples one pixel early. A scaled glyph keeps its rect.
    ///
    /// - `rect`: where the glyph is drawn.
    /// - `coverage`: its mask.
    /// - Returns: x, y, width, height.
    fn glyphQuad(rect: mod.Rect, coverage: mod.Coverage) [4]f32 {
        const unscaled = rect.width == @as(f32, @floatFromInt(coverage.width)) and rect.height == @as(f32, @floatFromInt(coverage.height));
        if (!unscaled) return Self.rectArray(rect);
        return .{ @ceil(rect.x - 0.5), @ceil(rect.y - 0.5), rect.width, rect.height };
    }

    /// A rect grown by `padding` on every side, as a shader float4.
    ///
    /// - `rect`: the rect.
    /// - `padding`: how far each side grows.
    /// - Returns: x, y, width, height.
    fn paddedQuad(rect: mod.Rect, padding: f32) [4]f32 {
        return .{ rect.x - padding, rect.y - padding, rect.width + 2 * padding, rect.height + 2 * padding };
    }

    /// Expand an 8-bit coverage mask to the RGBA8 the atlas stores: white with the
    /// coverage in alpha, so the shader's `color0 * texel.a` reproduces the
    /// software rasterizer's tinted-glyph blend.
    ///
    /// - `arena`: per-frame allocator for the pixels.
    /// - `coverage`: the mask.
    /// - Returns: the RGBA8 pixels; propagates allocation failure.
    fn coverageToRgba(arena: std.mem.Allocator, coverage: mod.Coverage) ![]const u8 {
        const pixels = try arena.alloc(u8, @as(usize, coverage.width) * coverage.height * 4);
        for (coverage.data, 0..) |alpha, index| {
            pixels[index * 4 + 0] = 255;
            pixels[index * 4 + 1] = 255;
            pixels[index * 4 + 2] = 255;
            pixels[index * 4 + 3] = alpha;
        }
        return pixels;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

/// Translates the way the tests need it.
const TestScene = struct {
    const Self = @This();

    /// Translate `commands` for an 800 × 600 framebuffer.
    ///
    /// - `arena`: per-frame allocator.
    /// - `commands`: the commands.
    /// - `atlas`: the texture atlas.
    /// - Returns: the scene; as `GpuScene.translate`.
    fn translate(arena: std.mem.Allocator, commands: []const mod.DrawCommand, atlas: *mod.TextureAtlas) !GpuScene {
        return GpuScene.translate(arena, commands, atlas, 800, 600);
    }
};

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "gpu_scene: fill becomes one padded instance and one draw step" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var atlas = mod.TextureAtlas.init(std.testing.allocator, 64);
    defer atlas.deinit();

    const commands = [_]mod.DrawCommand{
        .{ .fillRoundedRect = .{ .rect = .{ .x = 10, .y = 20, .width = 30, .height = 40 }, .radius = 5, .color = mod.Color.red } },
    };
    const scene = try TestScene.translate(arena_state.allocator(), &commands, &atlas);

    try std.testing.expectEqual(@as(usize, 1), scene.instances.len);
    const instance = scene.instances[0];
    try std.testing.expectEqual([4]f32{ 9, 19, 32, 42 }, instance.quad); // padded by 1
    try std.testing.expectEqual([4]f32{ 10, 20, 30, 40 }, instance.shape);
    try std.testing.expectEqual(@as(f32, @floatFromInt(@backingInt(InstanceKind.fill))), instance.parameters[0]);
    try std.testing.expectEqual(@as(f32, 5), instance.parameters[1]);
    try std.testing.expectEqual(@as(usize, 1), scene.steps.len);
    try std.testing.expectEqual(@as(u32, 1), scene.steps[0].draw.count);
}

test "gpu_scene: stroke and line pad by half width + 1" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var atlas = mod.TextureAtlas.init(std.testing.allocator, 64);
    defer atlas.deinit();

    const commands = [_]mod.DrawCommand{
        .{ .strokeRoundedRect = .{ .rect = .{ .x = 10, .y = 10, .width = 20, .height = 20 }, .width = 4, .color = mod.Color.black } },
        .{ .line = .{ .start = .{ .x = 0, .y = 0 }, .end = .{ .x = 10, .y = 10 }, .width = 2, .color = mod.Color.black } },
    };
    const scene = try TestScene.translate(arena_state.allocator(), &commands, &atlas);

    try std.testing.expectEqual([4]f32{ 7, 7, 26, 26 }, scene.instances[0].quad); // 4/2+1 = 3
    try std.testing.expectEqual(@as(f32, 2), scene.instances[0].parameters[2]); // half width
    try std.testing.expectEqual([4]f32{ -2, -2, 14, 14 }, scene.instances[1].quad); // 2/2+1 = 2
    try std.testing.expectEqual([4]f32{ 0, 0, 10, 10 }, scene.instances[1].points);
}

test "gpu_scene: clip stack intersects rects and keeps innermost rounded clip" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var atlas = mod.TextureAtlas.init(std.testing.allocator, 64);
    defer atlas.deinit();

    const commands = [_]mod.DrawCommand{
        .{ .pushClip = .{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 100 }, .radius = 8 } },
        .{ .pushClip = .{ .rect = .{ .x = 50, .y = 50, .width = 100, .height = 100 } } },
        .{ .fillRoundedRect = .{ .rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 }, .color = mod.Color.red } },
        .popClip,
        .popClip,
        .{ .fillRoundedRect = .{ .rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 }, .color = mod.Color.red } },
    };
    const scene = try TestScene.translate(arena_state.allocator(), &commands, &atlas);

    const clipped = scene.instances[0];
    try std.testing.expectEqual([4]f32{ 50, 50, 50, 50 }, clipped.clip); // intersection
    try std.testing.expectEqual([4]f32{ 0, 0, 100, 100 }, clipped.clip_rounded_rect);
    try std.testing.expectEqual(@as(f32, 8), clipped.parameters[3]);

    const unclipped = scene.instances[1];
    try std.testing.expectEqual([4]f32{ 0, 0, 800, 600 }, unclipped.clip); // full framebuffer
    try std.testing.expectEqual(@as(f32, 0), unclipped.parameters[3]);
}

test "gpu_scene: glyphs pack into the atlas once and share UVs" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var atlas = mod.TextureAtlas.init(std.testing.allocator, 64);
    defer atlas.deinit();

    const coverage_data = [_]u8{ 255, 0, 0, 255 };
    const coverage = mod.Coverage{ .width = 2, .height = 2, .data = &coverage_data };
    const commands = [_]mod.DrawCommand{
        .{ .glyph = .{ .rect = .{ .x = 0, .y = 0, .width = 2, .height = 2 }, .color = mod.Color.red, .coverage = coverage } },
        .{ .glyph = .{ .rect = .{ .x = 5, .y = 5, .width = 2, .height = 2 }, .color = mod.Color.blue, .coverage = coverage } },
    };
    const scene = try TestScene.translate(arena_state.allocator(), &commands, &atlas);

    try std.testing.expectEqual(scene.instances[0].atlas_rect, scene.instances[1].atlas_rect);
    const pending = atlas.pendingUploads();
    try std.testing.expectEqual(@as(usize, 1), pending.len); // same coverage -> one upload
    try std.testing.expectEqual(@as(u32, 2), pending[0].width);
    // coverage expanded to white RGBA with coverage alpha
    try std.testing.expectEqual(@as(u8, 255), pending[0].pixels[0]); // r
    try std.testing.expectEqual(@as(u8, 255), pending[0].pixels[3]); // a of first texel
    try std.testing.expectEqual(@as(u8, 0), pending[0].pixels[7]); // a of second texel
    atlas.clearPending();
    try std.testing.expectEqual(@as(usize, 0), atlas.pendingUploads().len); // drained
}

test "gpu_scene: blur splits the instance stream into steps" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var atlas = mod.TextureAtlas.init(std.testing.allocator, 64);
    defer atlas.deinit();

    const rect = mod.Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const commands = [_]mod.DrawCommand{
        .{ .fillRoundedRect = .{ .rect = rect, .color = mod.Color.red } },
        .{ .blurRect = .{ .rect = rect, .sigma = 4, .tint = mod.Color.white.withAlpha(0.5) } },
        .{ .fillRoundedRect = .{ .rect = rect, .color = mod.Color.blue } },
    };
    const scene = try TestScene.translate(arena_state.allocator(), &commands, &atlas);

    try std.testing.expectEqual(@as(usize, 3), scene.steps.len);
    try std.testing.expectEqual(@as(u32, 1), scene.steps[0].draw.count);
    try std.testing.expectEqual(@as(f32, 4), scene.steps[1].blur.sigma);
    try std.testing.expectEqual(@as(u32, 1), scene.steps[2].draw.first);
    try std.testing.expectEqual(@as(u32, 1), scene.steps[2].draw.count);
}

test "gpu_scene: atlas reports full and recovers by growing" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var atlas = mod.TextureAtlas.init(std.testing.allocator, 8);
    defer atlas.deinit();

    // An 8x8 mask + 1px pad cannot fit an 8x8 atlas.
    const data: [64]u8 = @splat(255);
    const coverage = mod.Coverage{ .width = 8, .height = 8, .data = &data };
    const commands = [_]mod.DrawCommand{
        .{ .glyph = .{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 8 }, .color = mod.Color.red, .coverage = coverage } },
    };
    try std.testing.expectError(error.AtlasFull, TestScene.translate(arena_state.allocator(), &commands, &atlas));

    const generation = atlas.generation;
    try std.testing.expect(atlas.grow());
    try std.testing.expectEqual(@as(u32, 16), atlas.size);
    try std.testing.expect(atlas.generation != generation);
    const scene = try TestScene.translate(arena_state.allocator(), &commands, &atlas);
    try std.testing.expectEqual(@as(usize, 1), scene.instances.len);
}

test "gpu_scene: a glyph already in the atlas is not expanded to RGBA again" {
    var atlas = mod.TextureAtlas.init(std.testing.allocator, 64);
    defer atlas.deinit();
    const data: [16]u8 = @splat(200);
    const coverage = mod.Coverage{ .width = 4, .height = 4, .data = &data };
    const commands = [_]mod.DrawCommand{
        .{ .glyph = .{ .rect = .{ .x = 0, .y = 0, .width = 4, .height = 4 }, .color = mod.Color.red, .coverage = coverage } },
    };
    // A fixed-buffer arena per frame, so its end index is the bytes the frame took.
    var first_buffer: [4096]u8 = undefined;
    var first_arena = std.heap.FixedBufferAllocator.init(&first_buffer);
    const first = try TestScene.translate(first_arena.allocator(), &commands, &atlas);
    try std.testing.expectEqual(@as(usize, 1), atlas.pendingUploads().len);
    atlas.clearPending();

    var second_buffer: [4096]u8 = undefined;
    var second_arena = std.heap.FixedBufferAllocator.init(&second_buffer);
    const second = try TestScene.translate(second_arena.allocator(), &commands, &atlas);
    try std.testing.expectEqual(first.instances[0].atlas_rect, second.instances[0].atlas_rect);
    try std.testing.expectEqual(@as(usize, 0), atlas.pendingUploads().len);
    // The second frame skipped the 4 x 4 x 4 RGBA expansion.
    try std.testing.expectEqual(first_arena.end_index - 4 * 4 * 4, second_arena.end_index);
}

test "an unscaled glyph's quad starts on the pixel the software rasterizer starts it at" {
    const coverage = mod.Coverage{ .width = 4, .height = 6, .data = &.{} };
    // Just past a half pixel: the software rasterizer starts at 339, not 338.
    try std.testing.expectEqual([4]f32{ 339, 343, 4, 6 }, GpuScene.glyphQuad(.{ .x = 338.5005, .y = 342.5005, .width = 4, .height = 6 }, coverage));
    // Exactly on a half pixel the pixel at 338 samples texel 0 (338.5 - 338.5 = 0).
    try std.testing.expectEqual([4]f32{ 338, 342, 4, 6 }, GpuScene.glyphQuad(.{ .x = 338.5, .y = 342.5, .width = 4, .height = 6 }, coverage));
    // A scaled glyph keeps its own rect.
    try std.testing.expectEqual([4]f32{ 10.25, 3.75, 8, 12 }, GpuScene.glyphQuad(.{ .x = 10.25, .y = 3.75, .width = 8, .height = 12 }, coverage));
}
