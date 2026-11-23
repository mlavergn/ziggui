// 3D scene fragment shader with ray-traced shadows and reflections, for
// Vulkan devices that trace rays (ray queries): scene.frag's lighting, its
// shadows found by tracing rays toward each light and, on a reflective
// surface, what a ray along the mirror direction meets.
//
// A directional light whose `directional_direction.w` is not -1 casts a
// shadow, softened over a cone `directional_color.w` (its angular radius's
// tangent) wide; a point light whose `point_color.w` is not -1 casts one,
// softened over a sphere that radius wide. A soft shadow sends
// `soft_samples` rays spread over the light's source (a golden-angle disc,
// turned per pixel), so it is sharp where a shadow meets its caster and
// blurs away from it. A surface whose `surface.w` (its reflectivity) is above
// 0 sends a ray along its mirror direction and mixes in what it meets, lit by
// the scene's lights (unshadowed), or the sky, more at grazing angles.
//
// SDL_GPU binds no acceleration structure, so `VulkanSceneRayTracer` hands
// the shapes' instance structure, their surfaces and their triangles over by
// GPU address in a third uniform block (`SceneTracing`, set 3 binding 2), and
// the textures reflections sample in the sampler slots after the base
// texture (set 2 bindings 1 to 8; an instance whose `texture` is -1 shows its
// color alone, its texture's average in).
//
// Compiled to SPIR-V 1.5 (`--target-env=vulkan1.2`, as ray queries need) by
// compile.sh; keep in sync with scene_traced.metal and scene.frag.
#version 460
#extension GL_EXT_ray_query : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference_uvec2 : require

layout(set = 2, binding = 0) uniform sampler2D base_texture;
layout(set = 2, binding = 1) uniform sampler2D reflected0;
layout(set = 2, binding = 2) uniform sampler2D reflected1;
layout(set = 2, binding = 3) uniform sampler2D reflected2;
layout(set = 2, binding = 4) uniform sampler2D reflected3;
layout(set = 2, binding = 5) uniform sampler2D reflected4;
layout(set = 2, binding = 6) uniform sampler2D reflected5;
layout(set = 2, binding = 7) uniform sampler2D reflected6;
layout(set = 2, binding = 8) uniform sampler2D reflected7;

layout(set = 3, binding = 0) uniform SceneLights {
    vec4 eye;                      // xyz the camera; w how many directional lights
    vec4 ambient;                  // rgb the ambient light; w how many point lights
    vec4 directional_direction[4]; // xyz the way the light travels; w its index when it casts a shadow, -1 for none
    vec4 directional_color[4];     // rgb; w its source's angular radius's tangent
    vec4 point_position[8];        // xyz; w its range
    vec4 point_color[8];           // rgb; w its source's radius when it casts a shadow, -1 for none
    mat4 shadow[4];                // unused here (shadow maps)
    vec4 shadow_parameters;        // z 1 to encode sRGB
} lights;

layout(set = 3, binding = 1) uniform SceneSurface {
    vec4 base_color; // linear rgb; a the alpha
    vec4 surface;    // x the specular; y the shininess; z 1 when it receives shadows; w the reflectivity
} surface;

// One instance's surface, as a reflection ray meets it; in the instances'
// order in the shapes' structure.
struct SceneHitInstance {
    vec4 normal_matrix[3];
    vec4 color;          // linear rgb; w the highlight's brightness
    uint first_triangle; // where its mesh's triangles start
    float shininess;
    int texture;         // the reflected texture it samples, -1 for none
    float unused;
};

// A mesh triangle's three vertex normals, in the mesh's space, and their
// texture coordinates.
struct SceneHitTriangle {
    vec4 normals[3];
    vec2 uvs[3];
    vec2 unused;
};

layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer SceneHitInstances {
    SceneHitInstance items[];
};

layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer SceneHitTriangles {
    SceneHitTriangle items[];
};

layout(set = 3, binding = 2) uniform SceneTracing {
    vec4 sky;        // linear rgb: what a reflection that meets nothing shows
    uvec2 shapes;    // the instance acceleration structure's address
    uvec2 instances; // the instances' surfaces' address
    uvec2 triangles; // the meshes' triangles' address
} tracing;

layout(location = 0) in vec3 v_world;
layout(location = 1) in vec3 v_normal;
layout(location = 2) in vec2 v_uv;

layout(location = 0) out vec4 out_color;

// The instance mask bit of the shapes that cast shadows.
const uint shadow_mask = 1u;
// The instance mask bit of the shapes reflections show (every opaque one).
const uint reflection_mask = 2u;
// How many rays a soft shadow sends a light.
const int soft_samples = 16;
// No ray reaches past this.
const float far_reach = 1.0e30;

// A number in [0, 1) that changes from pixel to pixel without a pattern the
// eye picks up (interleaved gradient noise), turning each pixel's samples.
float pixelNoise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

// A point moved off its surface along the normal, by a share of its
// distance from the origin, so a ray from it does not meet that surface.
vec3 offSurface(vec3 world, vec3 normal) {
    float scale = max(1.0, max(abs(world.x), max(abs(world.y), abs(world.z))));
    return world + normal * (0.001 * scale);
}

// Sample `index` of `count` spread evenly over the unit disc (a golden-angle
// spiral), turned by `turn` of a full turn.
vec2 discSample(int index, int count, float turn) {
    float radius = sqrt((float(index) + 0.5) / float(count));
    float angle = float(index) * 2.39996323 + turn * 6.28318531;
    return radius * vec2(cos(angle), sin(angle));
}

// Two unit vectors square to `axis` and to each other.
void squareTo(vec3 axis, out vec3 across, out vec3 up) {
    vec3 helper = abs(axis.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    across = normalize(cross(helper, axis));
    up = cross(axis, across);
}

// Whether a ray meets a shadow caster before `reach`.
bool blocked(vec3 origin, vec3 direction, float reach) {
    rayQueryEXT query;
    rayQueryInitializeEXT(query, accelerationStructureEXT(tracing.shapes),
                          gl_RayFlagsOpaqueEXT | gl_RayFlagsTerminateOnFirstHitEXT,
                          shadow_mask, origin, 0.0, direction, reach);
    while (rayQueryProceedEXT(query)) {
    }
    return rayQueryGetIntersectionTypeEXT(query, true) != gl_RayQueryCommittedIntersectionNoneEXT;
}

// How lit a point is by directional light `index`: 1 for a light that casts
// no shadow, else the share of rays toward its source no caster meets.
float directionalLit(int index, vec3 to_light, vec3 world, vec3 normal, vec2 pixel) {
    if (int(lights.directional_direction[index].w) < 0) return 1.0;
    vec3 origin = offSurface(world, normal);
    float spread = lights.directional_color[index].w;
    if (spread <= 0.0) return blocked(origin, to_light, far_reach) ? 0.0 : 1.0;
    vec3 across;
    vec3 up;
    squareTo(to_light, across, up);
    float turn = pixelNoise(pixel);
    float lit = 0.0;
    for (int sample_index = 0; sample_index < soft_samples; sample_index++) {
        vec2 offset = discSample(sample_index, soft_samples, turn) * spread;
        lit += blocked(origin, normalize(to_light + across * offset.x + up * offset.y), far_reach) ? 0.0 : 1.0;
    }
    return lit / float(soft_samples);
}

// How lit a point is by point light `index`: 1 for a light that casts no
// shadow, else the share of rays toward its sphere no caster meets.
float pointLit(int index, vec3 world, vec3 normal, vec2 pixel) {
    float radius = lights.point_color[index].w;
    if (radius < 0.0) return 1.0;
    vec3 origin = offSurface(world, normal);
    vec3 center = lights.point_position[index].xyz;
    vec3 toward = center - origin;
    float reach = length(toward);
    if (reach <= 0.0) return 1.0;
    if (radius <= 0.0) return blocked(origin, toward / reach, reach) ? 0.0 : 1.0;
    vec3 across;
    vec3 up;
    squareTo(toward / reach, across, up);
    float turn = pixelNoise(pixel);
    float lit = 0.0;
    for (int sample_index = 0; sample_index < soft_samples; sample_index++) {
        vec2 offset = discSample(sample_index, soft_samples, turn) * radius;
        vec3 to_target = center + across * offset.x + up * offset.y - origin;
        float distance = length(to_target);
        // A sample on the point itself lights it, as a light at the point does (no ray: its direction would be NaN).
        lit += (distance <= 0.0 || !blocked(origin, to_target / distance, distance)) ? 1.0 : 0.0;
    }
    return lit / float(soft_samples);
}

// The light a point of a surface sends toward the eye from the scene's
// lights, unclamped: ambient, then each directional and point light's
// diffuse and highlight, each dimmed by its traced shadow where the surface
// `receives` shadows and `shadowed` (false for what a reflection shows,
// which would cost a ray a light to shadow). `normal` faces the eye.
vec3 lightPoint(vec3 albedo, vec3 world, vec3 normal, vec3 to_eye, float specular, float shininess, bool receives, bool shadowed, vec2 pixel) {
    vec3 color = lights.ambient.rgb * albedo;
    int directional_count = int(lights.eye.w);
    for (int index = 0; index < 4; index++) {
        if (index >= directional_count) break;
        vec3 to_light = -normalize(lights.directional_direction[index].xyz);
        float diffuse = max(dot(normal, to_light), 0.0);
        if (diffuse <= 0.0) continue;
        float highlight = pow(max(dot(normal, normalize(to_light + to_eye)), 0.0), shininess) * specular;
        float lit = (receives && shadowed) ? directionalLit(index, to_light, world, normal, pixel) : 1.0;
        color += (albedo * diffuse + highlight) * lights.directional_color[index].rgb * lit;
    }
    int point_count = int(lights.ambient.w);
    for (int index = 0; index < 8; index++) {
        if (index >= point_count) break;
        vec3 offset = lights.point_position[index].xyz - world;
        float separation = length(offset);
        float range = lights.point_position[index].w;
        if (separation >= range || separation <= 0.0) continue;
        vec3 to_light = offset / separation;
        float diffuse = max(dot(normal, to_light), 0.0);
        if (diffuse <= 0.0) continue;
        float fade = 1.0 - separation / range;
        float highlight = pow(max(dot(normal, normalize(to_light + to_eye)), 0.0), shininess) * specular;
        float lit = (receives && shadowed) ? pointLit(index, world, normal, pixel) : 1.0;
        color += (albedo * diffuse + highlight) * lights.point_color[index].rgb * fade * fade * lit;
    }
    return color;
}

// Reflected texture `index` sampled at `uv`, its first level (a ray has no
// derivatives to pick one by).
vec3 reflectedTexel(int index, vec2 uv) {
    if (index == 0) return textureLod(reflected0, uv, 0.0).rgb;
    if (index == 1) return textureLod(reflected1, uv, 0.0).rgb;
    if (index == 2) return textureLod(reflected2, uv, 0.0).rgb;
    if (index == 3) return textureLod(reflected3, uv, 0.0).rgb;
    if (index == 4) return textureLod(reflected4, uv, 0.0).rgb;
    if (index == 5) return textureLod(reflected5, uv, 0.0).rgb;
    if (index == 6) return textureLod(reflected6, uv, 0.0).rgb;
    if (index == 7) return textureLod(reflected7, uv, 0.0).rgb;
    return vec3(1.0);
}

// The color a reflection ray sees where it meets a shape: its surface lit
// by the scene's lights, unshadowed.
vec3 litHit(uint instance_id, uint primitive_id, vec2 barycentric, vec3 world, vec3 direction) {
    SceneHitInstance instance = SceneHitInstances(tracing.instances).items[instance_id];
    SceneHitTriangle triangle = SceneHitTriangles(tracing.triangles).items[instance.first_triangle + primitive_id];
    float first = 1.0 - barycentric.x - barycentric.y;
    vec3 local = triangle.normals[0].xyz * first + triangle.normals[1].xyz * barycentric.x + triangle.normals[2].xyz * barycentric.y;
    mat3 normal_matrix = mat3(instance.normal_matrix[0].xyz, instance.normal_matrix[1].xyz, instance.normal_matrix[2].xyz);
    vec3 normal = normalize(normal_matrix * local);
    vec3 to_viewer = -direction;
    if (dot(normal, to_viewer) < 0.0) normal = -normal;
    vec3 albedo = instance.color.rgb;
    if (instance.texture >= 0) {
        vec2 uv = triangle.uvs[0] * first + triangle.uvs[1] * barycentric.x + triangle.uvs[2] * barycentric.y;
        albedo *= reflectedTexel(instance.texture, uv);
    }
    vec3 color = lightPoint(albedo, world, normal, to_viewer, instance.color.w, max(instance.shininess, 1.0), false, false, vec2(0.0));
    return clamp(color, 0.0, 1.0);
}

// `color` with what a reflective surface mirrors mixed in, by Schlick's
// approximation: the reflectivity head on, all of it at grazing angles.
vec3 reflected(vec3 color, vec3 world, vec3 normal, vec3 to_eye) {
    float reflectivity = surface.surface.w;
    if (reflectivity <= 0.0) return color;
    float facing = 1.0 - clamp(dot(normal, to_eye), 0.0, 1.0);
    float share = reflectivity + (1.0 - reflectivity) * facing * facing * facing * facing * facing;
    vec3 direction = reflect(-to_eye, normal);
    vec3 origin = offSurface(world, normal);
    rayQueryEXT query;
    rayQueryInitializeEXT(query, accelerationStructureEXT(tracing.shapes), gl_RayFlagsOpaqueEXT,
                          reflection_mask, origin, 0.0, direction, far_reach);
    while (rayQueryProceedEXT(query)) {
    }
    vec3 seen = tracing.sky.rgb;
    if (rayQueryGetIntersectionTypeEXT(query, true) != gl_RayQueryCommittedIntersectionNoneEXT) {
        float distance = rayQueryGetIntersectionTEXT(query, true);
        seen = litHit(uint(rayQueryGetIntersectionInstanceIdEXT(query, true)),
                      uint(rayQueryGetIntersectionPrimitiveIndexEXT(query, true)),
                      rayQueryGetIntersectionBarycentricsEXT(query, true),
                      origin + direction * distance, direction);
    }
    return mix(color, seen, share);
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

    vec3 color = lightPoint(albedo, v_world, normal, to_eye, specular, shininess, receives, true, gl_FragCoord.xy);
    color = reflected(color, v_world, normal, to_eye);

    color = clamp(color, 0.0, 1.0);
    if (lights.shadow_parameters.z > 0.5) color = encodeSrgb(color);
    out_color = vec4(color, alpha);
}
