// 3D scene shaders for Direct3D 12 (compiled at runtime to DXBC by
// d3dcompiler_47): the lit vertex and fragment entry points (the shadow
// map's pair is scene_shadow.hlsl, its uniforms on the same register). Keep
// in sync with scene.vert, scene.frag and scene.metal. SDL_GPU binding
// model: vertex uniforms at b0+ in space1, fragment samplers at t0+/s0+ in
// space2, fragment uniforms at b0+ in space3.

struct SceneVertexUniforms {
    float4x4 model;
    float4x4 normal_matrix;
    float4x4 view_projection;
};


struct SceneLights {
    float4 eye;
    float4 ambient;
    float4 directional_direction[4];
    float4 directional_color[4];
    float4 point_position[8];
    float4 point_color[8];
    float4x4 shadow[4];
    float4 shadow_parameters;
};

struct SceneSurface {
    float4 base_color;
    float4 surface;
};

ConstantBuffer<SceneVertexUniforms> vertex_uniforms : register(b0, space1);
ConstantBuffer<SceneLights> lights : register(b0, space3);
ConstantBuffer<SceneSurface> surface : register(b1, space3);

Texture2D<float4> base_texture : register(t0, space2);
SamplerState base_sampler : register(s0, space2);
Texture2D<float> shadow_map0 : register(t1, space2);
SamplerState shadow_sampler0 : register(s1, space2);
Texture2D<float> shadow_map1 : register(t2, space2);
SamplerState shadow_sampler1 : register(s2, space2);
Texture2D<float> shadow_map2 : register(t3, space2);
SamplerState shadow_sampler2 : register(s3, space2);
Texture2D<float> shadow_map3 : register(t4, space2);
SamplerState shadow_sampler3 : register(s4, space2);

struct SceneVertexIn {
    float3 position : TEXCOORD0;
    float3 normal   : TEXCOORD1;
    float2 uv       : TEXCOORD2;
};

struct SceneVaryings {
    float4 position : SV_Position;
    float3 world    : TEXCOORD0;
    float3 normal   : TEXCOORD1;
    float2 uv       : TEXCOORD2;
};

SceneVaryings scene_vertex(SceneVertexIn input) {
    SceneVaryings output;
    float4 world = mul(vertex_uniforms.model, float4(input.position, 1.0));
    output.world = world.xyz;
    output.normal = mul((float3x3)vertex_uniforms.normal_matrix, input.normal);
    output.uv = input.uv;
    output.position = mul(vertex_uniforms.view_projection, world);
    return output;
}

// How lit a point is by a shadow map: the share of a 3×3 patch of its
// texels the point is not behind.
float soft_shadow(Texture2D<float> map, SamplerState smp, float4x4 projection, float3 world) {
    float4 clip = mul(projection, float4(world, 1.0));
    float3 ndc = clip.xyz / clip.w;
    float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || ndc.z > 1.0) return 1.0;
    float depth = ndc.z - lights.shadow_parameters.y;
    float lit = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float nearest = map.SampleLevel(smp, uv + float2(float(dx), float(dy)) * lights.shadow_parameters.x, 0);
            lit += depth <= nearest ? 1.0 : 0.0;
        }
    }
    return lit / 9.0;
}

float3 encode_srgb(float3 linear_color) {
    float3 low = linear_color * 12.92;
    float3 high = 1.055 * pow(linear_color, 1.0 / 2.4) - 0.055;
    return float3(linear_color.x <= 0.0031308 ? low.x : high.x,
                  linear_color.y <= 0.0031308 ? low.y : high.y,
                  linear_color.z <= 0.0031308 ? low.z : high.z);
}

float4 scene_fragment(SceneVaryings input) : SV_Target0 {
    float3 normal = normalize(input.normal);
    float3 to_eye = normalize(lights.eye.xyz - input.world);
    // Lit from the side the camera sees, so a plane seen from behind is lit too.
    if (dot(normal, to_eye) < 0.0) normal = -normal;
    float4 texel = base_texture.Sample(base_sampler, input.uv);
    float3 albedo = surface.base_color.rgb * texel.rgb;
    float alpha = surface.base_color.a * texel.a;
    float specular = surface.surface.x;
    float shininess = max(surface.surface.y, 1.0);
    bool receives = surface.surface.z > 0.5;

    float3 color = lights.ambient.rgb * albedo;
    int directional_count = int(lights.eye.w);
    [unroll] for (int index = 0; index < 4; index++) {
        if (index >= directional_count) break;
        float3 to_light = -normalize(lights.directional_direction[index].xyz);
        float diffuse = max(dot(normal, to_light), 0.0);
        if (diffuse <= 0.0) continue;
        float highlight = pow(max(dot(normal, normalize(to_light + to_eye)), 0.0), shininess) * specular;
        int map = int(lights.directional_direction[index].w);
        float lit = 1.0;
        if (receives && map == 0) lit = soft_shadow(shadow_map0, shadow_sampler0, lights.shadow[0], input.world);
        if (receives && map == 1) lit = soft_shadow(shadow_map1, shadow_sampler1, lights.shadow[1], input.world);
        if (receives && map == 2) lit = soft_shadow(shadow_map2, shadow_sampler2, lights.shadow[2], input.world);
        if (receives && map == 3) lit = soft_shadow(shadow_map3, shadow_sampler3, lights.shadow[3], input.world);
        color += (albedo * diffuse + highlight) * lights.directional_color[index].rgb * lit;
    }
    int point_count = int(lights.ambient.w);
    [unroll] for (int light_index = 0; light_index < 8; light_index++) {
        if (light_index >= point_count) break;
        float3 offset = lights.point_position[light_index].xyz - input.world;
        float separation = length(offset);
        float range = lights.point_position[light_index].w;
        if (separation >= range || separation <= 0.0) continue;
        float3 to_light = offset / separation;
        float diffuse = max(dot(normal, to_light), 0.0);
        if (diffuse <= 0.0) continue;
        float fade = 1.0 - separation / range;
        float highlight = pow(max(dot(normal, normalize(to_light + to_eye)), 0.0), shininess) * specular;
        color += (albedo * diffuse + highlight) * lights.point_color[light_index].rgb * fade * fade;
    }

    color = saturate(color);
    if (lights.shadow_parameters.z > 0.5) color = encode_srgb(color);
    return float4(color, alpha);
}
