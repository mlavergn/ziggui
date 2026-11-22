// 3D scene fragment shader: Blinn-Phong in linear light, the base color times
// its texture, ambient, up to 4 directional lights (each with a shadow map,
// softened 3×3) and 8 point lights; the result encoded to sRGB when the
// target holds sRGB bytes in a UNORM format.
//
// Compiled to SPIR-V by compile.sh; keep in sync with scene.metal and scene.hlsl.
#version 450

layout(set = 2, binding = 0) uniform sampler2D base_texture;
layout(set = 2, binding = 1) uniform sampler2D shadow_map0;
layout(set = 2, binding = 2) uniform sampler2D shadow_map1;
layout(set = 2, binding = 3) uniform sampler2D shadow_map2;
layout(set = 2, binding = 4) uniform sampler2D shadow_map3;

layout(set = 3, binding = 0) uniform SceneLights {
    vec4 eye;                      // xyz the camera; w how many directional lights
    vec4 ambient;                  // rgb the ambient light; w how many point lights
    vec4 directional_direction[4]; // xyz the way the light travels; w its shadow map, -1 for none
    vec4 directional_color[4];     // rgb
    vec4 point_position[8];        // xyz; w its range
    vec4 point_color[8];           // rgb
    mat4 shadow[4];                // the scene's space into each shadow map
    vec4 shadow_parameters;        // x a shadow texel; y the depth bias; z 1 to encode sRGB
} lights;

layout(set = 3, binding = 1) uniform SceneSurface {
    vec4 base_color; // linear rgb; a the alpha
    vec4 surface;    // x the specular; y the shininess; z 1 when it receives shadows
} surface;

layout(location = 0) in vec3 v_world;
layout(location = 1) in vec3 v_normal;
layout(location = 2) in vec2 v_uv;

layout(location = 0) out vec4 out_color;

// How lit a point is by a shadow map: the share of a 3×3 patch of its
// texels the point is not behind.
float softShadow(sampler2D map, mat4 projection, vec3 world) {
    vec4 clip = projection * vec4(world, 1.0);
    vec3 ndc = clip.xyz / clip.w;
    vec2 uv = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || ndc.z > 1.0) return 1.0;
    float depth = ndc.z - lights.shadow_parameters.y;
    float lit = 0.0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float nearest = texture(map, uv + vec2(float(dx), float(dy)) * lights.shadow_parameters.x).r;
            lit += depth <= nearest ? 1.0 : 0.0;
        }
    }
    return lit / 9.0;
}

float shadowOf(int map, vec3 world) {
    if (map == 0) return softShadow(shadow_map0, lights.shadow[0], world);
    if (map == 1) return softShadow(shadow_map1, lights.shadow[1], world);
    if (map == 2) return softShadow(shadow_map2, lights.shadow[2], world);
    if (map == 3) return softShadow(shadow_map3, lights.shadow[3], world);
    return 1.0;
}

vec3 encodeSrgb(vec3 linear) {
    vec3 low = linear * 12.92;
    vec3 high = 1.055 * pow(linear, vec3(1.0 / 2.4)) - 0.055;
    return mix(high, low, vec3(lessThanEqual(linear, vec3(0.0031308))));
}

void main() {
    vec3 normal = normalize(v_normal);
    vec3 to_eye = normalize(lights.eye.xyz - v_world);
    // Lit from the side the camera sees, so a plane seen from behind is lit too.
    if (dot(normal, to_eye) < 0.0) normal = -normal;
    vec4 texel = texture(base_texture, v_uv);
    vec3 albedo = surface.base_color.rgb * texel.rgb;
    float alpha = surface.base_color.a * texel.a;
    float specular = surface.surface.x;
    float shininess = max(surface.surface.y, 1.0);
    bool receives = surface.surface.z > 0.5;

    vec3 color = lights.ambient.rgb * albedo;
    int directional_count = int(lights.eye.w);
    for (int index = 0; index < 4; index++) {
        if (index >= directional_count) break;
        vec3 to_light = -normalize(lights.directional_direction[index].xyz);
        float diffuse = max(dot(normal, to_light), 0.0);
        if (diffuse <= 0.0) continue;
        float highlight = pow(max(dot(normal, normalize(to_light + to_eye)), 0.0), shininess) * specular;
        int map = int(lights.directional_direction[index].w);
        float lit = (receives && map >= 0) ? shadowOf(map, v_world) : 1.0;
        color += (albedo * diffuse + highlight) * lights.directional_color[index].rgb * lit;
    }
    int point_count = int(lights.ambient.w);
    for (int index = 0; index < 8; index++) {
        if (index >= point_count) break;
        vec3 offset = lights.point_position[index].xyz - v_world;
        float separation = length(offset);
        float range = lights.point_position[index].w;
        if (separation >= range || separation <= 0.0) continue;
        vec3 to_light = offset / separation;
        float diffuse = max(dot(normal, to_light), 0.0);
        if (diffuse <= 0.0) continue;
        float fade = 1.0 - separation / range;
        float highlight = pow(max(dot(normal, normalize(to_light + to_eye)), 0.0), shininess) * specular;
        color += (albedo * diffuse + highlight) * lights.point_color[index].rgb * fade * fade;
    }

    color = clamp(color, 0.0, 1.0);
    if (lights.shadow_parameters.z > 0.5) color = encodeSrgb(color);
    out_color = vec4(color, alpha);
}
