// 3D scene shaders for Metal (compiled at runtime by SDL_GPU): the lit
// vertex and fragment functions and the shadow map's depth-only pair. Keep
// in sync with scene.vert, scene.frag, scene_shadow.vert, scene_shadow.frag
// and scene.hlsl. SDL_GPU binding model: vertex attributes via [[stage_in]],
// uniforms at [[buffer(n)]], textures and samplers at [[texture(n)]] and
// [[sampler(n)]].

#include <metal_stdlib>
using namespace metal;

struct SceneVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct SceneVertexUniforms {
    float4x4 model;
    float4x4 normal_matrix;
    float4x4 view_projection;
};

struct SceneShadowUniforms {
    float4x4 model;
    float4x4 light;
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

struct SceneVaryings {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float2 uv;
};

vertex SceneVaryings scene_vertex(SceneVertexIn in [[stage_in]],
                                  constant SceneVertexUniforms &u [[buffer(0)]]) {
    SceneVaryings out;
    float4 world = u.model * float4(in.position, 1.0);
    out.world = world.xyz;
    float3x3 normal_matrix = float3x3(u.normal_matrix[0].xyz, u.normal_matrix[1].xyz, u.normal_matrix[2].xyz);
    out.normal = normal_matrix * in.normal;
    out.uv = in.uv;
    out.position = u.view_projection * world;
    return out;
}

// How lit a point is by a shadow map: the share of a 3×3 patch of its
// texels the point is not behind.
static float soft_shadow(depth2d<float> map, sampler smp, float4x4 projection, float3 world, float4 parameters) {
    float4 clip = projection * float4(world, 1.0);
    float3 ndc = clip.xyz / clip.w;
    float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || ndc.z > 1.0) return 1.0;
    float depth = ndc.z - parameters.y;
    float lit = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float nearest = map.sample(smp, uv + float2(float(dx), float(dy)) * parameters.x);
            lit += depth <= nearest ? 1.0 : 0.0;
        }
    }
    return lit / 9.0;
}

static float3 encode_srgb(float3 linear) {
    float3 low = linear * 12.92;
    float3 high = 1.055 * pow(linear, float3(1.0 / 2.4)) - 0.055;
    return select(high, low, linear <= float3(0.0031308));
}

fragment float4 scene_fragment(SceneVaryings in [[stage_in]],
                               constant SceneLights &lights [[buffer(0)]],
                               constant SceneSurface &surface [[buffer(1)]],
                               texture2d<float> base_texture [[texture(0)]],
                               sampler base_sampler [[sampler(0)]],
                               depth2d<float> shadow_map0 [[texture(1)]],
                               sampler shadow_sampler0 [[sampler(1)]],
                               depth2d<float> shadow_map1 [[texture(2)]],
                               sampler shadow_sampler1 [[sampler(2)]],
                               depth2d<float> shadow_map2 [[texture(3)]],
                               sampler shadow_sampler2 [[sampler(3)]],
                               depth2d<float> shadow_map3 [[texture(4)]],
                               sampler shadow_sampler3 [[sampler(4)]]) {
    float3 normal = normalize(in.normal);
    float3 to_eye = normalize(lights.eye.xyz - in.world);
    // Lit from the side the camera sees, so a plane seen from behind is lit too.
    if (dot(normal, to_eye) < 0.0) normal = -normal;
    float4 texel = base_texture.sample(base_sampler, in.uv);
    float3 albedo = surface.base_color.rgb * texel.rgb;
    float alpha = surface.base_color.a * texel.a;
    float specular = surface.surface.x;
    float shininess = max(surface.surface.y, 1.0);
    bool receives = surface.surface.z > 0.5;

    float3 color = lights.ambient.rgb * albedo;
    int directional_count = int(lights.eye.w);
    for (int index = 0; index < 4; index++) {
        if (index >= directional_count) break;
        float3 to_light = -normalize(lights.directional_direction[index].xyz);
        float diffuse = max(dot(normal, to_light), 0.0);
        if (diffuse <= 0.0) continue;
        float highlight = pow(max(dot(normal, normalize(to_light + to_eye)), 0.0), shininess) * specular;
        int map = int(lights.directional_direction[index].w);
        float lit = 1.0;
        if (receives && map == 0) lit = soft_shadow(shadow_map0, shadow_sampler0, lights.shadow[0], in.world, lights.shadow_parameters);
        if (receives && map == 1) lit = soft_shadow(shadow_map1, shadow_sampler1, lights.shadow[1], in.world, lights.shadow_parameters);
        if (receives && map == 2) lit = soft_shadow(shadow_map2, shadow_sampler2, lights.shadow[2], in.world, lights.shadow_parameters);
        if (receives && map == 3) lit = soft_shadow(shadow_map3, shadow_sampler3, lights.shadow[3], in.world, lights.shadow_parameters);
        color += (albedo * diffuse + highlight) * lights.directional_color[index].rgb * lit;
    }
    int point_count = int(lights.ambient.w);
    for (int index = 0; index < 8; index++) {
        if (index >= point_count) break;
        float3 offset = lights.point_position[index].xyz - in.world;
        float separation = length(offset);
        float range = lights.point_position[index].w;
        if (separation >= range || separation <= 0.0) continue;
        float3 to_light = offset / separation;
        float diffuse = max(dot(normal, to_light), 0.0);
        if (diffuse <= 0.0) continue;
        float fade = 1.0 - separation / range;
        float highlight = pow(max(dot(normal, normalize(to_light + to_eye)), 0.0), shininess) * specular;
        color += (albedo * diffuse + highlight) * lights.point_color[index].rgb * fade * fade;
    }

    color = clamp(color, 0.0, 1.0);
    if (lights.shadow_parameters.z > 0.5) color = encode_srgb(color);
    return float4(color, alpha);
}

struct SceneShadowVaryings {
    float4 position [[position]];
};

vertex SceneShadowVaryings scene_shadow_vertex(SceneVertexIn in [[stage_in]],
                                               constant SceneShadowUniforms &u [[buffer(0)]]) {
    SceneShadowVaryings out;
    out.position = u.light * (u.model * float4(in.position, 1.0));
    return out;
}

fragment void scene_shadow_fragment() {
}
