//! A node's shape: a primitive (box, sphere, plane, cylinder) or a mesh the
//! app supplies, and the vertices the GPU draws it with.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_geometry);
const mod = @import("module.zig");

/// One vertex as the scene shaders read it: position, normal and texture
/// coordinates (u right, v down).
pub const SceneVertex = extern struct {
    const Self = @This();

    /// The position, in the node's units.
    position: [3]f32,
    /// The unit normal.
    normal: [3]f32,
    /// The texture coordinates.
    uv: [2]f32,
};

/// A box centered on the origin (SceneKit's `SCNBox`).
pub const SceneBox = struct {
    const Self = @This();

    /// Its extent along X.
    width: f32 = 1,
    /// Its extent along Y.
    height: f32 = 1,
    /// Its extent along Z.
    length: f32 = 1,
};

/// A sphere centered on the origin (SceneKit's `SCNSphere`).
pub const SceneSphere = struct {
    const Self = @This();

    /// Its radius.
    radius: f32 = 0.5,
};

/// A rectangle in the XY plane facing +Z, centered on the origin (SceneKit's
/// `SCNPlane`; turn it -90° about X for a floor).
pub const ScenePlane = struct {
    const Self = @This();

    /// Its extent along X.
    width: f32 = 1,
    /// Its extent along Y.
    height: f32 = 1,
};

/// A capped cylinder along Y, centered on the origin (SceneKit's `SCNCylinder`).
pub const SceneCylinder = struct {
    const Self = @This();

    /// Its radius.
    radius: f32 = 0.5,
    /// Its extent along Y.
    height: f32 = 1,
};

/// Triangles the app supplies, in its memory, which must outlive every frame
/// that draws them. The GPU keeps a copy keyed by the slices and
/// `generation`: change `generation` after changing the data in place.
pub const SceneMesh = struct {
    const Self = @This();

    /// Each vertex's position.
    positions: []const [3]f32,
    /// Each vertex's unit normal, as many as `positions`.
    normals: []const [3]f32,
    /// Each vertex's texture coordinates, as many as `positions`, or null for none.
    uvs: ?[]const [2]f32 = null,
    /// Three indices into `positions` per triangle, counter-clockwise seen from outside.
    indices: []const u32,
    /// Changes when the data changes in place.
    generation: u64 = 0,

    /// Checks the mesh can be drawn: normals (and uvs) for every position,
    /// whole triangles, and every index in range.
    ///
    /// - `self`: the mesh.
    /// - Returns: nothing; `error.InvalidMesh` when it cannot be drawn.
    pub fn validate(self: *const Self) error{InvalidMesh}!void {
        if (self.normals.len != self.positions.len) return error.InvalidMesh;
        if (self.uvs) |uvs| if (uvs.len != self.positions.len) return error.InvalidMesh;
        if (self.indices.len == 0 or self.indices.len % 3 != 0) return error.InvalidMesh;
        for (self.indices) |index| if (index >= self.positions.len) return error.InvalidMesh;
    }
};

/// The vertices and triangles a geometry is drawn with, owned by the
/// allocator that built them.
pub const SceneGeometryData = struct {
    const Self = @This();

    /// The vertices.
    vertices: []SceneVertex,
    /// Three indices into `vertices` per triangle.
    indices: []u32,

    /// Frees the vertices and indices.
    ///
    /// - `self`: the data.
    /// - `allocator`: the allocator that built them.
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
    }
};

/// A node's shape.
pub const SceneGeometry = union(enum) {
    const Self = @This();

    /// The segments around a sphere or a cylinder.
    pub const segments = 48;
    /// The rings from a sphere's top to its bottom.
    pub const rings = 24;

    /// A box.
    box: SceneBox,
    /// A sphere.
    sphere: SceneSphere,
    /// A rectangle facing +Z.
    plane: ScenePlane,
    /// A capped cylinder.
    cylinder: SceneCylinder,
    /// Triangles the app supplies.
    mesh: SceneMesh,

    /// What identifies the geometry's vertices on the GPU: its shape and
    /// sizes, or a mesh's slices and generation.
    ///
    /// - `self`: the geometry.
    /// - Returns: the key.
    pub fn key(self: *const Self) u64 {
        var hasher = std.hash.Wyhash.init(@backingInt(self.*));
        switch (self.*) {
            .box => |box| hasher.update(std.mem.asBytes(&box)),
            .sphere => |sphere| hasher.update(std.mem.asBytes(&sphere)),
            .plane => |plane| hasher.update(std.mem.asBytes(&plane)),
            .cylinder => |cylinder| hasher.update(std.mem.asBytes(&cylinder)),
            .mesh => |mesh| {
                const identity = [_]u64{ @intFromPtr(mesh.positions.ptr), mesh.positions.len, @intFromPtr(mesh.indices.ptr), mesh.indices.len, mesh.generation };
                hasher.update(std.mem.asBytes(&identity));
            },
        }
        return hasher.final();
    }

    /// The box that holds the geometry, in its node's units.
    ///
    /// - `self`: the geometry.
    /// - Returns: the bounds; empty for a mesh with no positions.
    pub fn bounds(self: *const Self) mod.SceneBounds {
        return switch (self.*) {
            .box => |box| Self.centered(box.width, box.height, box.length),
            .sphere => |sphere| Self.centered(sphere.radius * 2, sphere.radius * 2, sphere.radius * 2),
            .plane => |plane| Self.centered(plane.width, plane.height, 0),
            .cylinder => |cylinder| Self.centered(cylinder.radius * 2, cylinder.height, cylinder.radius * 2),
            .mesh => |mesh| bounds: {
                var result = mod.SceneBounds.empty;
                for (mesh.positions) |position| result = result.including(.{ .x = position[0], .y = position[1], .z = position[2] });
                break :bounds result;
            },
        };
    }

    /// Builds the vertices and triangles the geometry is drawn with.
    ///
    /// - `self`: the geometry.
    /// - `allocator`: what the data is allocated with.
    /// - Returns: the data; `error.InvalidMesh` for a mesh that cannot be
    ///   drawn; propagates allocation failure.
    pub fn build(self: *const Self, allocator: std.mem.Allocator) error{ OutOfMemory, InvalidMesh }!SceneGeometryData {
        return switch (self.*) {
            .box => |box| Self.buildBox(allocator, box),
            .sphere => |sphere| Self.buildSphere(allocator, sphere),
            .plane => |plane| Self.buildPlane(allocator, plane),
            .cylinder => |cylinder| Self.buildCylinder(allocator, cylinder),
            .mesh => |mesh| Self.buildMesh(allocator, mesh),
        };
    }

    /// A box of the given extents centered on the origin.
    ///
    /// - `width`: its extent along X.
    /// - `height`: its extent along Y.
    /// - `length`: its extent along Z.
    /// - Returns: the bounds.
    fn centered(width: f32, height: f32, length: f32) mod.SceneBounds {
        const half = mod.Vec3.init(@abs(width) / 2, @abs(height) / 2, @abs(length) / 2);
        return mod.SceneBounds.init(half.scale(-1), half);
    }

    /// A box's 24 vertices (four a face, so each face keeps its normal) and
    /// 12 triangles.
    ///
    /// - `allocator`: what the data is allocated with.
    /// - `box`: the box.
    /// - Returns: the data; propagates allocation failure.
    fn buildBox(allocator: std.mem.Allocator, box: SceneBox) error{OutOfMemory}!SceneGeometryData {
        const half = [3]f32{ box.width / 2, box.height / 2, box.length / 2 };
        // Each face: its normal, then the axes its u and v run along.
        const faces = [6][3][3]f32{
            .{ .{ 1, 0, 0 }, .{ 0, 0, -1 }, .{ 0, -1, 0 } },
            .{ .{ -1, 0, 0 }, .{ 0, 0, 1 }, .{ 0, -1, 0 } },
            .{ .{ 0, 1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, 1 } },
            .{ .{ 0, -1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, -1 } },
            .{ .{ 0, 0, 1 }, .{ 1, 0, 0 }, .{ 0, -1, 0 } },
            .{ .{ 0, 0, -1 }, .{ -1, 0, 0 }, .{ 0, -1, 0 } },
        };
        const vertices = try allocator.alloc(SceneVertex, 24);
        errdefer allocator.free(vertices);
        const indices = try allocator.alloc(u32, 36);
        for (faces, 0..) |face, face_index| {
            const corner_uvs = [4][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 } };
            for (corner_uvs, 0..) |uv, corner| {
                var position: [3]f32 = undefined;
                for (0..3) |axis| {
                    const along_u = face[1][axis] * (uv[0] * 2 - 1);
                    const along_v = face[2][axis] * (uv[1] * 2 - 1);
                    position[axis] = (face[0][axis] + along_u + along_v) * half[axis];
                }
                vertices[face_index * 4 + corner] = .{ .position = position, .normal = face[0], .uv = uv };
            }
            const base: u32 = @intCast(face_index * 4);
            Self.quad(indices[face_index * 6 ..][0..6], base, base + 3, base + 2, base + 1);
        }
        return .{ .vertices = vertices, .indices = indices };
    }

    /// A UV sphere: `rings` + 1 rows of `segments` + 1 vertices (the seam
    /// doubled so its uvs wrap).
    ///
    /// - `allocator`: what the data is allocated with.
    /// - `sphere`: the sphere.
    /// - Returns: the data; propagates allocation failure.
    fn buildSphere(allocator: std.mem.Allocator, sphere: SceneSphere) error{OutOfMemory}!SceneGeometryData {
        const columns = segments + 1;
        const vertices = try allocator.alloc(SceneVertex, (rings + 1) * columns);
        errdefer allocator.free(vertices);
        const indices = try allocator.alloc(u32, rings * segments * 6);
        for (0..rings + 1) |ring| {
            const down = @as(f32, @floatFromInt(ring)) / rings;
            const polar = down * std.math.pi;
            for (0..columns) |segment| {
                const around = @as(f32, @floatFromInt(segment)) / segments;
                const azimuth = around * 2 * std.math.pi;
                const normal = [3]f32{ @sin(polar) * @sin(azimuth), @cos(polar), @sin(polar) * @cos(azimuth) };
                vertices[ring * columns + segment] = .{
                    .position = .{ normal[0] * sphere.radius, normal[1] * sphere.radius, normal[2] * sphere.radius },
                    .normal = normal,
                    .uv = .{ around, down },
                };
            }
        }
        for (0..rings) |ring| for (0..segments) |segment| {
            const top: u32 = @intCast(ring * columns + segment);
            const bottom: u32 = top + columns;
            Self.quad(indices[(ring * segments + segment) * 6 ..][0..6], top, bottom, bottom + 1, top + 1);
        };
        return .{ .vertices = vertices, .indices = indices };
    }

    /// A rectangle facing +Z: four vertices, two triangles.
    ///
    /// - `allocator`: what the data is allocated with.
    /// - `plane`: the plane.
    /// - Returns: the data; propagates allocation failure.
    fn buildPlane(allocator: std.mem.Allocator, plane: ScenePlane) error{OutOfMemory}!SceneGeometryData {
        const half_width = plane.width / 2;
        const half_height = plane.height / 2;
        const vertices = try allocator.dupe(SceneVertex, &.{
            .{ .position = .{ -half_width, half_height, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 0, 0 } },
            .{ .position = .{ -half_width, -half_height, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 0, 1 } },
            .{ .position = .{ half_width, -half_height, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 1, 1 } },
            .{ .position = .{ half_width, half_height, 0 }, .normal = .{ 0, 0, 1 }, .uv = .{ 1, 0 } },
        });
        errdefer allocator.free(vertices);
        const indices = try allocator.alloc(u32, 6);
        Self.quad(indices[0..6], 0, 1, 2, 3);
        return .{ .vertices = vertices, .indices = indices };
    }

    /// A capped cylinder: its side (`segments` + 1 columns of two vertices)
    /// and each cap (a center and a ring of `segments` + 1).
    ///
    /// - `allocator`: what the data is allocated with.
    /// - `cylinder`: the cylinder.
    /// - Returns: the data; propagates allocation failure.
    fn buildCylinder(allocator: std.mem.Allocator, cylinder: SceneCylinder) error{OutOfMemory}!SceneGeometryData {
        const columns = segments + 1;
        const side_count = columns * 2;
        const cap_count = columns + 1;
        const vertices = try allocator.alloc(SceneVertex, side_count + cap_count * 2);
        errdefer allocator.free(vertices);
        const indices = try allocator.alloc(u32, segments * 6 + segments * 3 * 2);
        const half = cylinder.height / 2;
        for (0..columns) |segment| {
            const around = @as(f32, @floatFromInt(segment)) / segments;
            const azimuth = around * 2 * std.math.pi;
            const x = @sin(azimuth);
            const z = @cos(azimuth);
            vertices[segment * 2] = .{ .position = .{ x * cylinder.radius, half, z * cylinder.radius }, .normal = .{ x, 0, z }, .uv = .{ around, 0 } };
            vertices[segment * 2 + 1] = .{ .position = .{ x * cylinder.radius, -half, z * cylinder.radius }, .normal = .{ x, 0, z }, .uv = .{ around, 1 } };
        }
        for (0..segments) |segment| {
            const top: u32 = @intCast(segment * 2);
            Self.quad(indices[segment * 6 ..][0..6], top, top + 1, top + 3, top + 2);
        }
        // The caps: up on top, down below, each a fan around its center.
        for ([2]f32{ 1, -1 }, 0..) |side, cap| {
            const center: u32 = @intCast(side_count + cap * cap_count);
            vertices[center] = .{ .position = .{ 0, half * side, 0 }, .normal = .{ 0, side, 0 }, .uv = .{ 0.5, 0.5 } };
            for (0..columns) |segment| {
                const azimuth = @as(f32, @floatFromInt(segment)) / segments * 2 * std.math.pi;
                const x = @sin(azimuth);
                const z = @cos(azimuth);
                vertices[center + 1 + segment] = .{ .position = .{ x * cylinder.radius, half * side, z * cylinder.radius }, .normal = .{ 0, side, 0 }, .uv = .{ 0.5 + x / 2, 0.5 - z * side / 2 } };
            }
            const fans = indices[segments * 6 + cap * segments * 3 ..][0 .. segments * 3];
            for (0..segments) |segment| {
                const ring: u32 = center + 1 + @as(u32, @intCast(segment));
                // Counter-clockwise from outside: around +Y on top, the other way below.
                fans[segment * 3 ..][0..3].* = if (cap == 0) .{ center, ring, ring + 1 } else .{ center, ring + 1, ring };
            }
        }
        return .{ .vertices = vertices, .indices = indices };
    }

    /// A mesh's vertices and triangles, copied; uvs are zero where it has none.
    ///
    /// - `allocator`: what the data is allocated with.
    /// - `mesh`: the mesh.
    /// - Returns: the data; `error.InvalidMesh` when it cannot be drawn;
    ///   propagates allocation failure.
    fn buildMesh(allocator: std.mem.Allocator, mesh: SceneMesh) error{ OutOfMemory, InvalidMesh }!SceneGeometryData {
        try mesh.validate();
        const vertices = try allocator.alloc(SceneVertex, mesh.positions.len);
        errdefer allocator.free(vertices);
        for (vertices, mesh.positions, mesh.normals, 0..) |*vertex, position, normal, index| {
            vertex.* = .{ .position = position, .normal = normal, .uv = if (mesh.uvs) |uvs| uvs[index] else .{ 0, 0 } };
        }
        const indices = try allocator.dupe(u32, mesh.indices);
        return .{ .vertices = vertices, .indices = indices };
    }

    /// Two counter-clockwise triangles of a quad whose corners go round it
    /// counter-clockwise seen from its front.
    ///
    /// - `indices`: the six indices to fill.
    /// - `first`: the first corner.
    /// - `second`: the next corner counter-clockwise.
    /// - `third`: the next.
    /// - `fourth`: the last.
    fn quad(indices: *[6]u32, first: u32, second: u32, third: u32, fourth: u32) void {
        indices.* = .{ first, second, third, first, third, fourth };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

/// Checks for the geometry tests.
const TestGeometry = struct {
    const Self = @This();

    /// Checks a geometry's data: unit normals, uvs in range, indices in range,
    /// and every triangle counter-clockwise seen from outside (its face normal
    /// agreeing with its vertices' normals).
    ///
    /// - `data`: the data.
    /// - Returns: nothing; fails the test on the first problem.
    fn expectWellFormed(data: SceneGeometryData) !void {
        for (data.vertices) |vertex| {
            const normal = mod.Vec3.init(vertex.normal[0], vertex.normal[1], vertex.normal[2]);
            try std.testing.expectApproxEqAbs(@as(f32, 1), normal.length(), 1e-5);
            for (vertex.uv) |coordinate| try std.testing.expect(coordinate >= 0 and coordinate <= 1);
        }
        try std.testing.expect(data.indices.len % 3 == 0);
        var triangle: usize = 0;
        while (triangle < data.indices.len) : (triangle += 3) {
            var corners: [3]mod.Vec3 = undefined;
            var normal_sum = mod.Vec3.zero;
            for (0..3) |corner| {
                const index = data.indices[triangle + corner];
                try std.testing.expect(index < data.vertices.len);
                const vertex = data.vertices[index];
                corners[corner] = mod.Vec3.init(vertex.position[0], vertex.position[1], vertex.position[2]);
                normal_sum = normal_sum.add(mod.Vec3.init(vertex.normal[0], vertex.normal[1], vertex.normal[2]));
            }
            const face = corners[1].sub(corners[0]).cross(corners[2].sub(corners[0]));
            // A sphere's pole triangles collapse to nothing; any other faces outward.
            if (face.length() > 1e-7) try std.testing.expect(face.dot(normal_sum) > 0);
        }
    }
};

test "every primitive's vertices have unit normals, uvs in range and outward triangles" {
    const allocator = std.testing.allocator;
    const shapes = [_]SceneGeometry{
        .{ .box = .{ .width = 2, .height = 1, .length = 3 } },
        .{ .sphere = .{ .radius = 1.5 } },
        .{ .plane = .{ .width = 4, .height = 2 } },
        .{ .cylinder = .{ .radius = 0.5, .height = 2 } },
    };
    const vertex_counts = [_]usize{ 24, (SceneGeometry.rings + 1) * (SceneGeometry.segments + 1), 4, (SceneGeometry.segments + 1) * 2 + (SceneGeometry.segments + 2) * 2 };
    for (shapes, vertex_counts) |shape, vertex_count| {
        var data = try shape.build(allocator);
        defer data.deinit(allocator);
        try std.testing.expectEqual(vertex_count, data.vertices.len);
        try TestGeometry.expectWellFormed(data);
        // Every vertex lies inside the geometry's bounds.
        const box = shape.bounds();
        for (data.vertices) |vertex| {
            const position = mod.Vec3.init(vertex.position[0], vertex.position[1], vertex.position[2]);
            try std.testing.expect(position.x >= box.min.x - 1e-5 and position.x <= box.max.x + 1e-5);
            try std.testing.expect(position.y >= box.min.y - 1e-5 and position.y <= box.max.y + 1e-5);
            try std.testing.expect(position.z >= box.min.z - 1e-5 and position.z <= box.max.z + 1e-5);
        }
    }
}

test "a mesh draws only with normals for every position, whole triangles and indices in range" {
    const allocator = std.testing.allocator;
    const positions = [_][3]f32{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } };
    const normals = [_][3]f32{ .{ 0, 0, 1 }, .{ 0, 0, 1 }, .{ 0, 0, 1 } };
    const mesh = SceneMesh{ .positions = &positions, .normals = &normals, .indices = &.{ 0, 1, 2 } };
    try mesh.validate();
    var data = try (SceneGeometry{ .mesh = mesh }).build(allocator);
    defer data.deinit(allocator);
    try TestGeometry.expectWellFormed(data);

    try std.testing.expectError(error.InvalidMesh, (SceneMesh{ .positions = &positions, .normals = normals[0..2], .indices = &.{ 0, 1, 2 } }).validate());
    try std.testing.expectError(error.InvalidMesh, (SceneMesh{ .positions = &positions, .normals = &normals, .indices = &.{ 0, 1 } }).validate());
    try std.testing.expectError(error.InvalidMesh, (SceneMesh{ .positions = &positions, .normals = &normals, .indices = &.{ 0, 1, 3 } }).validate());
    try std.testing.expectError(error.InvalidMesh, (SceneGeometry{ .mesh = .{ .positions = &positions, .normals = &normals, .indices = &.{ 0, 1, 3 } } }).build(allocator));
}

test "a geometry's key follows its sizes, and a mesh's its generation" {
    const first = SceneGeometry{ .box = .{ .width = 1 } };
    try std.testing.expectEqual(first.key(), (SceneGeometry{ .box = .{ .width = 1 } }).key());
    try std.testing.expect(first.key() != (SceneGeometry{ .box = .{ .width = 2 } }).key());
    try std.testing.expect(first.key() != (SceneGeometry{ .sphere = .{} }).key());
    const positions = [_][3]f32{.{ 0, 0, 0 }};
    const mesh = SceneMesh{ .positions = &positions, .normals = &positions, .indices = &.{ 0, 0, 0 } };
    var changed = mesh;
    changed.generation = 1;
    try std.testing.expect((SceneGeometry{ .mesh = mesh }).key() != (SceneGeometry{ .mesh = changed }).key());
}
