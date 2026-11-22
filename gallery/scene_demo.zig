//! The Scenes section's 3D card: a `SceneView` of a spinning,
//! textured cube on a floor, lit by a directional light that casts its
//! shadow and a warm point light, beside a sphere and a translucent pane.

const std = @import("std");
const log = std.log.scoped(.ziggui_gallery_scene_demo);
const gallery = @import("module.zig");
const ziggui = @import("ziggui");

/// The side of the cube's checkerboard texture, in pixels.
const checker_side = 64;

/// The cube's texture: an 8 × 8 checkerboard in two tones of the accent's
/// blue, made at compile time so its pixels never move.
const checker_pixels: [checker_side * checker_side * 4]u8 = pixels: {
    @setEvalBranchQuota(100_000);
    var pixels: [checker_side * checker_side * 4]u8 = undefined;
    for (0..checker_side) |y| for (0..checker_side) |x| {
        const light = ((x / 8) + (y / 8)) % 2 == 0;
        const color = if (light) [4]u8{ 0xe8, 0xf0, 0xff, 0xff } else [4]u8{ 0x2f, 0x6f, 0xe4, 0xff };
        @memcpy(pixels[(y * checker_side + x) * 4 ..][0..4], &color);
    };
    break :pixels pixels;
};

/// A floor turned from facing +Z to facing up.
const floor_turn = ziggui.Quaternion{ .x = -std.math.sqrt1_2, .w = std.math.sqrt1_2 };

/// The Scenes section's scene and the cube it spins.
pub const SceneDemo = struct {
    const Self = @This();

    /// The cube's turn per millisecond of the frame clock, in radians.
    const spin_per_ms = 0.0006;

    /// The scene the card shows.
    scene: ziggui.Scene,
    /// The spinning cube.
    cube: ziggui.SceneNodeId,

    /// Builds the scene: the camera, floor, cube, sphere, pane and lights.
    ///
    /// - `allocator`: what the scene keeps its nodes with.
    /// - Returns: the demo; propagates allocation failure.
    pub fn init(allocator: std.mem.Allocator) !Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        var scene = try ziggui.Scene.init(allocator);
        errdefer scene.deinit();
        const root = scene.root();
        scene.background = ziggui.Color.hex(0x1f2430);
        scene.ambient_intensity = 0.3;
        scene.camera_target = ziggui.Vec3.init(0, 0.5, 0);

        var camera = ziggui.SceneNode{ .name = "camera", .camera = .{ .field_of_view = 45 }, .transform = .{ .position = ziggui.Vec3.init(0, 2.6, 6) } };
        camera.lookAt(scene.camera_target, ziggui.Vec3.up);
        scene.point_of_view = try scene.addChild(root, camera);

        _ = try scene.addChild(root, .{
            .name = "floor",
            .geometry = .{ .plane = .{ .width = 8, .height = 8 } },
            .material = .{ .base_color = ziggui.Color.hex(0xc9ccd3), .specular = 0.1 },
            .transform = .{ .rotation = floor_turn },
            .casts_shadows = false,
        });
        const cube = try scene.addChild(root, .{
            .name = "cube",
            .geometry = .{ .box = .{ .width = 1.2, .height = 1.2, .length = 1.2 } },
            .material = .{ .texture = .{ .image = .{ .width = checker_side, .height = checker_side, .pixels = &checker_pixels } }, .specular = 0.6, .shininess = 48 },
            .transform = .{ .position = ziggui.Vec3.init(0, 0.9, 0) },
        });
        _ = try scene.addChild(root, .{
            .name = "sphere",
            .geometry = .{ .sphere = .{ .radius = 0.45 } },
            .material = .{ .base_color = ziggui.Color.hex(0xe0533d), .specular = 0.8, .shininess = 64 },
            .transform = .{ .position = ziggui.Vec3.init(1.7, 0.45, 0.6) },
        });
        _ = try scene.addChild(root, .{
            .name = "pane",
            .geometry = .{ .plane = .{ .width = 1.6, .height = 1.2 } },
            .material = .{ .base_color = ziggui.Color.hex(0x5ab0ff).withAlpha(0.35), .specular = 0.9, .shininess = 96 },
            .transform = .{ .position = ziggui.Vec3.init(-1.6, 0.6, 0.9), .rotation = ziggui.Quaternion.fromAxisAngle(ziggui.Vec3.up, 0.5) },
        });

        var sun = ziggui.SceneNode{ .name = "sun", .light = .{ .intensity = 0.9 }, .transform = .{ .position = ziggui.Vec3.init(3, 6, 4) } };
        sun.lookAt(ziggui.Vec3.zero, ziggui.Vec3.up);
        _ = try scene.addChild(root, sun);
        _ = try scene.addChild(root, .{
            .name = "lamp",
            .light = .{ .kind = .{ .point = .{ .range = 8 } }, .color = ziggui.Color.hex(0xffc37a), .intensity = 0.8 },
            .transform = .{ .position = ziggui.Vec3.init(-2, 2, 2) },
        });

        const self = Self{ .scene = scene, .cube = cube };
        return self;
    }

    /// Frees the scene.
    ///
    /// - `self`: the demo.
    pub fn deinit(self: *Self) void {
        self.scene.deinit();
    }

    /// The 3D card: the cube turned for the frame clock's time, drawn with
    /// camera control on (drag to orbit; pinch or ⌘-scroll to zoom).
    ///
    /// - `self`: the demo.
    /// - `theme`: the theme this frame draws with.
    /// - Returns: the card.
    pub fn card(self: *Self, theme: ziggui.Theme) ziggui.View {
        if (self.scene.node(self.cube)) |cube| {
            // Whole turns dropped in f64, so the spin never jumps as the clock grows.
            const angle = @as(f64, @floatFromInt(ziggui.FrameClock.shared().time())) * spin_per_ms;
            const turn: f32 = @floatCast(@mod(angle, 2 * std.math.pi));
            cube.transform.rotation = ziggui.Quaternion.fromAxisAngle(ziggui.Vec3.init(0.3, 1, 0.1), turn);
        }
        return gallery.Card.view(
            theme,
            "SceneView: a lit, textured cube casting a shadow, a translucent pane (drag to orbit; pinch or ⌘-scroll to zoom)",
            "ziggui.SceneView · ziggui.Scene · ziggui.SceneNode · ziggui.SceneCameraInput",
            ziggui.SceneView(&self.scene, .{ .allows_camera_control = true, .animating = true }).frameMaxWidth().frameHeight(440),
        );
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the demo's scene holds its camera, shapes and lights, and casts the sun's shadow" {
    const allocator = std.testing.allocator;
    var demo = try SceneDemo.init(allocator);
    defer demo.deinit();
    var frame = try ziggui.SceneFrame.gather(allocator, &demo.scene, 2);
    defer frame.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), frame.opaque_count);
    try std.testing.expectEqual(@as(usize, 4), frame.draws.len);
    try std.testing.expectEqual(@as(usize, 1), frame.directional_lights.len);
    try std.testing.expect(frame.directional_lights[0].shadow != null);
    try std.testing.expectEqual(@as(usize, 1), frame.point_lights.len);
    try std.testing.expect(frame.eye.approxEql(ziggui.Vec3.init(0, 2.6, 6), 1e-5));
}
