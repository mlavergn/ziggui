//! One frame of a scene as the GPU draws it: the shapes in drawing order,
//! the lights (and their shadow projections) and the camera, all in the
//! scene's space, colors linear.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_frame);
const mod = @import("module.zig");
const renderer = @import("renderer");

/// A shape to draw: its geometry and material, and where it is.
pub const SceneDraw = struct {
    const Self = @This();

    /// The shape.
    geometry: mod.SceneGeometry,
    /// How its surface looks.
    material: mod.SceneMaterial,
    /// Its transform in the scene's space.
    world: mod.Mat4,
    /// The matrix that turns its normals into the scene's space.
    normal: mod.Mat4,
    /// The box holding it, in the scene's space.
    bounds: mod.SceneBounds,
    /// Whether it casts shadows (never a translucent shape).
    casts_shadows: bool,
    /// Whether it shows the shadows cast onto it.
    receives_shadows: bool,
    /// Whether it only casts its shadow (`SceneNode.shadow_only`): not drawn, nor reflected.
    shadow_only: bool = false,
    /// Whether reflection rays meet it (`SceneNode.reflected`, and never a shadow-only shape).
    reflected: bool = true,
    /// When it draws among the others (`SceneNode.rendering_order`): lower first.
    rendering_order: i32 = 0,
};

/// A directional light as the shaders read it.
pub const SceneFrameDirectionalLight = struct {
    const Self = @This();

    /// The way its light travels, a unit vector in the scene's space.
    direction: mod.Vec3,
    /// Its color times its intensity, linear.
    color: mod.Vec3,
    /// The projection from the scene's space into its shadow map, or null
    /// when it casts no shadow this frame (it casts none, or nothing would
    /// show one).
    shadow: ?mod.Mat4,
    /// Half the angle its source spans, in radians (`angular_diameter`), for
    /// soft ray-traced shadows; 0 for hard ones.
    angular_radius: f32 = 0,
    /// The texture it shines through, or null (one that is not usable, `ScenePlaneTexture.isUsable`, is dropped).
    cookie: ?mod.ScenePlaneTexture = null,
};

/// A point light as the shaders read it.
pub const SceneFramePointLight = struct {
    const Self = @This();

    /// Where it is, in the scene's space.
    position: mod.Vec3,
    /// Its color times its intensity, linear.
    color: mod.Vec3,
    /// How far it reaches.
    range: f32,
    /// Whether it casts ray-traced shadows.
    casts_shadows: bool = false,
    /// Its source's radius, for soft ray-traced shadows; 0 for hard ones.
    radius: f32 = 0,
    /// How far from it its shadows are traced (`ScenePointLight.shadow_range`), at most `range`.
    shadow_range: f32 = 0,
    /// The most rays a soft shadow of its sends, or null for the scene's.
    shadow_rays: ?u32 = null,
};

/// One frame of a scene, gathered from its graph: the opaque shapes first,
/// then the translucent ones from the farthest to the nearest, the lights
/// up to the limits (the first in the graph kept) and the camera.
pub const SceneFrame = struct {
    const Self = @This();

    /// The directional lights a frame draws with at most.
    pub const max_directional_lights = 4;
    /// The point lights a frame draws with at most.
    pub const max_point_lights = 8;

    /// The shapes, opaque first, then translucent from back to front.
    draws: []SceneDraw,
    /// How many of `draws` are opaque.
    opaque_count: usize,
    /// The directional lights, at most `max_directional_lights`.
    directional_lights: []SceneFrameDirectionalLight,
    /// What reflections see where they meet nothing (`Scene.environment`).
    environment: ?mod.SceneEnvironment = null,
    /// What the light is multiplied by before it's shown (`Scene.exposure`).
    exposure: f32 = 1,
    /// How it's brought into the display's range (`Scene.tone_mapping`).
    tone_mapping: mod.SceneToneMapping = .none,
    /// The point lights, at most `max_point_lights`.
    point_lights: []SceneFramePointLight,
    /// The ambient light's color times its intensity, linear.
    ambient: mod.Vec3,
    /// From the scene's space to the camera's.
    view: mod.Mat4,
    /// From the camera's space to the view's clip space.
    projection: mod.Mat4,
    /// Where the camera is, in the scene's space.
    eye: mod.Vec3,

    /// Gathers a frame from a scene seen in a view of the given aspect.
    ///
    /// - `allocator`: what the frame is allocated with (a frame's arena:
    ///   `deinit` frees it otherwise).
    /// - `scene`: the scene.
    /// - `aspect`: the view's width over its height.
    /// - Returns: the frame; propagates allocation failure.
    pub fn gather(allocator: std.mem.Allocator, scene: *const mod.Scene, aspect: f32) error{OutOfMemory}!Self {
        const visits = try scene.walk(allocator);
        defer allocator.free(visits);

        var opaque_draws: std.ArrayList(SceneDraw) = .empty;
        defer opaque_draws.deinit(allocator);
        var translucent_draws: std.ArrayList(SceneDraw) = .empty;
        defer translucent_draws.deinit(allocator);
        var directional_lights: std.ArrayList(SceneFrameDirectionalLight) = .empty;
        errdefer directional_lights.deinit(allocator);
        var point_lights: std.ArrayList(SceneFramePointLight) = .empty;
        errdefer point_lights.deinit(allocator);

        var eye = mod.Vec3.init(0, 0, 5).add(scene.camera_target);
        var view = mod.Mat4.lookAt(eye, scene.camera_target, mod.Vec3.up);
        var camera = mod.SceneCamera{};
        for (visits) |visit| {
            const node = visit.node;
            // A faded node's opacity folds into its material's alpha, making it translucent.
            if (node.geometry) |geometry| if (visit.opacity > 0) {
                var material = node.material;
                material.base_color.a *= visit.opacity;
                const draw = SceneDraw{
                    .geometry = geometry,
                    .material = material,
                    .world = visit.world,
                    .normal = visit.world.normalMatrix(),
                    .bounds = geometry.bounds().transformed(visit.world),
                    .casts_shadows = node.casts_shadows and !material.isTranslucent(),
                    .receives_shadows = node.receives_shadows,
                    .shadow_only = node.shadow_only,
                    .reflected = node.reflected and !node.shadow_only,
                    .rendering_order = node.rendering_order,
                };
                if (material.isTranslucent()) try translucent_draws.append(allocator, draw) else try opaque_draws.append(allocator, draw);
            };
            if (node.light) |light| switch (light.kind) {
                .directional => |directional| if (directional_lights.items.len < max_directional_lights) {
                    const direction = visit.world.transformDirection(mod.Vec3.init(0, 0, -1)).normalized();
                    // A degenerate transform leaves no direction: lit as from straight above.
                    try directional_lights.append(allocator, .{
                        .direction = if (direction.length() == 0) mod.Vec3.init(0, -1, 0) else direction,
                        .color = Self.linear(light.color).scale(light.intensity),
                        // Marks a light that wants a shadow; fitted once every shape is known.
                        .shadow = if (directional.casts_shadows) mod.Mat4.identity else null,
                        // NaN or negative is 0 (`clamp` would make NaN 90).
                        .angular_radius = if (directional.angular_diameter > 0) std.math.degreesToRadians(@min(directional.angular_diameter, 90)) / 2 else 0,
                        .cookie = Self.usableCookie(directional.cookie),
                    });
                },
                .point => |point| if (point_lights.items.len < max_point_lights) try point_lights.append(allocator, .{
                    .position = visit.world.transformPoint(mod.Vec3.zero),
                    .color = Self.linear(light.color).scale(light.intensity),
                    .range = @max(point.range, 0),
                    .casts_shadows = point.casts_shadows,
                    .radius = if (point.radius > 0) point.radius else 0,
                    // NaN or below 0 is 0; null is its whole range.
                    .shadow_range = if (point.shadow_range) |reach| (if (reach > 0) @min(reach, @max(point.range, 0)) else 0) else @max(point.range, 0),
                    .shadow_rays = point.shadow_rays,
                }),
            };
            if (scene.point_of_view) |point_of_view| if (std.meta.eql(point_of_view, visit.id)) if (node.camera) |node_camera| {
                camera = node_camera;
                eye = visit.world.transformPoint(mod.Vec3.zero);
                view = visit.world.inverse();
            };
        }

        // Opaque by order alone, keeping the walk's order within one.
        std.sort.block(SceneDraw, opaque_draws.items, {}, Self.drawsBefore);
        Self.sortBackToFront(translucent_draws.items, eye);
        const opaque_count = opaque_draws.items.len;
        const draws = try allocator.alloc(SceneDraw, opaque_count + translucent_draws.items.len);
        errdefer allocator.free(draws);
        @memcpy(draws[0..opaque_count], opaque_draws.items);
        @memcpy(draws[opaque_count..], translucent_draws.items);
        for (directional_lights.items) |*light| {
            if (light.shadow != null) light.shadow = Self.shadowProjection(light.direction, draws);
        }

        const directional = try directional_lights.toOwnedSlice(allocator);
        errdefer allocator.free(directional);
        const points = try point_lights.toOwnedSlice(allocator);
        const self = Self{
            .draws = draws,
            .opaque_count = opaque_count,
            .directional_lights = directional,
            .environment = scene.environment,
            .exposure = if (std.math.isFinite(scene.exposure) and scene.exposure > 0) scene.exposure else 1,
            .tone_mapping = scene.tone_mapping,
            .point_lights = points,
            .ambient = Self.linear(scene.ambient).scale(scene.ambient_intensity),
            .view = view,
            .projection = camera.projection(aspect),
            .eye = eye,
        };
        return self;
    }

    /// Frees what `gather` allocated.
    ///
    /// - `self`: the frame.
    /// - `allocator`: the allocator it was gathered with.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.draws);
        allocator.free(self.directional_lights);
        allocator.free(self.point_lights);
    }

    /// A light's cookie, if it can be drawn (`ScenePlaneTexture.isUsable`).
    ///
    /// - `cookie`: the light's cookie, or null.
    /// - Returns: the cookie, or null.
    fn usableCookie(cookie: ?mod.ScenePlaneTexture) ?mod.ScenePlaneTexture {
        const value = cookie orelse return null;
        return if (value.isUsable()) value else null;
    }

    /// A color's red, green and blue in linear light, from sRGB.
    ///
    /// - `color`: the color.
    /// - Returns: the linear channels.
    pub fn linear(color: renderer.Color) mod.Vec3 {
        return .{ .x = Self.linearChannel(color.r), .y = Self.linearChannel(color.g), .z = Self.linearChannel(color.b) };
    }

    /// The projection into a directional light's shadow map: an orthographic
    /// box along the light, fitted across it to the shapes that receive
    /// shadows and deep enough to hold every shape that casts one.
    ///
    /// - `direction`: the way the light travels, a unit vector.
    /// - `draws`: the frame's shapes.
    /// - Returns: the projection, or null when no shape casts a shadow or
    ///   none receives one.
    pub fn shadowProjection(direction: mod.Vec3, draws: []const SceneDraw) ?mod.Mat4 {
        var receivers = mod.SceneBounds.empty;
        var casters = mod.SceneBounds.empty;
        for (draws) |draw| {
            if (draw.receives_shadows) receivers = receivers.merged(draw.bounds);
            if (draw.casts_shadows) casters = casters.merged(draw.bounds);
        }
        if (receivers.isEmpty() or casters.isEmpty()) return null;
        const everything = receivers.merged(casters);
        const center = receivers.center();
        const reach = everything.max.sub(everything.min).length() + 1;
        const up = if (@abs(direction.y) > 0.99) mod.Vec3.init(0, 0, 1) else mod.Vec3.up;
        const light_view = mod.Mat4.lookAt(center.sub(direction.scale(reach)), center, up);
        // Across the light: the receivers. Along it: everything, so a caster
        // between the light and the receivers is never cut off.
        const across = receivers.transformed(light_view);
        const along = everything.transformed(light_view);
        const margin = 0.01 * reach;
        const projection = mod.Mat4.orthographic(across.min.x - margin, across.max.x + margin, across.min.y - margin, across.max.y + margin, -along.max.z - margin, -along.min.z + margin);
        return projection.multiply(light_view);
    }

    /// One sRGB channel in linear light.
    ///
    /// - `channel`: the channel, 0 to 1.
    /// - Returns: the linear channel.
    fn linearChannel(channel: f32) f32 {
        const clamped = std.math.clamp(channel, 0, 1);
        if (clamped <= 0.04045) return clamped / 12.92;
        return std.math.pow(f32, (clamped + 0.055) / 1.055, 2.4);
    }

    /// Sorts translucent shapes by their rendering order, then from the
    /// farthest to the nearest by their centers' distance from the eye.
    ///
    /// - `draws`: the shapes.
    /// - `eye`: where the camera is.
    fn sortBackToFront(draws: []SceneDraw, eye: mod.Vec3) void {
        std.mem.sort(SceneDraw, draws, eye, Self.translucentDrawsBefore);
    }

    /// Whether one shape draws before another by rendering order alone.
    ///
    /// - `context`: unused.
    /// - `first`: one shape.
    /// - `second`: the other.
    /// - Returns: true when the first's order is lower.
    fn drawsBefore(context: void, first: SceneDraw, second: SceneDraw) bool {
        _ = context;
        return first.rendering_order < second.rendering_order;
    }

    /// Whether one shape draws before another: a lower rendering order, or
    /// within one, a center farther from the eye.
    ///
    /// - `eye`: where the camera is.
    /// - `first`: one shape.
    /// - `second`: the other.
    /// - Returns: true when the first draws first.
    fn translucentDrawsBefore(eye: mod.Vec3, first: SceneDraw, second: SceneDraw) bool {
        if (first.rendering_order != second.rendering_order) return first.rendering_order < second.rendering_order;
        const first_distance = first.bounds.center().sub(eye).length();
        const second_distance = second.bounds.center().sub(eye).length();
        return first_distance > second_distance;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a frame draws opaque shapes first, then translucent ones back to front" {
    const allocator = std.testing.allocator;
    var scene = try mod.Scene.init(allocator);
    defer scene.deinit();
    const glass = renderer.Color.white.withAlpha(0.5);
    _ = try scene.addChild(scene.root(), .{ .name = "near glass", .geometry = .{ .box = .{} }, .material = .{ .base_color = glass }, .transform = .{ .position = mod.Vec3.init(0, 0, 2) } });
    _ = try scene.addChild(scene.root(), .{ .name = "solid", .geometry = .{ .sphere = .{} } });
    _ = try scene.addChild(scene.root(), .{ .name = "far glass", .geometry = .{ .box = .{} }, .material = .{ .base_color = glass }, .transform = .{ .position = mod.Vec3.init(0, 0, -2) } });
    var frame = try SceneFrame.gather(allocator, &scene, 1);
    defer frame.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), frame.draws.len);
    try std.testing.expectEqual(@as(usize, 1), frame.opaque_count);
    try std.testing.expect(frame.draws[0].geometry == .sphere);
    // The default camera sits at +5 Z: the far glass first.
    try std.testing.expect(frame.draws[1].world.transformPoint(mod.Vec3.zero).z < frame.draws[2].world.transformPoint(mod.Vec3.zero).z);
    try std.testing.expect(!frame.draws[1].casts_shadows);
}

test "a frame keeps the first lights in the graph up to its limits, each moving with its node" {
    const allocator = std.testing.allocator;
    var scene = try mod.Scene.init(allocator);
    defer scene.deinit();
    const rig = try scene.addChild(scene.root(), .{ .transform = .{ .position = mod.Vec3.init(0, 3, 0) } });
    for (0..SceneFrame.max_point_lights + 2) |index| {
        _ = try scene.addChild(rig, .{ .light = .{ .kind = .{ .point = .{ .range = @floatFromInt(index + 1) } } } });
    }
    for (0..SceneFrame.max_directional_lights + 1) |_| {
        _ = try scene.addChild(scene.root(), .{ .light = .{}, .transform = .{ .rotation = mod.Quaternion.fromAxisAngle(mod.Vec3.init(1, 0, 0), -std.math.pi / 2.0) } });
    }
    var frame = try SceneFrame.gather(allocator, &scene, 1);
    defer frame.deinit(allocator);
    try std.testing.expectEqual(@as(usize, SceneFrame.max_point_lights), frame.point_lights.len);
    try std.testing.expectEqual(@as(f32, 1), frame.point_lights[0].range);
    try std.testing.expect(frame.point_lights[0].position.approxEql(mod.Vec3.init(0, 3, 0), 1e-5));
    try std.testing.expectEqual(@as(usize, SceneFrame.max_directional_lights), frame.directional_lights.len);
    // Turned -90° about X, a light's -Z points down.
    try std.testing.expect(frame.directional_lights[0].direction.approxEql(mod.Vec3.init(0, -1, 0), 1e-5));
    // Nothing to shade: no shadow.
    try std.testing.expectEqual(null, frame.directional_lights[0].shadow);
}

test "a light's source size gives its soft shadow's width, and one not a number or negative gives none" {
    const allocator = std.testing.allocator;
    var scene = try mod.Scene.init(allocator);
    defer scene.deinit();
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .directional = .{ .angular_diameter = 4 } } } });
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .directional = .{ .angular_diameter = std.math.nan(f32) } } } });
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .point = .{ .casts_shadows = true, .radius = 0.25 } } } });
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .point = .{ .radius = std.math.nan(f32) } } } });
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .point = .{ .radius = -1 } } } });
    var frame = try SceneFrame.gather(allocator, &scene, 1);
    defer frame.deinit(allocator);
    try std.testing.expectApproxEqAbs(std.math.degreesToRadians(@as(f32, 2)), frame.directional_lights[0].angular_radius, 1e-6);
    try std.testing.expectEqual(@as(f32, 0), frame.directional_lights[1].angular_radius);
    try std.testing.expect(frame.point_lights[0].casts_shadows);
    try std.testing.expectEqual(@as(f32, 0.25), frame.point_lights[0].radius);
    try std.testing.expectEqual(@as(f32, 0), frame.point_lights[1].radius);
    try std.testing.expectEqual(@as(f32, 0), frame.point_lights[2].radius);
}

test "the camera follows the point-of-view node, its parent included" {
    const allocator = std.testing.allocator;
    var scene = try mod.Scene.init(allocator);
    defer scene.deinit();
    const dolly = try scene.addChild(scene.root(), .{ .transform = .{ .position = mod.Vec3.init(0, 0, 10) } });
    scene.point_of_view = try scene.addChild(dolly, .{ .camera = .{ .field_of_view = 45 } });
    var frame = try SceneFrame.gather(allocator, &scene, 2);
    defer frame.deinit(allocator);
    try std.testing.expect(frame.eye.approxEql(mod.Vec3.init(0, 0, 10), 1e-5));
    try std.testing.expect(frame.view.transformPoint(mod.Vec3.zero).approxEql(mod.Vec3.init(0, 0, -10), 1e-5));
    try std.testing.expect(frame.projection.approxEql((mod.SceneCamera{ .field_of_view = 45 }).projection(2), 1e-6));
}

test "a shadow projection holds the receivers across it and every caster along it" {
    const allocator = std.testing.allocator;
    var scene = try mod.Scene.init(allocator);
    defer scene.deinit();
    const floor_turn = mod.Quaternion.fromAxisAngle(mod.Vec3.init(1, 0, 0), -std.math.pi / 2.0);
    _ = try scene.addChild(scene.root(), .{ .geometry = .{ .plane = .{ .width = 10, .height = 10 } }, .transform = .{ .rotation = floor_turn }, .casts_shadows = false });
    _ = try scene.addChild(scene.root(), .{ .geometry = .{ .box = .{} }, .transform = .{ .position = mod.Vec3.init(0, 3, 0) }, .receives_shadows = false });
    _ = try scene.addChild(scene.root(), .{ .light = .{}, .transform = .{ .rotation = floor_turn } });
    var frame = try SceneFrame.gather(allocator, &scene, 1);
    defer frame.deinit(allocator);
    const shadow = frame.directional_lights[0].shadow.?;
    // The floor's corners land inside the map; the box above it inside its depth.
    for ([_]mod.Vec3{ mod.Vec3.init(-5, 0, -5), mod.Vec3.init(5, 0, 5), mod.Vec3.init(0, 3.5, 0), mod.Vec3.init(0, 2.5, 0) }) |point| {
        const projected = shadow.transformPoint(point);
        try std.testing.expect(@abs(projected.x) <= 1 and @abs(projected.y) <= 1);
        try std.testing.expect(projected.z >= 0 and projected.z <= 1);
    }
    // The box is nearer the light than the floor.
    try std.testing.expect(shadow.transformPoint(mod.Vec3.init(0, 3, 0)).z < shadow.transformPoint(mod.Vec3.zero).z);
}

test "sRGB colors turn linear: black and white stay, mid gray darkens" {
    try std.testing.expect(SceneFrame.linear(renderer.Color.black).approxEql(mod.Vec3.zero, 0));
    try std.testing.expect(SceneFrame.linear(renderer.Color.white).approxEql(mod.Vec3.one, 1e-6));
    try std.testing.expectApproxEqAbs(@as(f32, 0.2140), SceneFrame.linear(renderer.Color.rgb(0.5, 0.5, 0.5)).x, 1e-3);
}

test "translucent shapes draw by rendering order, then back to front; opaque ones by order" {
    const allocator = std.testing.allocator;
    var scene = try mod.Scene.init(allocator);
    defer scene.deinit();
    const glass = mod.SceneMaterial{ .base_color = renderer.Color.white.withAlpha(0.5) };
    // The camera is 5 back along +Z: the near pane is at z 4, the far ones at z -20.
    _ = try scene.addChild(scene.root(), .{ .name = "near", .geometry = .{ .box = .{} }, .material = glass, .transform = .{ .position = mod.Vec3.init(0, 0, 4) } });
    _ = try scene.addChild(scene.root(), .{ .name = "far", .geometry = .{ .box = .{} }, .material = glass, .transform = .{ .position = mod.Vec3.init(0, 0, -20) } });
    _ = try scene.addChild(scene.root(), .{ .name = "late", .geometry = .{ .box = .{} }, .material = glass, .rendering_order = 1, .transform = .{ .position = mod.Vec3.init(0, 0, -30) } });
    _ = try scene.addChild(scene.root(), .{ .name = "backdrop", .geometry = .{ .box = .{} }, .rendering_order = -1 });
    _ = try scene.addChild(scene.root(), .{ .name = "ground", .geometry = .{ .box = .{} } });
    var frame = try SceneFrame.gather(allocator, &scene, 1);
    defer frame.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), frame.opaque_count);
    try std.testing.expectEqual(@as(i32, -1), frame.draws[0].rendering_order);
    // Back to front within order 0, and the later order last though it's farthest.
    try std.testing.expectEqual(@as(f32, -20), frame.draws[2].world.transformPoint(mod.Vec3.zero).z);
    try std.testing.expectEqual(@as(f32, 4), frame.draws[3].world.transformPoint(mod.Vec3.zero).z);
    try std.testing.expectEqual(@as(i32, 1), frame.draws[4].rendering_order);
}

test "a node's opacity multiplies down the tree into its shapes' alpha; at 0 nothing draws, its light still shines" {
    const allocator = std.testing.allocator;
    var scene = try mod.Scene.init(allocator);
    defer scene.deinit();
    const parent = try scene.addChild(scene.root(), .{ .geometry = .{ .box = .{} }, .opacity = 0.5 });
    _ = try scene.addChild(parent, .{ .geometry = .{ .sphere = .{} }, .opacity = 0.5, .material = .{ .base_color = renderer.Color.white.withAlpha(0.8) } });
    const hidden = try scene.addChild(scene.root(), .{ .geometry = .{ .box = .{} }, .opacity = 0 });
    _ = try scene.addChild(hidden, .{ .light = .{ .kind = .{ .point = .{} } } });
    var frame = try SceneFrame.gather(allocator, &scene, 1);
    defer frame.deinit(allocator);
    // Both faded shapes are translucent; the invisible one is gone.
    try std.testing.expectEqual(@as(usize, 0), frame.opaque_count);
    try std.testing.expectEqual(@as(usize, 2), frame.draws.len);
    var alphas = [2]f32{ frame.draws[0].material.base_color.a, frame.draws[1].material.base_color.a };
    std.mem.sort(f32, &alphas, {}, std.sort.asc(f32));
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), alphas[0], 1e-6); // 0.8 × 0.5 × 0.5
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), alphas[1], 1e-6);
    for (frame.draws) |draw| try std.testing.expect(!draw.casts_shadows);
    try std.testing.expectEqual(@as(usize, 1), frame.point_lights.len);
}

test "a light's cookie is carried to the frame, and one spanning no plane is dropped" {
    const allocator = std.testing.allocator;
    var scene = try mod.Scene.init(allocator);
    defer scene.deinit();
    const pixels = [_]u8{ 255, 255, 255, 255 };
    const texture = mod.SceneTexture{ .image = .{ .width = 1, .height = 1, .pixels = &pixels } };
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .directional = .{ .cookie = mod.ScenePlaneTexture.level(texture, mod.Vec3.init(12, 1600, 0), 4000) } } } });
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .directional = .{ .cookie = mod.ScenePlaneTexture.level(texture, mod.Vec3.init(0, 10, 0), 0) } } } });
    var frame = try SceneFrame.gather(allocator, &scene, 1);
    defer frame.deinit(allocator);
    try std.testing.expectEqual(@as(f32, 1600), frame.directional_lights[0].cookie.?.origin.y);
    try std.testing.expectEqual(@as(f32, 12), frame.directional_lights[0].cookie.?.origin.x);
    try std.testing.expect(frame.directional_lights[1].cookie == null);
}
