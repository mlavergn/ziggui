// 3D scene shadow-map vertex shader: projects one `scenes.SceneVertex` into
// a directional light's shadow map (depth only).
//
// Compiled to SPIR-V by compile.sh; keep in sync with scene.metal and scene.hlsl.
#version 450

layout(set = 1, binding = 0) uniform SceneShadowUniforms {
    mat4 model; // the node's transform in the scene's space
    mat4 light; // the scene's space into the shadow map
} u;

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;

void main() {
    gl_Position = u.light * (u.model * vec4(a_position, 1.0));
}
