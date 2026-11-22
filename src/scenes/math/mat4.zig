//! A 4×4 matrix: a scene's transforms, views and projections.

const std = @import("std");
const log = std.log.scoped(.ziggui_mat4);
const mod = @import("module.zig");

/// A 4×4 matrix stored column-major, as the shaders read it, transforming
/// column vectors (`matrix × vector`). Projections are right-handed, the
/// camera looking down -Z, with depth from 0 at the near plane to 1 at the
/// far one, as SDL_GPU's backends all take it.
pub const Mat4 = extern struct {
    const Self = @This();

    /// The four columns.
    columns: [4]mod.Vec4,

    /// The matrix that changes nothing.
    pub const identity = Self{ .columns = .{
        .{ .x = 1 },
        .{ .y = 1 },
        .{ .z = 1 },
        .{ .w = 1 },
    } };

    /// A move by an offset.
    ///
    /// - `offset`: the offset.
    /// - Returns: the matrix.
    pub fn translation(offset: mod.Vec3) Self {
        var self = identity;
        self.columns[3] = mod.Vec4.fromVec3(offset, 1);
        return self;
    }

    /// A scale along each axis.
    ///
    /// - `factors`: the scale along X, Y and Z.
    /// - Returns: the matrix.
    pub fn scaling(factors: mod.Vec3) Self {
        const self = Self{ .columns = .{
            .{ .x = factors.x },
            .{ .y = factors.y },
            .{ .z = factors.z },
            .{ .w = 1 },
        } };
        return self;
    }

    /// A rotation.
    ///
    /// - `rotation`: the rotation, a unit quaternion.
    /// - Returns: the matrix.
    pub fn fromQuaternion(rotation: mod.Quaternion) Self {
        const right = rotation.rotate(mod.Vec3.init(1, 0, 0));
        const up = rotation.rotate(mod.Vec3.init(0, 1, 0));
        const back = rotation.rotate(mod.Vec3.init(0, 0, 1));
        const self = Self{ .columns = .{
            mod.Vec4.fromVec3(right, 0),
            mod.Vec4.fromVec3(up, 0),
            mod.Vec4.fromVec3(back, 0),
            .{ .w = 1 },
        } };
        return self;
    }

    /// A transform: a scale, then a rotation, then a move.
    ///
    /// - `position`: the move.
    /// - `rotation`: the rotation.
    /// - `factors`: the scale.
    /// - Returns: the matrix.
    pub fn compose(position: mod.Vec3, rotation: mod.Quaternion, factors: mod.Vec3) Self {
        var self = Self.fromQuaternion(rotation);
        self.columns[0] = Self.scaled(self.columns[0], factors.x);
        self.columns[1] = Self.scaled(self.columns[1], factors.y);
        self.columns[2] = Self.scaled(self.columns[2], factors.z);
        self.columns[3] = mod.Vec4.fromVec3(position, 1);
        return self;
    }

    /// A perspective projection.
    ///
    /// - `field_of_view`: the vertical field of view, in radians.
    /// - `aspect`: width over height.
    /// - `near`: the near plane's distance (above 0).
    /// - `far`: the far plane's distance (beyond `near`).
    /// - Returns: the matrix.
    pub fn perspective(field_of_view: f32, aspect: f32, near: f32, far: f32) Self {
        const focal = 1 / @tan(field_of_view / 2);
        const self = Self{ .columns = .{
            .{ .x = focal / aspect },
            .{ .y = focal },
            .{ .z = far / (near - far), .w = -1 },
            .{ .z = near * far / (near - far) },
        } };
        return self;
    }

    /// An orthographic projection of a box.
    ///
    /// - `left`: the box's left edge.
    /// - `right`: its right edge.
    /// - `bottom`: its bottom edge.
    /// - `top`: its top edge.
    /// - `near`: the near plane's distance.
    /// - `far`: the far plane's distance.
    /// - Returns: the matrix.
    pub fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Self {
        const self = Self{ .columns = .{
            .{ .x = 2 / (right - left) },
            .{ .y = 2 / (top - bottom) },
            .{ .z = 1 / (near - far) },
            .{ .x = -(right + left) / (right - left), .y = -(top + bottom) / (top - bottom), .z = near / (near - far), .w = 1 },
        } };
        return self;
    }

    /// The view from an eye looking at a target: what moves the scene so the
    /// eye is at the origin looking down -Z.
    ///
    /// - `eye`: where the eye is.
    /// - `target`: what it looks at.
    /// - `up`: the direction up should lean toward.
    /// - Returns: the matrix.
    pub fn lookAt(eye: mod.Vec3, target: mod.Vec3, up: mod.Vec3) Self {
        const rotation = mod.Quaternion.lookRotation(target.sub(eye), up);
        return Self.compose(eye, rotation, mod.Vec3.one).inverse();
    }

    /// The product `self × other`: `other` applied first.
    ///
    /// - `self`: the matrix applied second.
    /// - `other`: the matrix applied first.
    /// - Returns: the product.
    pub fn multiply(self: *const Self, other: Self) Self {
        var product: Self = undefined;
        for (other.columns, 0..) |column, index| product.columns[index] = self.transform(column);
        return product;
    }

    /// A vector transformed.
    ///
    /// - `self`: the matrix.
    /// - `vector`: the vector.
    /// - Returns: the transformed vector.
    pub fn transform(self: *const Self, vector: mod.Vec4) mod.Vec4 {
        const columns = self.columns;
        return .{
            .x = columns[0].x * vector.x + columns[1].x * vector.y + columns[2].x * vector.z + columns[3].x * vector.w,
            .y = columns[0].y * vector.x + columns[1].y * vector.y + columns[2].y * vector.z + columns[3].y * vector.w,
            .z = columns[0].z * vector.x + columns[1].z * vector.y + columns[2].z * vector.z + columns[3].z * vector.w,
            .w = columns[0].w * vector.x + columns[1].w * vector.y + columns[2].w * vector.z + columns[3].w * vector.w,
        };
    }

    /// A point transformed (projected, when the matrix is a projection).
    ///
    /// - `self`: the matrix.
    /// - `point`: the point.
    /// - Returns: the transformed point.
    pub fn transformPoint(self: *const Self, point: mod.Vec3) mod.Vec3 {
        return self.transform(mod.Vec4.fromVec3(point, 1)).toVec3();
    }

    /// A direction transformed (moves ignored).
    ///
    /// - `self`: the matrix.
    /// - `direction`: the direction.
    /// - Returns: the transformed direction.
    pub fn transformDirection(self: *const Self, direction: mod.Vec3) mod.Vec3 {
        const transformed = self.transform(mod.Vec4.fromVec3(direction, 0));
        return .{ .x = transformed.x, .y = transformed.y, .z = transformed.z };
    }

    /// The matrix's rows as columns.
    ///
    /// - `self`: the matrix.
    /// - Returns: the transpose.
    pub fn transpose(self: *const Self) Self {
        const columns = self.columns;
        const transposed = Self{ .columns = .{
            .{ .x = columns[0].x, .y = columns[1].x, .z = columns[2].x, .w = columns[3].x },
            .{ .x = columns[0].y, .y = columns[1].y, .z = columns[2].y, .w = columns[3].y },
            .{ .x = columns[0].z, .y = columns[1].z, .z = columns[2].z, .w = columns[3].z },
            .{ .x = columns[0].w, .y = columns[1].w, .z = columns[2].w, .w = columns[3].w },
        } };
        return transposed;
    }

    /// The matrix that undoes this one, or the identity for one that cannot
    /// be undone (a zero scale).
    ///
    /// - `self`: the matrix.
    /// - Returns: the inverse.
    pub fn inverse(self: *const Self) Self {
        const entries = self.toArray();
        var cofactors: [16]f32 = undefined;
        cofactors[0] = entries[5] * entries[10] * entries[15] - entries[5] * entries[11] * entries[14] - entries[9] * entries[6] * entries[15] + entries[9] * entries[7] * entries[14] + entries[13] * entries[6] * entries[11] - entries[13] * entries[7] * entries[10];
        cofactors[4] = -entries[4] * entries[10] * entries[15] + entries[4] * entries[11] * entries[14] + entries[8] * entries[6] * entries[15] - entries[8] * entries[7] * entries[14] - entries[12] * entries[6] * entries[11] + entries[12] * entries[7] * entries[10];
        cofactors[8] = entries[4] * entries[9] * entries[15] - entries[4] * entries[11] * entries[13] - entries[8] * entries[5] * entries[15] + entries[8] * entries[7] * entries[13] + entries[12] * entries[5] * entries[11] - entries[12] * entries[7] * entries[9];
        cofactors[12] = -entries[4] * entries[9] * entries[14] + entries[4] * entries[10] * entries[13] + entries[8] * entries[5] * entries[14] - entries[8] * entries[6] * entries[13] - entries[12] * entries[5] * entries[10] + entries[12] * entries[6] * entries[9];
        cofactors[1] = -entries[1] * entries[10] * entries[15] + entries[1] * entries[11] * entries[14] + entries[9] * entries[2] * entries[15] - entries[9] * entries[3] * entries[14] - entries[13] * entries[2] * entries[11] + entries[13] * entries[3] * entries[10];
        cofactors[5] = entries[0] * entries[10] * entries[15] - entries[0] * entries[11] * entries[14] - entries[8] * entries[2] * entries[15] + entries[8] * entries[3] * entries[14] + entries[12] * entries[2] * entries[11] - entries[12] * entries[3] * entries[10];
        cofactors[9] = -entries[0] * entries[9] * entries[15] + entries[0] * entries[11] * entries[13] + entries[8] * entries[1] * entries[15] - entries[8] * entries[3] * entries[13] - entries[12] * entries[1] * entries[11] + entries[12] * entries[3] * entries[9];
        cofactors[13] = entries[0] * entries[9] * entries[14] - entries[0] * entries[10] * entries[13] - entries[8] * entries[1] * entries[14] + entries[8] * entries[2] * entries[13] + entries[12] * entries[1] * entries[10] - entries[12] * entries[2] * entries[9];
        cofactors[2] = entries[1] * entries[6] * entries[15] - entries[1] * entries[7] * entries[14] - entries[5] * entries[2] * entries[15] + entries[5] * entries[3] * entries[14] + entries[13] * entries[2] * entries[7] - entries[13] * entries[3] * entries[6];
        cofactors[6] = -entries[0] * entries[6] * entries[15] + entries[0] * entries[7] * entries[14] + entries[4] * entries[2] * entries[15] - entries[4] * entries[3] * entries[14] - entries[12] * entries[2] * entries[7] + entries[12] * entries[3] * entries[6];
        cofactors[10] = entries[0] * entries[5] * entries[15] - entries[0] * entries[7] * entries[13] - entries[4] * entries[1] * entries[15] + entries[4] * entries[3] * entries[13] + entries[12] * entries[1] * entries[7] - entries[12] * entries[3] * entries[5];
        cofactors[14] = -entries[0] * entries[5] * entries[14] + entries[0] * entries[6] * entries[13] + entries[4] * entries[1] * entries[14] - entries[4] * entries[2] * entries[13] - entries[12] * entries[1] * entries[6] + entries[12] * entries[2] * entries[5];
        cofactors[3] = -entries[1] * entries[6] * entries[11] + entries[1] * entries[7] * entries[10] + entries[5] * entries[2] * entries[11] - entries[5] * entries[3] * entries[10] - entries[9] * entries[2] * entries[7] + entries[9] * entries[3] * entries[6];
        cofactors[7] = entries[0] * entries[6] * entries[11] - entries[0] * entries[7] * entries[10] - entries[4] * entries[2] * entries[11] + entries[4] * entries[3] * entries[10] + entries[8] * entries[2] * entries[7] - entries[8] * entries[3] * entries[6];
        cofactors[11] = -entries[0] * entries[5] * entries[11] + entries[0] * entries[7] * entries[9] + entries[4] * entries[1] * entries[11] - entries[4] * entries[3] * entries[9] - entries[8] * entries[1] * entries[7] + entries[8] * entries[3] * entries[5];
        cofactors[15] = entries[0] * entries[5] * entries[10] - entries[0] * entries[6] * entries[9] - entries[4] * entries[1] * entries[10] + entries[4] * entries[2] * entries[9] + entries[8] * entries[1] * entries[6] - entries[8] * entries[2] * entries[5];
        const determinant = entries[0] * cofactors[0] + entries[1] * cofactors[4] + entries[2] * cofactors[8] + entries[3] * cofactors[12];
        if (determinant == 0 or !std.math.isFinite(determinant)) return identity;
        for (&cofactors) |*cofactor| cofactor.* /= determinant;
        return Self.fromArray(cofactors);
    }

    /// The matrix that turns a transform's normals: the inverse transpose of
    /// its rotation and scale, the move dropped.
    ///
    /// - `self`: the transform.
    /// - Returns: the normal matrix.
    pub fn normalMatrix(self: *const Self) Self {
        var rotation_and_scale = self.*;
        rotation_and_scale.columns[3] = .{ .w = 1 };
        return rotation_and_scale.inverse().transpose();
    }

    /// The matrix's sixteen floats, column after column.
    ///
    /// - `self`: the matrix.
    /// - Returns: the floats.
    pub fn toArray(self: *const Self) [16]f32 {
        return @as(*const [16]f32, @ptrCast(self)).*;
    }

    /// The matrix from sixteen floats, column after column.
    ///
    /// - `floats`: the floats.
    /// - Returns: the matrix.
    pub fn fromArray(floats: [16]f32) Self {
        return @as(*const Self, @ptrCast(&floats)).*;
    }

    /// Whether two matrices agree to within a tolerance in every element.
    ///
    /// - `self`: the first.
    /// - `other`: the second.
    /// - `tolerance`: the largest difference allowed.
    /// - Returns: true when they agree.
    pub fn approxEql(self: *const Self, other: Self, tolerance: f32) bool {
        for (self.toArray(), other.toArray()) |first, second| {
            if (@abs(first - second) > tolerance) return false;
        }
        return true;
    }

    /// A column scaled, its `w` kept.
    ///
    /// - `column`: the column.
    /// - `factor`: the factor.
    /// - Returns: the scaled column.
    fn scaled(column: mod.Vec4, factor: f32) mod.Vec4 {
        return .{ .x = column.x * factor, .y = column.y * factor, .z = column.z * factor, .w = column.w };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a perspective projection takes the near plane to depth 0 and the far one to 1" {
    const projection = Mat4.perspective(std.math.pi / 2.0, 2, 1, 10);
    try std.testing.expectApproxEqAbs(@as(f32, 0), projection.transformPoint(mod.Vec3.init(0, 0, -1)).z, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), projection.transformPoint(mod.Vec3.init(0, 0, -10)).z, 1e-5);
    // At 90°, a point as far up as it is away lies on the top edge; aspect 2 halves x.
    const corner = projection.transformPoint(mod.Vec3.init(2, 2, -2));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), corner.x, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), corner.y, 1e-6);
}

test "an orthographic projection maps its box onto x and y in -1 to 1 and depth in 0 to 1" {
    const projection = Mat4.orthographic(-2, 2, -1, 1, 0, 10);
    try std.testing.expect(projection.transformPoint(mod.Vec3.init(2, 1, 0)).approxEql(mod.Vec3.init(1, 1, 0), 1e-6));
    try std.testing.expect(projection.transformPoint(mod.Vec3.init(-2, -1, -10)).approxEql(mod.Vec3.init(-1, -1, 1), 1e-6));
}

test "look-at puts the eye at the origin with the target down -Z" {
    const view = Mat4.lookAt(mod.Vec3.init(0, 0, 5), mod.Vec3.zero, mod.Vec3.up);
    try std.testing.expect(view.transformPoint(mod.Vec3.init(0, 0, 5)).approxEql(mod.Vec3.zero, 1e-5));
    try std.testing.expect(view.transformPoint(mod.Vec3.zero).approxEql(mod.Vec3.init(0, 0, -5), 1e-5));
    try std.testing.expect(view.transformPoint(mod.Vec3.init(1, 0, 0)).approxEql(mod.Vec3.init(1, 0, -5), 1e-5));
}

test "a transform times its inverse is the identity; a zero scale inverts to the identity" {
    const transform = Mat4.compose(mod.Vec3.init(1, 2, 3), mod.Quaternion.fromAxisAngle(mod.Vec3.init(1, 1, 0), 0.7), mod.Vec3.init(2, 3, 0.5));
    try std.testing.expect(transform.multiply(transform.inverse()).approxEql(Mat4.identity, 1e-5));
    try std.testing.expect(Mat4.scaling(mod.Vec3.zero).inverse().approxEql(Mat4.identity, 0));
}

test "a normal matrix keeps a stretched surface's normal perpendicular to it" {
    // A 45° slope stretched 2× along X: its normal must turn the other way.
    const stretch = Mat4.scaling(mod.Vec3.init(2, 1, 1));
    const tangent = stretch.transformDirection(mod.Vec3.init(1, 1, 0));
    const normal = stretch.normalMatrix().transformDirection(mod.Vec3.init(-1, 1, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 0), tangent.dot(normal), 1e-6);
}
