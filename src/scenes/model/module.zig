//! A scene's model: the graph of nodes, what they carry, and one frame of
//! it gathered for drawing.

const std = @import("std");
const log = std.log.scoped(.ziggui_model_module);

/// A point or a direction in a scene.
pub const Vec3 = @import("../math/module.zig").Vec3;
/// A point in homogeneous coordinates, or a matrix column.
pub const Vec4 = @import("../math/module.zig").Vec4;
/// A 4×4 column-major matrix.
pub const Mat4 = @import("../math/module.zig").Mat4;
/// A rotation as a unit quaternion.
pub const Quaternion = @import("../math/module.zig").Quaternion;

/// A 3D scene: a graph of nodes under a root.
pub const Scene = @import("scene.zig").Scene;
/// A node reached by walking a scene's graph.
pub const SceneVisit = @import("scene.zig").SceneVisit;
/// A node of a scene.
pub const SceneNode = @import("scene_node.zig").SceneNode;
/// A stable handle to a scene's node.
pub const SceneNodeId = @import("scene_node_id.zig").SceneNodeId;
/// A node's place in its parent's space.
pub const SceneTransform = @import("scene_transform.zig").SceneTransform;
/// A node's shape.
pub const SceneGeometry = @import("scene_geometry.zig").SceneGeometry;
/// A box primitive.
pub const SceneBox = @import("scene_geometry.zig").SceneBox;
/// A sphere primitive.
pub const SceneSphere = @import("scene_geometry.zig").SceneSphere;
/// A rectangle primitive facing +Z.
pub const ScenePlane = @import("scene_geometry.zig").ScenePlane;
/// A capped cylinder primitive.
pub const SceneCylinder = @import("scene_geometry.zig").SceneCylinder;
/// Triangles the app supplies.
pub const SceneMesh = @import("scene_geometry.zig").SceneMesh;
/// One vertex as the scene shaders read it.
pub const SceneVertex = @import("scene_geometry.zig").SceneVertex;
/// The vertices and triangles a geometry is drawn with.
pub const SceneGeometryData = @import("scene_geometry.zig").SceneGeometryData;
/// An axis-aligned box holding geometry.
pub const SceneBounds = @import("scene_bounds.zig").SceneBounds;
/// How a node's surface looks.
pub const SceneMaterial = @import("scene_material.zig").SceneMaterial;
/// A material's base-color texture.
pub const SceneTexture = @import("scene_material.zig").SceneTexture;
/// A light a node carries.
pub const SceneLight = @import("scene_light.zig").SceneLight;
/// What kind of light it is.
pub const SceneLightKind = @import("scene_light.zig").SceneLightKind;
/// A directional light's settings.
pub const SceneDirectionalLight = @import("scene_light.zig").SceneDirectionalLight;
/// A point light's settings.
pub const ScenePointLight = @import("scene_light.zig").ScenePointLight;
/// A camera a node carries.
pub const SceneCamera = @import("scene_camera.zig").SceneCamera;
/// Where a view last drew a scene.
pub const SceneViewport = @import("scene_viewport.zig").SceneViewport;
/// One frame of a scene as the GPU draws it.
pub const SceneFrame = @import("scene_frame.zig").SceneFrame;
/// A shape a frame draws.
pub const SceneDraw = @import("scene_frame.zig").SceneDraw;
/// A directional light as the shaders read it.
pub const SceneFrameDirectionalLight = @import("scene_frame.zig").SceneFrameDirectionalLight;
/// A point light as the shaders read it.
pub const SceneFramePointLight = @import("scene_frame.zig").SceneFramePointLight;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("scene.zig");
    _ = @import("scene_node.zig");
    _ = @import("scene_node_id.zig");
    _ = @import("scene_transform.zig");
    _ = @import("scene_geometry.zig");
    _ = @import("scene_bounds.zig");
    _ = @import("scene_material.zig");
    _ = @import("scene_light.zig");
    _ = @import("scene_camera.zig");
    _ = @import("scene_viewport.zig");
    _ = @import("scene_frame.zig");
}
