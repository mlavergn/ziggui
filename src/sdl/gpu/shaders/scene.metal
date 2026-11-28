// 3D scene shaders for Metal (compiled at runtime by SDL_GPU): the lit
// vertex and fragment functions and the shadow map's depth-only pair. Keep
// in sync with scene.vert, scene.frag, scene_shadow.vert, scene_shadow.frag
// and scene.hlsl. scene_traced.metal, Metal's alone, is compiled appended to
// this file (it uses `shade`). SDL_GPU binding model: vertex attributes via
// [[stage_in]], uniforms at [[buffer(n)]], textures and samplers at
// [[texture(n)]] and [[sampler(n)]].

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
    // x the exposure, y the tone curve (0 clamped, 1 filmic); appended, so
    // the other backends' shaders, which don't read it, keep their layout.
    float4 tone;
    // Each point light's shadow range (x) and soft rays (y), when traced.
    float4 point_shadow[8];
};

struct SceneSurface {
    float4 base_color;
    float4 surface;
    float4 emission;
};

// `tint` multiplies the surface's color and alpha: white but where a
// geometry modifier sets it; `custom` is what a modifier's geometry body
// hands its surface body (zero otherwise).
struct SceneVaryings {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float2 uv;
    float4 tint;
    float4 custom;
};

vertex SceneVaryings scene_vertex(SceneVertexIn in [[stage_in]],
                                  constant SceneVertexUniforms &u [[buffer(0)]]) {
    SceneVaryings out;
    float4 world = u.model * float4(in.position, 1.0);
    out.world = world.xyz;
    float3x3 normal_matrix = float3x3(u.normal_matrix[0].xyz, u.normal_matrix[1].xyz, u.normal_matrix[2].xyz);
    out.normal = normal_matrix * in.normal;
    out.uv = in.uv;
    out.tint = float4(1.0);
    out.custom = float4(0.0);
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

// The light shown: exposed, then brought into the display's range (ACES,
// Narkowicz's fit, for the filmic curve), clamped.
static float3 tone_map(float3 color, float4 tone) {
    float3 exposed = max(color * tone.x, 0.0);
    if (tone.y > 0.5) exposed = (exposed * (2.51 * exposed + 0.03)) / (exposed * (2.43 * exposed + 0.59) + 0.14);
    return clamp(exposed, 0.0, 1.0);
}

static float3 encode_srgb(float3 linear) {
    float3 low = linear * 12.92;
    float3 high = 1.055 * pow(linear, float3(1.0 / 2.4)) - 0.055;
    return select(high, low, linear <= float3(0.0031308));
}

// How lit a point is by each directional light's shadow map (its
// `directional_direction.w` names its map, -1 for a light with none); point
// lights cast no shadow from a map, and nothing reflects.
struct MappedLighting {
    depth2d<float> map0;
    sampler sampler0;
    depth2d<float> map1;
    sampler sampler1;
    depth2d<float> map2;
    sampler sampler2;
    depth2d<float> map3;
    sampler sampler3;

    float directional(constant SceneLights &lights, int index, float3 to_light, float3 world, float3 normal, float2 pixel) const {
        int map = int(lights.directional_direction[index].w);
        if (map == 0) return soft_shadow(map0, sampler0, lights.shadow[0], world, lights.shadow_parameters);
        if (map == 1) return soft_shadow(map1, sampler1, lights.shadow[1], world, lights.shadow_parameters);
        if (map == 2) return soft_shadow(map2, sampler2, lights.shadow[2], world, lights.shadow_parameters);
        if (map == 3) return soft_shadow(map3, sampler3, lights.shadow[3], world, lights.shadow_parameters);
        return 1.0;
    }

    float point(constant SceneLights &lights, int index, float3 world, float3 normal, float2 pixel) const {
        return 1.0;
    }

    float3 reflected(constant SceneLights &lights, constant SceneSurface &surface, float3 color, float3 world, float3 normal, float3 to_eye, float2 pixel) const {
        return color;
    }
};

// The light a point of a surface sends toward the eye from the scene's
// lights, unclamped: ambient, then each directional and point light's
// diffuse and highlight, each dimmed by its shadow (`lighting.directional`,
// a share or a color a cookie tints, and `lighting.point`) where the
// surface `receives` shadows. `normal` faces
// the eye; `pixel` turns the samples of a soft ray-traced shadow.
template <typename Lighting>
static float3 light_point(constant SceneLights &lights, thread const Lighting &lighting, float3 albedo,
                          float3 world, float3 normal, float3 to_eye, float specular, float shininess,
                          bool receives, float2 pixel) {
    float3 color = lights.ambient.rgb * albedo;
    int directional_count = int(lights.eye.w);
    for (int index = 0; index < 4; index++) {
        if (index >= directional_count) break;
        float3 to_light = -normalize(lights.directional_direction[index].xyz);
        float diffuse = max(dot(normal, to_light), 0.0);
        if (diffuse <= 0.0) continue;
        float highlight = pow(max(dot(normal, normalize(to_light + to_eye)), 0.0), shininess) * specular;
        float3 lit = float3(1.0);
        if (receives) lit = float3(lighting.directional(lights, index, to_light, world, normal, pixel));
        color += (albedo * diffuse + highlight) * lights.directional_color[index].rgb * lit;
    }
    int point_count = int(lights.ambient.w);
    for (int index = 0; index < 8; index++) {
        if (index >= point_count) break;
        float3 offset = lights.point_position[index].xyz - world;
        float separation = length(offset);
        float range = lights.point_position[index].w;
        if (separation >= range || separation <= 0.0) continue;
        float3 to_light = offset / separation;
        float diffuse = max(dot(normal, to_light), 0.0);
        if (diffuse <= 0.0) continue;
        float fade = 1.0 - separation / range;
        float highlight = pow(max(dot(normal, normalize(to_light + to_eye)), 0.0), shininess) * specular;
        float lit = 1.0;
        if (receives) lit = lighting.point(lights, index, world, normal, pixel);
        color += (albedo * diffuse + highlight) * lights.point_color[index].rgb * fade * fade * lit;
    }
    return color;
}

// The lit color of a point: its light (`light_point`), then what the
// surface reflects. `Lighting` says how a shadow is found and what is
// reflected (`MappedLighting`; Metal's ray-traced variant,
// scene_traced.metal, traces rays).
template <typename Lighting>
static float4 shade(SceneVaryings in, constant SceneLights &lights, constant SceneSurface &surface,
                    texture2d<float> base_texture, sampler base_sampler, thread const Lighting &lighting) {
    float3 normal = normalize(in.normal);
    float3 to_eye = normalize(lights.eye.xyz - in.world);
    // Lit from the side the camera sees, so a plane seen from behind is lit too.
    if (dot(normal, to_eye) < 0.0) normal = -normal;
    float4 texel = base_texture.sample(base_sampler, in.uv);
    float3 albedo = surface.base_color.rgb * texel.rgb * in.tint.rgb;
    float alpha = surface.base_color.a * texel.a * in.tint.a;
    // Wholly emissive: its own color, without the lighting it would discard.
    if (surface.emission.x >= 1.0) {
        float3 shown = tone_map(albedo * surface.emission.y, lights.tone);
        if (lights.shadow_parameters.z > 0.5) shown = encode_srgb(shown);
        return float4(shown, alpha);
    }
    float specular = surface.surface.x;
    float shininess = max(surface.surface.y, 1.0);
    bool receives = surface.surface.z > 0.5;

    float3 color = light_point(lights, lighting, albedo, in.world, normal, to_eye, specular, shininess, receives, in.position.xy);
    color = lighting.reflected(lights, surface, color, in.world, normal, to_eye, in.position.xy);

    // An emissive surface shows its own color, unlit, by its share.
    color = mix(color, albedo * surface.emission.y, surface.emission.x);
    color = tone_map(color, lights.tone);
    if (lights.shadow_parameters.z > 0.5) color = encode_srgb(color);
    return float4(color, alpha);
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
    MappedLighting lighting = { shadow_map0, shadow_sampler0, shadow_map1, shadow_sampler1,
                                shadow_map2, shadow_sampler2, shadow_map3, shadow_sampler3 };
    return shade(in, lights, surface, base_texture, base_sampler, lighting);
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
