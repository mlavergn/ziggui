// The lit fragment function with ray-traced shadows and reflections,
// Metal's alone: compiled appended to scene.metal (SDL_GPU compiles one
// source per shader, so the shared `shade` comes along), and only on a device
// that traces rays from a render pipeline.
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
// SceneRayTracer.bind binds, past the uniform buffers SDL_GPU binds: the
// shapes' instance acceleration structure at [[buffer(16)]] (its
// instances' primitive structures resident on SDL's render encoder), each
// instance's surface at [[buffer(17)]], each mesh triangle's vertex normals
// and texture coordinates at [[buffer(18)]], the sky at [[buffer(19)]], and
// the textures reflections sample at [[texture(8)]] on (an instance whose
// `texture` is -1 shows its color alone, its texture's average in).

#include <metal_raytracing>

// One instance's surface, as a reflection ray meets it; in the instances'
// order in the shapes' structure.
struct SceneHitInstance {
    float4 normal_matrix[3];
    float4 color;
    uint first_triangle;
    float shininess;
    int texture;
    float unused;
};

// A mesh triangle's three vertex normals, in the mesh's space, and their
// texture coordinates.
struct SceneHitTriangle {
    float4 normals[3];
    float2 uvs[3];
    float2 unused;
};

// What a reflection that meets nothing shows.
struct SceneTracing {
    float4 sky;
};

// The instance mask bit of the shapes that cast shadows.
constant uint shadow_mask = 1;
// The instance mask bit of the shapes reflections show (every opaque one).
constant uint reflection_mask = 2;
// How many rays a soft shadow sends a light.
constant int soft_samples = 16;
// How many textures reflections sample (the instances' `texture` indexes them).
constant int reflected_texture_count = 8;
// How a reflection samples a texture: its first level (a ray has no
// derivatives to pick one by), repeating as the lit pass's sampler does.
constexpr sampler reflected_sampler(filter::linear, address::repeat);

// A number in [0, 1) that changes from pixel to pixel without a pattern the
// eye picks up (interleaved gradient noise), turning each pixel's samples.
static float pixel_noise(float2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
}

// A point moved off its surface along the normal, by a share of its
// distance from the origin, so a ray from it does not meet that surface.
static float3 off_surface(float3 world, float3 normal) {
    float scale = max(1.0, max(abs(world.x), max(abs(world.y), abs(world.z))));
    return world + normal * (0.001 * scale);
}

// Sample `index` of `count` spread evenly over the unit disc (a golden-angle
// spiral), turned by `turn` of a full turn.
static float2 disc_sample(int index, int count, float turn) {
    float radius = sqrt((float(index) + 0.5) / float(count));
    float angle = float(index) * 2.39996323 + turn * 6.28318531;
    return radius * float2(cos(angle), sin(angle));
}

// Two unit vectors square to `axis` and to each other.
static void square_to(float3 axis, thread float3 &across, thread float3 &up) {
    float3 helper = abs(axis.y) < 0.99 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
    across = normalize(cross(helper, axis));
    up = cross(axis, across);
}

// Whether a ray meets a shadow caster before `reach`.
static bool blocked(raytracing::instance_acceleration_structure shapes, float3 origin, float3 direction, float reach) {
    raytracing::ray shadow_ray(origin, direction, 0.0, reach);
    raytracing::intersector<raytracing::instancing> query;
    query.accept_any_intersection(true);
    query.assume_geometry_type(raytracing::geometry_type::triangle);
    query.force_opacity(raytracing::forced_opacity::opaque);
    return query.intersect(shadow_ray, shapes, shadow_mask).type != raytracing::intersection_type::none;
}

// Lighting with no shadows: what a reflection shows of the surface it
// meets, which would cost a ray a light to shadow.
struct Unshadowed {
    float directional(constant SceneLights &lights, int index, float3 to_light, float3 world, float3 normal, float2 pixel) const {
        return 1.0;
    }

    float point(constant SceneLights &lights, int index, float3 world, float3 normal, float2 pixel) const {
        return 1.0;
    }
};

// Shadows found by tracing rays toward each light, and reflections by
// tracing one along the mirror direction.
struct TracedLighting {
    raytracing::instance_acceleration_structure shapes;
    device const SceneHitInstance *instances;
    device const SceneHitTriangle *triangles;
    constant SceneTracing *tracing;
    array<texture2d<float>, reflected_texture_count> textures;

    float directional(constant SceneLights &lights, int index, float3 to_light, float3 world, float3 normal, float2 pixel) const {
        if (int(lights.directional_direction[index].w) < 0) return 1.0;
        float3 origin = off_surface(world, normal);
        float spread = lights.directional_color[index].w;
        if (spread <= 0.0) return blocked(shapes, origin, to_light, INFINITY) ? 0.0 : 1.0;
        float3 across, up;
        square_to(to_light, across, up);
        float turn = pixel_noise(pixel);
        float lit = 0.0;
        for (int sample = 0; sample < soft_samples; sample++) {
            float2 offset = disc_sample(sample, soft_samples, turn) * spread;
            lit += blocked(shapes, origin, normalize(to_light + across * offset.x + up * offset.y), INFINITY) ? 0.0 : 1.0;
        }
        return lit / float(soft_samples);
    }

    float point(constant SceneLights &lights, int index, float3 world, float3 normal, float2 pixel) const {
        float radius = lights.point_color[index].w;
        if (radius < 0.0) return 1.0;
        float3 origin = off_surface(world, normal);
        float3 center = lights.point_position[index].xyz;
        float3 toward = center - origin;
        float reach = length(toward);
        if (reach <= 0.0) return 1.0;
        if (radius <= 0.0) return blocked(shapes, origin, toward / reach, reach) ? 0.0 : 1.0;
        float3 across, up;
        square_to(toward / reach, across, up);
        float turn = pixel_noise(pixel);
        float lit = 0.0;
        for (int sample = 0; sample < soft_samples; sample++) {
            float2 offset = disc_sample(sample, soft_samples, turn) * radius;
            float3 to_target = center + across * offset.x + up * offset.y - origin;
            float distance = length(to_target);
            // A sample on the point itself lights it, as a light at the point does (no ray: its direction would be NaN).
            lit += (distance <= 0.0 || !blocked(shapes, origin, to_target / distance, distance)) ? 1.0 : 0.0;
        }
        return lit / float(soft_samples);
    }

    float3 reflected(constant SceneLights &lights, constant SceneSurface &surface, float3 color, float3 world, float3 normal, float3 to_eye, float2 pixel) const {
        float reflectivity = surface.surface.w;
        if (reflectivity <= 0.0) return color;
        // Schlick's approximation: the reflectivity head on, all of it at grazing.
        float facing = 1.0 - saturate(dot(normal, to_eye));
        float share = reflectivity + (1.0 - reflectivity) * facing * facing * facing * facing * facing;
        float3 direction = reflect(-to_eye, normal);
        raytracing::ray mirror_ray(off_surface(world, normal), direction, 0.0, INFINITY);
        raytracing::intersector<raytracing::instancing, raytracing::triangle_data> query;
        query.assume_geometry_type(raytracing::geometry_type::triangle);
        query.force_opacity(raytracing::forced_opacity::opaque);
        auto hit = query.intersect(mirror_ray, shapes, reflection_mask);
        float3 seen = tracing->sky.rgb;
        if (hit.type != raytracing::intersection_type::none) {
            seen = lit_hit(lights, hit.instance_id, hit.primitive_id, hit.triangle_barycentric_coord,
                           mirror_ray.origin + direction * hit.distance, direction);
        }
        return mix(color, seen, share);
    }

    // The color a reflection ray sees where it meets a shape: its surface
    // lit by the scene's lights, unshadowed.
    float3 lit_hit(constant SceneLights &lights, uint instance_id, uint primitive_id, float2 barycentric, float3 world, float3 direction) const {
        SceneHitInstance instance = instances[instance_id];
        SceneHitTriangle triangle = triangles[instance.first_triangle + primitive_id];
        float3 local = triangle.normals[0].xyz * (1.0 - barycentric.x - barycentric.y)
                     + triangle.normals[1].xyz * barycentric.x
                     + triangle.normals[2].xyz * barycentric.y;
        float3x3 normal_matrix = float3x3(instance.normal_matrix[0].xyz, instance.normal_matrix[1].xyz, instance.normal_matrix[2].xyz);
        float3 normal = normalize(normal_matrix * local);
        float3 to_viewer = -direction;
        if (dot(normal, to_viewer) < 0.0) normal = -normal;
        float3 albedo = instance.color.rgb;
        if (instance.texture >= 0 && instance.texture < reflected_texture_count) {
            float2 uv = triangle.uvs[0] * (1.0 - barycentric.x - barycentric.y) + triangle.uvs[1] * barycentric.x + triangle.uvs[2] * barycentric.y;
            albedo *= textures[instance.texture].sample(reflected_sampler, uv, level(0.0)).rgb;
        }
        Unshadowed unshadowed;
        float3 color = light_point(lights, unshadowed, albedo, world, normal, to_viewer, instance.color.w, max(instance.shininess, 1.0), false, float2(0.0));
        return clamp(color, 0.0, 1.0);
    }
};

fragment float4 scene_traced_fragment(SceneVaryings in [[stage_in]],
                                      constant SceneLights &lights [[buffer(0)]],
                                      constant SceneSurface &surface [[buffer(1)]],
                                      texture2d<float> base_texture [[texture(0)]],
                                      sampler base_sampler [[sampler(0)]],
                                      raytracing::instance_acceleration_structure shapes [[buffer(16)]],
                                      device const SceneHitInstance *instances [[buffer(17)]],
                                      device const SceneHitTriangle *triangles [[buffer(18)]],
                                      constant SceneTracing &tracing [[buffer(19)]],
                                      array<texture2d<float>, reflected_texture_count> textures [[texture(8)]]) {
    TracedLighting lighting = { shapes, instances, triangles, &tracing, textures };
    return shade(in, lights, surface, base_texture, base_sampler, lighting);
}
