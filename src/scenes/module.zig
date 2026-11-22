//! Scenes: an app-owned 3D scene graph (SceneKit's model) and the math under
//! it, pure Zig, drawn by a `SceneView` through the GPU backend. Imports only
//! the renderer (colors, images); the views and the SDL runtime import it.

const std = @import("std");
const log = std.log.scoped(.ziggui_scenes_module);

// -----------------------------------------------------------------------------
// Math

/// A point or a direction in a scene.
pub const Vec3 = @import("math/module.zig").Vec3;
/// A point in homogeneous coordinates, or a matrix column.
pub const Vec4 = @import("math/module.zig").Vec4;
/// A 4×4 column-major matrix.
pub const Mat4 = @import("math/module.zig").Mat4;
/// A rotation as a unit quaternion.
pub const Quaternion = @import("math/module.zig").Quaternion;

// -----------------------------------------------------------------------------
// Model

/// A 3D scene: a graph of nodes under a root.
pub const Scene = @import("model/module.zig").Scene;
/// A node reached by walking a scene's graph.
pub const SceneVisit = @import("model/module.zig").SceneVisit;
/// A node of a scene.
pub const SceneNode = @import("model/module.zig").SceneNode;
/// A stable handle to a scene's node.
pub const SceneNodeId = @import("model/module.zig").SceneNodeId;
/// A node's place in its parent's space.
pub const SceneTransform = @import("model/module.zig").SceneTransform;
/// A node's shape.
pub const SceneGeometry = @import("model/module.zig").SceneGeometry;
/// A box primitive.
pub const SceneBox = @import("model/module.zig").SceneBox;
/// A sphere primitive.
pub const SceneSphere = @import("model/module.zig").SceneSphere;
/// A rectangle primitive facing +Z.
pub const ScenePlane = @import("model/module.zig").ScenePlane;
/// A capped cylinder primitive.
pub const SceneCylinder = @import("model/module.zig").SceneCylinder;
/// Triangles the app supplies.
pub const SceneMesh = @import("model/module.zig").SceneMesh;
/// One vertex as the scene shaders read it.
pub const SceneVertex = @import("model/module.zig").SceneVertex;
/// The vertices and triangles a geometry is drawn with.
pub const SceneGeometryData = @import("model/module.zig").SceneGeometryData;
/// An axis-aligned box holding geometry.
pub const SceneBounds = @import("model/module.zig").SceneBounds;
/// How a node's surface looks.
pub const SceneMaterial = @import("model/module.zig").SceneMaterial;
/// A material's base-color texture.
pub const SceneTexture = @import("model/module.zig").SceneTexture;
/// A light a node carries.
pub const SceneLight = @import("model/module.zig").SceneLight;
/// What kind of light it is.
pub const SceneLightKind = @import("model/module.zig").SceneLightKind;
/// A directional light's settings.
pub const SceneDirectionalLight = @import("model/module.zig").SceneDirectionalLight;
/// A point light's settings.
pub const ScenePointLight = @import("model/module.zig").ScenePointLight;
/// A camera a node carries.
pub const SceneCamera = @import("model/module.zig").SceneCamera;
/// Where a view last drew a scene.
pub const SceneViewport = @import("model/module.zig").SceneViewport;
/// One frame of a scene as the GPU draws it.
pub const SceneFrame = @import("model/module.zig").SceneFrame;
/// A shape a frame draws.
pub const SceneDraw = @import("model/module.zig").SceneDraw;
/// A directional light as the shaders read it.
pub const SceneFrameDirectionalLight = @import("model/module.zig").SceneFrameDirectionalLight;
/// A point light as the shaders read it.
pub const SceneFramePointLight = @import("model/module.zig").SceneFramePointLight;

// -----------------------------------------------------------------------------
// Camera

/// Orbits and zooms a scene's point of view about its camera target.
pub const SceneCameraControl = @import("camera/module.zig").SceneCameraControl;

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
    _ = @import("math/module.zig");
    _ = @import("model/module.zig");
    _ = @import("camera/module.zig");
}
