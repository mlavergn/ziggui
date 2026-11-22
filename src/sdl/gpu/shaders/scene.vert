// 3D scene vertex shader: places one `scenes.SceneVertex` (position, normal,
// uv) in the scene's space and projects it through the camera.
//
// Compiled to SPIR-V by compile.sh; keep in sync with scene.metal and scene.hlsl.
#version 450

layout(set = 1, binding = 0) uniform SceneVertexUniforms {
    mat4 model;           // the node's transform in the scene's space
    mat4 normal_matrix;   // its inverse transpose (rotation and scale)
    mat4 view_projection; // the camera's projection times its view
} u;

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;

layout(location = 0) out vec3 v_world;
layout(location = 1) out vec3 v_normal;
layout(location = 2) out vec2 v_uv;

void main() {
    vec4 world = u.model * vec4(a_position, 1.0);
    v_world = world.xyz;
    v_normal = mat3(u.normal_matrix) * a_normal;
    v_uv = a_uv;
    gl_Position = u.view_projection * world;
}
