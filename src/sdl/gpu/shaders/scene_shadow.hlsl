// 3D scene shadow-map shaders for Direct3D 12 (compiled at runtime to DXBC
// by d3dcompiler_47): project a `scenes.SceneVertex` into a directional
// light's shadow map, depth only. Keep in sync with scene_shadow.vert,
// scene_shadow.frag and scene.metal. SDL_GPU binding model: vertex uniforms
// at b0+ in space1.

struct SceneShadowUniforms {
    float4x4 model;
    float4x4 light;
};

ConstantBuffer<SceneShadowUniforms> shadow_uniforms : register(b0, space1);

struct SceneVertexIn {
    float3 position : TEXCOORD0;
    float3 normal   : TEXCOORD1;
    float2 uv       : TEXCOORD2;
};

float4 scene_shadow_vertex(SceneVertexIn input) : SV_Position {
    return mul(shadow_uniforms.light, mul(shadow_uniforms.model, float4(input.position, 1.0)));
}

void scene_shadow_fragment() {
}
