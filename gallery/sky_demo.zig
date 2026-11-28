//! The Scenes section's sky card: a `SceneView` of a lighthouse on an
//! island in a rolling sea under drifting clouds, built to show what a scene
//! can do beyond the cube card's shapes and lights: shader modifiers (the
//! waves moved per vertex and shaded per pixel, the sky's gradient, the
//! clouds' drift and haze), emissive surfaces brighter than white (the
//! lamp), a drawing order (the sky behind its clouds), a shape that only
//! casts its shadow, and, ray traced on Metal, the sun shining through a
//! cloud cookie, reflections of an environment with the clouds laid over it,
//! a point light whose shadows are traced only near it, exposure, a filmic
//! tone curve and the soft-shadow ray count; with a cap on the frame rate.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_sky_demo);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The turn that makes a plane, facing +Z, face down (the cloud layer).
const facing_down = ziggui.Quaternion{ .x = std.math.sqrt1_2, .w = std.math.sqrt1_2 };

/// The textures and the sea's mesh the card draws, made at compile time so
/// their bytes never move and every screenshot holds.
const SkyAssets = struct {
    const Self = @This();

    /// The side of the cloud textures, in pixels.
    const cloud_side = 64;
    /// The sky's equirectangular texture's width, in pixels (its height is half).
    const sky_width = 64;
    /// How many cells the sea's grid has along each side.
    const sea_cells = 48;
    /// The sea's side, in scene units.
    const sea_side: f32 = 96;
    /// How many vertices the sea's grid has along each side.
    const sea_points = sea_cells + 1;

    /// A lattice point's pseudo-random value, 0 to 1.
    ///
    /// - `x`: the point's column.
    /// - `y`: the point's row.
    /// - Returns: the value.
    fn lattice(x: u32, y: u32) f32 {
        var hash = x *% 0x27d4eb2d ^ y *% 0x165667b1;
        hash ^= hash >> 15;
        hash *%= 0x85ebca6b;
        hash ^= hash >> 13;
        return @as(f32, @floatFromInt(hash & 0xffff)) / 65535.0;
    }

    /// Value noise at a point, smoothly blended between lattice points that
    /// repeat every `period`, so a texture made of it tiles.
    ///
    /// - `x`: the point's x, in lattice cells.
    /// - `y`: the point's y, in lattice cells.
    /// - `period`: the cells after which the lattice repeats.
    /// - Returns: the noise, 0 to 1.
    fn noise(x: f32, y: f32, period: u32) f32 {
        const cell_x: u32 = @intFromFloat(@floor(x));
        const cell_y: u32 = @intFromFloat(@floor(y));
        const fraction_x = x - @floor(x);
        const fraction_y = y - @floor(y);
        const blend_x = fraction_x * fraction_x * (3 - 2 * fraction_x);
        const blend_y = fraction_y * fraction_y * (3 - 2 * fraction_y);
        const left = cell_x % period;
        const right = (cell_x + 1) % period;
        const top = cell_y % period;
        const bottom = (cell_y + 1) % period;
        const upper = Self.lattice(left, top) + (Self.lattice(right, top) - Self.lattice(left, top)) * blend_x;
        const lower = Self.lattice(left, bottom) + (Self.lattice(right, bottom) - Self.lattice(left, bottom)) * blend_x;
        return upper + (lower - upper) * blend_y;
    }

    /// How cloudy a texel of the cloud textures is: three octaves of noise
    /// thresholded into separate clouds.
    ///
    /// - `x`: the texel's column.
    /// - `y`: the texel's row.
    /// - Returns: the density, 0 to 1.
    fn density(x: usize, y: usize) f32 {
        var sum: f32 = 0;
        var weight: f32 = 0.55;
        var period: u32 = 4;
        while (period <= 16) : (period *= 2) {
            const scale = @as(f32, @floatFromInt(period)) / cloud_side;
            sum += weight * Self.noise(@as(f32, @floatFromInt(x)) * scale, @as(f32, @floatFromInt(y)) * scale, period);
            weight *= 0.5;
        }
        const normalized = sum / (0.55 + 0.275 + 0.1375);
        const edge = std.math.clamp((normalized - 0.45) / 0.25, 0, 1);
        return edge * edge * (3 - 2 * edge);
    }

    /// The clouds as the sky shows them: white, their density their alpha.
    ///
    /// - Returns: the pixels.
    fn clouds() [cloud_side * cloud_side * 4]u8 {
        @setEvalBranchQuota(4_000_000);
        var pixels: [cloud_side * cloud_side * 4]u8 = undefined;
        for (0..cloud_side) |y| for (0..cloud_side) |x| {
            const alpha: u8 = @intFromFloat(Self.density(x, y) * 235);
            @memcpy(pixels[(y * cloud_side + x) * 4 ..][0..4], &[4]u8{ 255, 255, 255, alpha });
        };
        return pixels;
    }

    /// The clouds as the sun's cookie: opaque, darker where they are thicker,
    /// scaling the light that passes them.
    ///
    /// - Returns: the pixels.
    fn shade() [cloud_side * cloud_side * 4]u8 {
        @setEvalBranchQuota(4_000_000);
        var pixels: [cloud_side * cloud_side * 4]u8 = undefined;
        for (0..cloud_side) |y| for (0..cloud_side) |x| {
            const gray: u8 = @intFromFloat((1 - 0.7 * Self.density(x, y)) * 255);
            @memcpy(pixels[(y * cloud_side + x) * 4 ..][0..4], &[4]u8{ gray, gray, gray, 255 });
        };
        return pixels;
    }

    /// The sky reflections see: equirectangular, a deep blue overhead paling
    /// to a hazy horizon, the sea's gray-blue below it.
    ///
    /// - Returns: the pixels.
    fn sky() [sky_width * sky_width / 2 * 4]u8 {
        @setEvalBranchQuota(400_000);
        const height = sky_width / 2;
        const zenith = [3]f32{ 58, 111, 208 };
        const horizon = [3]f32{ 207, 227, 245 };
        const below = [3]f32{ 42, 70, 96 };
        var pixels: [sky_width * height * 4]u8 = undefined;
        for (0..height) |y| {
            const polar = (@as(f32, @floatFromInt(y)) + 0.5) / height * std.math.pi;
            const elevation = @cos(polar);
            var color: [3]f32 = undefined;
            for (&color, zenith, horizon, below) |*channel, high, middle, low| {
                channel.* = if (elevation >= 0) middle + (high - middle) * @sqrt(elevation) else middle + (low - middle) * @min(-elevation * 4, 1);
            }
            for (0..sky_width) |x| {
                @memcpy(pixels[(y * sky_width + x) * 4 ..][0..4], &[4]u8{ @intFromFloat(color[0]), @intFromFloat(color[1]), @intFromFloat(color[2]), 255 });
            }
        }
        return pixels;
    }

    /// The sea's vertices' positions: a level grid centred on the origin.
    ///
    /// - Returns: the positions.
    fn seaPositions() [sea_points * sea_points][3]f32 {
        @setEvalBranchQuota(200_000);
        var positions: [sea_points * sea_points][3]f32 = undefined;
        for (0..sea_points) |row| for (0..sea_points) |column| {
            const x = (@as(f32, @floatFromInt(column)) / sea_cells - 0.5) * sea_side;
            const z = (@as(f32, @floatFromInt(row)) / sea_cells - 0.5) * sea_side;
            positions[row * sea_points + column] = .{ x, 0, z };
        };
        return positions;
    }

    /// The sea's vertices' texture coordinates, 0 to 1 across the grid.
    ///
    /// - Returns: the texture coordinates.
    fn seaUvs() [sea_points * sea_points][2]f32 {
        @setEvalBranchQuota(200_000);
        var uvs: [sea_points * sea_points][2]f32 = undefined;
        for (0..sea_points) |row| for (0..sea_points) |column| {
            uvs[row * sea_points + column] = .{ @as(f32, @floatFromInt(column)) / sea_cells, @as(f32, @floatFromInt(row)) / sea_cells };
        };
        return uvs;
    }

    /// The sea's triangles, two a cell, counter-clockwise seen from above.
    ///
    /// - Returns: the indices.
    fn seaIndices() [sea_cells * sea_cells * 6]u32 {
        @setEvalBranchQuota(200_000);
        var indices: [sea_cells * sea_cells * 6]u32 = undefined;
        for (0..sea_cells) |row| for (0..sea_cells) |column| {
            const corner: u32 = @intCast(row * sea_points + column);
            const below: u32 = corner + sea_points;
            const cell = (row * sea_cells + column) * 6;
            indices[cell..][0..6].* = .{ corner, below, corner + 1, corner + 1, below, below + 1 };
        };
        return indices;
    }
};

/// The clouds as the sky shows them.
const cloud_pixels = SkyAssets.clouds();
/// The clouds as the sun's cookie.
const shade_pixels = SkyAssets.shade();
/// The sky reflections see.
const sky_pixels = SkyAssets.sky();
/// The sea's positions.
const sea_positions = SkyAssets.seaPositions();
/// The sea's normals: straight up (its modifiers write the real ones).
const sea_normals: [sea_positions.len][3]f32 = @splat(.{ 0, 1, 0 });
/// The sea's texture coordinates.
const sea_uvs = SkyAssets.seaUvs();
/// The sea's triangles.
const sea_indices = SkyAssets.seaIndices();

/// The waves' height, shared by the sea's geometry and surface modifiers.
const wave_declarations =
    \\static float wave_height(float2 p, float t, float a) {
    \\    return a * (sin(p.x * 0.45 + t * 1.1) + 0.6 * sin(p.y * 0.7 - t * 0.8 + p.x * 0.2));
    \\}
    \\static float ripple_height(float2 p, float t, float a) {
    \\    return wave_height(p, t, a) + a * 0.12 * (sin(p.x * 3.1 + p.y * 1.7 + t * 2.3) + sin(p.y * 2.6 - p.x * 1.1 - t * 1.9));
    \\}
;

/// The sea's vertices lifted onto the waves: values[0] is (time, amplitude).
const wave_geometry =
    \\position.y = wave_height(position.xz, values[0].x, values[0].y);
;

/// The sea's normal per pixel, from the waves and ripples too fine for its grid.
const wave_surface =
    \\float t = values[0].x;
    \\float a = values[0].y;
    \\float e = 0.05;
    \\float dx = ripple_height(world.xz + float2(e, 0.0), t, a) - ripple_height(world.xz - float2(e, 0.0), t, a);
    \\float dz = ripple_height(world.xz + float2(0.0, e), t, a) - ripple_height(world.xz - float2(0.0, e), t, a);
    \\normal = normalize(float3(-dx, 2.0 * e, -dz));
;

/// The sky's colors by direction, a pale haze at the horizon.
const sky_declarations =
    \\static float3 sky_tint(float3 direction) {
    \\    float up = clamp(direction.y, -1.0, 1.0);
    \\    float3 horizon = float3(1.25, 1.15, 1.02);
    \\    float3 zenith = float3(0.55, 0.72, 1.0);
    \\    float3 sea = float3(0.45, 0.55, 0.65);
    \\    return up >= 0.0 ? mix(horizon, zenith, sqrt(up)) : mix(horizon, sea, min(-up * 4.0, 1.0));
    \\}
;

/// The sky dome's tint, seen from the eye.
const sky_surface =
    \\tint = float4(sky_tint(normalize(world - eye)), 1.0);
;

/// The clouds laid on their plane in the scene's space, drifting, fading
/// into the haze far off: values[0] is (origin x, origin z, tile, haze distance).
const cloud_surface =
    \\uv = (world.xz - values[0].xy) / values[0].z;
    \\float fade = clamp(1.0 - length(world.xz - eye.xz) / values[0].w, 0.0, 1.0);
    \\tint = float4(1.0, 1.0, 1.0, fade * fade);
;

/// The Scenes section's sky scene, its modifiers and the controls over it.
pub const SkyDemo = struct {
    const Self = @This();

    /// How high the cloud layer is.
    const cloud_height: f32 = 14;
    /// One repeat of the clouds, each way.
    const cloud_tile: f32 = 30;
    /// How far off the clouds have faded away.
    const haze_distance: f32 = 110;
    /// How fast the clouds drift along +X, in units a second.
    const drift_per_second: f64 = 0.9;
    /// The waves' height.
    const wave_amplitude: f32 = 0.18;
    /// The soft-shadow ray counts the picker offers.
    const soft_ray_choices = [_]u32{ 4, 16, 32 };
    /// The frame-rate caps the picker offers, 0 for the display's own.
    const frame_rate_choices = [_]u32{ 0, 60, 30 };

    /// The scene the card shows.
    scene: ziggui.Scene,
    /// What the scene's lights and modifiers are kept with.
    allocator: std.mem.Allocator,
    /// The sea's modifier: the waves, per vertex and per pixel.
    waves: *ziggui.SceneShaderModifier,
    /// The sky dome's modifier: its gradient.
    sky: *ziggui.SceneShaderModifier,
    /// The cloud layer's modifier: its drift and haze.
    clouds: *ziggui.SceneShaderModifier,
    /// The environment's overlays: the clouds again, for reflections.
    overlays: *[1]ziggui.ScenePlaneTexture,
    /// The sun, whose cookie drifts with the clouds.
    sun: ziggui.SceneNodeId,
    /// Whether the scene asks to be ray traced.
    ray_traced: ziggui.State(bool),
    /// The scene's exposure (`Scene.exposure`).
    exposure: ziggui.State(f32),
    /// Whether a press is changing the exposure.
    exposure_editing: ziggui.State(bool),
    /// Whether the light is brought into range by a film's curve (`Scene.tone_mapping`).
    filmic: ziggui.State(bool),
    /// The soft-shadow ray count chosen, an index into `soft_ray_choices`.
    soft_rays: ziggui.State(i64),
    /// The frame-rate cap chosen, an index into `frame_rate_choices`.
    frame_rate: ziggui.State(i64),

    /// Builds the scene: the camera, the sky, its clouds, the sea, the island
    /// and its lighthouse, an unseen post, the sun and the lamp.
    ///
    /// - `allocator`: what the scene keeps its nodes with, and its modifiers.
    /// - Returns: the demo; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const waves = try allocator.create(ziggui.SceneShaderModifier);
        errdefer allocator.destroy(waves);
        waves.* = .{ .geometry = wave_geometry, .surface = wave_surface, .declarations = wave_declarations };
        waves.values[0] = .{ 0, wave_amplitude, 0, 0 };
        const sky = try allocator.create(ziggui.SceneShaderModifier);
        errdefer allocator.destroy(sky);
        sky.* = .{ .surface = sky_surface, .declarations = sky_declarations };
        const clouds = try allocator.create(ziggui.SceneShaderModifier);
        errdefer allocator.destroy(clouds);
        clouds.* = .{ .surface = cloud_surface };
        clouds.values[0] = .{ 0, 0, cloud_tile, haze_distance };
        const overlays = try allocator.create([1]ziggui.ScenePlaneTexture);
        errdefer allocator.destroy(overlays);
        overlays[0] = Self.cloudPlane(&cloud_pixels, true, 0);

        var scene = try ziggui.Scene.init(allocator);
        errdefer scene.deinit();
        const root = scene.root();
        scene.background = ziggui.Color.hex(0x9cc4ec);
        scene.ambient = ziggui.Color.hex(0xc8dcff);
        scene.ambient_intensity = 0.35;
        scene.camera_target = ziggui.Vec3.init(-1, 3.5, -6);
        scene.environment = .{ .texture = .{ .image = .{ .width = SkyAssets.sky_width, .height = SkyAssets.sky_width / 2, .pixels = &sky_pixels } }, .strength = 0.9, .overlays = overlays };

        var camera = ziggui.SceneNode{ .name = "camera", .camera = .{ .field_of_view = 50, .far = 200 }, .transform = .{ .position = ziggui.Vec3.init(2, 2.4, 9) } };
        camera.lookAt(scene.camera_target, ziggui.Vec3.up);
        scene.point_of_view = try scene.addChild(root, camera);

        // The sky first (rendering order), never met by reflections: the environment stands in for it.
        _ = try scene.addChild(root, .{
            .name = "sky",
            .geometry = .{ .sphere = .{ .radius = 90 } },
            .material = .{ .base_color = ziggui.Color.hex(0x8fbfff), .specular = 0, .emission = 1, .emission_strength = 1.2, .shader_modifier = sky },
            .casts_shadows = false,
            .receives_shadows = false,
            .reflected = false,
            .rendering_order = -2,
        });
        _ = try scene.addChild(root, .{
            .name = "clouds",
            .geometry = .{ .plane = .{ .width = 180, .height = 180 } },
            .material = .{ .texture = .{ .image = .{ .width = SkyAssets.cloud_side, .height = SkyAssets.cloud_side, .pixels = &cloud_pixels }, .translucent = true }, .specular = 0, .emission = 1, .emission_strength = 1.3, .shader_modifier = clouds },
            .transform = .{ .position = ziggui.Vec3.init(0, cloud_height, 0), .rotation = facing_down },
            .receives_shadows = false,
            .reflected = false,
            .rendering_order = -1,
        });
        const sea_bounds = ziggui.SceneBounds.init(ziggui.Vec3.init(-SkyAssets.sea_side / 2, -1, -SkyAssets.sea_side / 2), ziggui.Vec3.init(SkyAssets.sea_side / 2, 1, SkyAssets.sea_side / 2));
        _ = try scene.addChild(root, .{
            .name = "sea",
            .geometry = .{ .mesh = .{ .positions = &sea_positions, .normals = &sea_normals, .uvs = &sea_uvs, .indices = &sea_indices, .bounds = sea_bounds } },
            .material = .{ .base_color = ziggui.Color.hex(0x1d4f73), .specular = 0.9, .shininess = 96, .reflectivity = 0.35, .shader_modifier = waves },
            .casts_shadows = false,
        });
        _ = try scene.addChild(root, .{
            .name = "island",
            .geometry = .{ .sphere = .{ .radius = 3 } },
            .material = .{ .base_color = ziggui.Color.hex(0x8a7a5c), .specular = 0.05 },
            .transform = .{ .position = ziggui.Vec3.init(-4, -0.2, -6), .scale = ziggui.Vec3.init(1, 0.35, 1) },
        });
        _ = try scene.addChild(root, .{
            .name = "lighthouse",
            .geometry = .{ .cylinder = .{ .radius = 0.35, .height = 4 } },
            .material = .{ .base_color = ziggui.Color.hex(0xf1eee6), .specular = 0.3, .reflectivity = 0.05 },
            .transform = .{ .position = ziggui.Vec3.init(-4, 2.6, -6) },
        });
        // Its lamp glows brighter than white, so a filmic curve shows its form.
        _ = try scene.addChild(root, .{
            .name = "lamp",
            .geometry = .{ .sphere = .{ .radius = 0.32 } },
            .material = .{ .base_color = ziggui.Color.hex(0xffd38a), .emission = 1, .emission_strength = 3 },
            .transform = .{ .position = ziggui.Vec3.init(-4, 4.9, -6) },
            .casts_shadows = false,
        });
        _ = try scene.addChild(root, .{
            .name = "lamp light",
            .light = .{ .kind = .{ .point = .{ .range = 16, .casts_shadows = true, .radius = 0.3, .shadow_range = 7, .shadow_rays = 8 } }, .color = ziggui.Color.hex(0xffc37a), .intensity = 1.2 },
            .transform = .{ .position = ziggui.Vec3.init(-4, 4.9, -6) },
        });
        // A post out of the frame: only its shadow shows, across the sea.
        _ = try scene.addChild(root, .{
            .name = "unseen post",
            .geometry = .{ .box = .{ .width = 0.4, .height = 3, .length = 0.4 } },
            .transform = .{ .position = ziggui.Vec3.init(5.5, 1.5, -1) },
            .shadow_only = true,
        });

        var sun_node = ziggui.SceneNode{ .name = "sun", .light = .{ .kind = .{ .directional = .{ .angular_diameter = 1.5, .cookie = Self.cloudPlane(&shade_pixels, false, 0) } }, .intensity = 1.1, .color = ziggui.Color.hex(0xfff1dc) }, .transform = .{ .position = ziggui.Vec3.init(8, 10, -6) } };
        sun_node.lookAt(ziggui.Vec3.zero, ziggui.Vec3.up);
        const sun = try scene.addChild(root, sun_node);

        const self = Self{
            .scene = scene,
            .allocator = allocator,
            .waves = waves,
            .sky = sky,
            .clouds = clouds,
            .overlays = overlays,
            .sun = sun,
            .ray_traced = ziggui.State(bool).init(allocator, false),
            .exposure = ziggui.State(f32).init(allocator, 1),
            .exposure_editing = ziggui.State(bool).init(allocator, false),
            .filmic = ziggui.State(bool).init(allocator, true),
            .soft_rays = ziggui.State(i64).init(allocator, 1),
            .frame_rate = ziggui.State(i64).init(allocator, 0),
        };
        return self;
    }

    /// Frees the scene, its modifiers and the controls' state.
    ///
    /// - `self`: the demo.
    pub fn deinit(self: *Self) void {
        self.frame_rate.deinit();
        self.soft_rays.deinit();
        self.filmic.deinit();
        self.exposure_editing.deinit();
        self.exposure.deinit();
        self.ray_traced.deinit();
        self.scene.deinit();
        self.allocator.destroy(self.overlays);
        self.allocator.destroy(self.clouds);
        self.allocator.destroy(self.sky);
        self.allocator.destroy(self.waves);
    }

    /// The sky card: the scene moved on to the frame clock's time (the waves,
    /// the clouds and their shadows drifting; still headless), its controls
    /// under it: ray tracing, exposure, a filmic curve, the soft-shadow rays
    /// and the frame-rate cap.
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn card(self: *Self, theme: ziggui.Theme) ziggui.View {
        self.update();
        const traces = ziggui.SystemInfo.shared().ray_tracing;
        const hint = if (traces)
            "Trace rays for the clouds' shadows, the sky and its clouds in the sea, and the lamp's soft shadows near it."
        else
            "Needs Metal ray tracing on Apple silicon: this GPU draws shadow maps and no reflections.";
        const allocator = ziggui.BuildScope.shared().allocator();
        const exposure = allocator.print("{d:.2}×{s}", .{ self.exposure.get(), if (self.exposure_editing.get()) " …" else "" }) catch @panic("oom");
        return gallery.Card.view(
            theme,
            "SceneView: a sea, sky and clouds drawn by shader modifiers, a lamp brighter than white (drag to orbit)",
            "ziggui.SceneShaderModifier · ziggui.ScenePlaneTexture · ziggui.SceneEnvironment · ziggui.SceneToneMapping · SceneMaterial.emission · SceneNode.shadow_only · .reflected · .rendering_order · FrameClock.setFrameRateLimit",
            ziggui.VStack(.{
                ziggui.SceneView(&self.scene, .{ .allows_camera_control = true, .animating = true, .label = "A lighthouse on an island under drifting clouds" }).frameMaxWidth().frameHeight(400),
                ziggui.HStack(.{
                    ziggui.Toggle("Ray tracing", self.ray_traced.binding()).toggleStyle(.checkbox).disabled(!traces).help(hint),
                    ziggui.Toggle("Filmic", self.filmic.binding()).toggleStyle(.checkbox).help("A film's curve rolls the lamp's glow off toward white rather than clipping it (Metal)."),
                    ziggui.Spacer(),
                }).spacing(16),
                Self.row("Exposure", ziggui.HStack(.{
                    ziggui.Slider(self.exposure.binding(), 0.25, 3).sliderStep(0.25).onEditingChanged(self.exposure_editing.binding()).frameMaxWidth(),
                    ziggui.Text(exposure).monospaced().foregroundStyle(theme.colors.secondary_label).frameWidth(64).frameAlign(.leading),
                }).spacing(12)),
                Self.row("Soft rays", ziggui.Picker(self.soft_rays.binding(), &.{ "4", "16", "32" }).pickerStyle(.segmented).help("The most rays a soft shadow sends a light (Metal ray tracing).")),
                Self.row("Frame rate", ziggui.Picker(self.frame_rate.binding(), &.{ "Display", "60 fps", "30 fps" }).pickerStyle(.segmented).help("Caps the frames the window draws while this section shows, saving power while scenes animate.")),
            }).spacing(10).alignment(.leading),
        );
    }

    /// Caps the window's frame rate as the picker says while the card shows,
    /// and lifts the cap otherwise, so it never outlives the section. Called
    /// every frame, whatever section shows.
    ///
    /// - `self`: the demo.
    /// - `shown`: whether the Scenes section shows.
    pub fn applyFrameRate(self: *const Self, shown: bool) void {
        const limit = if (shown) frame_rate_choices[Self.choice(self.frame_rate.get(), frame_rate_choices.len)] else 0;
        ziggui.FrameClock.shared().setFrameRateLimit(limit);
    }

    /// Moves the scene on to the frame clock's time and applies the controls.
    ///
    /// - `self`: the demo.
    fn update(self: *Self) void {
        // Whole repeats dropped in f64, so the drift never jumps as the clock grows.
        const seconds = @as(f64, @floatFromInt(ziggui.FrameClock.shared().time())) / 1000;
        const drift: f32 = @floatCast(@mod(seconds * drift_per_second, cloud_tile));
        const waves_time: f32 = @floatCast(@mod(seconds, 1000 * std.math.pi));
        self.waves.values[0][0] = waves_time;
        self.clouds.values[0][0] = drift;
        self.overlays[0] = Self.cloudPlane(&cloud_pixels, true, drift);
        if (self.scene.node(self.sun)) |sun| if (sun.light) |*light| switch (light.kind) {
            .directional => |*directional| directional.cookie = Self.cloudPlane(&shade_pixels, false, drift),
            else => {},
        };
        self.scene.lighting_technique = if (self.ray_traced.get()) .rayTraced else .rasterized;
        self.scene.exposure = self.exposure.get();
        self.scene.tone_mapping = if (self.filmic.get()) .filmic else .none;
        self.scene.soft_shadow_rays = soft_ray_choices[Self.choice(self.soft_rays.get(), soft_ray_choices.len)];
    }

    /// The cloud layer's plane carrying a texture, drifted along +X.
    ///
    /// - `pixels`: the texture's pixels, `SkyAssets.cloud_side` square.
    /// - `translucent`: whether any pixel is less than opaque.
    /// - `drift`: how far the clouds have drifted.
    /// - Returns: the plane texture.
    fn cloudPlane(pixels: []const u8, translucent: bool, drift: f32) ziggui.ScenePlaneTexture {
        const texture = ziggui.SceneTexture{ .image = .{ .width = SkyAssets.cloud_side, .height = SkyAssets.cloud_side, .pixels = pixels }, .translucent = translucent };
        return ziggui.ScenePlaneTexture.level(texture, ziggui.Vec3.init(drift, cloud_height, 0), cloud_tile);
    }

    /// A picker's index kept within its choices.
    ///
    /// - `index`: the index chosen.
    /// - `count`: how many choices there are.
    /// - Returns: the index, 0 to `count` - 1.
    fn choice(index: i64, count: usize) usize {
        return @intCast(std.math.clamp(index, 0, @as(i64, @intCast(count)) - 1));
    }

    /// A control under its title, the titles in one column.
    ///
    /// - `title`: the title.
    /// - `control`: the control.
    /// - Returns: the row.
    fn row(title: []const u8, control: ziggui.View) ziggui.View {
        return ziggui.HStack(.{ ziggui.Text(title).frameWidth(80).frameAlign(.leading), control.frameMaxWidth() }).spacing(12).frameMaxWidth();
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the sky scene draws its sky first, its clouds after it, and keeps the unseen post out of reflections" {
    const allocator = std.testing.allocator;
    var demo = try SkyDemo.init(allocator);
    defer demo.deinit();
    var frame = try ziggui.SceneFrame.gather(allocator, &demo.scene, 2);
    defer frame.deinit(allocator);
    try std.testing.expectEqual(@as(i32, -2), frame.draws[0].rendering_order);
    try std.testing.expect(!frame.draws[0].reflected);
    // The clouds are the one translucent shape, first among them.
    try std.testing.expectEqual(frame.opaque_count + 1, frame.draws.len);
    try std.testing.expectEqual(@as(i32, -1), frame.draws[frame.opaque_count].rendering_order);
    var shadow_only: usize = 0;
    for (frame.draws) |draw| if (draw.shadow_only) {
        shadow_only += 1;
        try std.testing.expect(!draw.reflected);
    };
    try std.testing.expectEqual(@as(usize, 1), shadow_only);
    try std.testing.expect(frame.directional_lights[0].cookie != null);
    try std.testing.expect(frame.environment != null);
    try std.testing.expectEqual(@as(f32, 7), frame.point_lights[0].shadow_range);
}

test "the sky card's frame-rate cap holds only while the Scenes section shows" {
    var demo = try SkyDemo.init(std.testing.allocator);
    defer demo.deinit();
    const clock = ziggui.FrameClock.shared();
    defer clock.setFrameRateLimit(0);
    demo.frame_rate.set(2);
    demo.applyFrameRate(true);
    try std.testing.expectEqual(@as(u32, 30), clock.frame_rate_limit);
    demo.applyFrameRate(false);
    try std.testing.expectEqual(@as(u32, 0), clock.frame_rate_limit);
}

test "the sky's cloud textures tile, and the sea's grid is whole" {
    // The noise repeats every period, so the textures' edges meet.
    try std.testing.expectApproxEqAbs(SkyAssets.noise(0, 1.75, 4), SkyAssets.noise(4, 1.75, 4), 1e-6);
    try std.testing.expectApproxEqAbs(SkyAssets.density(0, 7), SkyAssets.density(SkyAssets.cloud_side, 7), 1e-6);
    const mesh = ziggui.SceneMesh{ .positions = &sea_positions, .normals = &sea_normals, .uvs = &sea_uvs, .indices = &sea_indices };
    try mesh.validate();
}
