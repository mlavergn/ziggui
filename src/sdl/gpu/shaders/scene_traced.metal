// The lit fragment function with ray-traced shadows and reflections,
// Metal's alone: compiled appended to scene.metal (SDL_GPU compiles one
// source per shader, so the shared `shade` comes along), and only on a device
// that traces rays from a render pipeline.
//
// A directional light whose `directional_direction.w` is not -1 casts a
// shadow, softened over a cone `directional_color.w` (its angular radius's
// tangent) wide; a point light whose `point_color.w` is not -1 casts one,
// softened over a sphere that radius wide. A soft shadow sends
// up to `sky.w` rays spread over the light's source (a quarter of them
// first, the rest only where those disagree: a penumbra) (a golden-angle disc,
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
// `texture` is -1 shows its color alone, its texture's average in), and a
// directional light's cookie at [[texture(16)]]: the light that reaches a
// point, directly or as a reflection shows it, is scaled by the cookie's
// texel where the ray to the light crosses the cookie's plane; and an
// environment at [[texture(17)]], its overlays at [[texture(18)]] on, for
// reflections that meet nothing.

#include <metal_raytracing>

// One instance's surface, as a reflection ray meets it; in the instances'
// order in the shapes' structure.
struct SceneHitInstance {
    float4 normal_matrix[3];
    float4 color;
    uint first_triangle;
    float shininess;
    int texture;
    float emission;
};

// A mesh triangle's three vertex normals, in the mesh's space, and their
// texture coordinates.
struct SceneHitTriangle {
    float4 normals[3];
    float2 uvs[3];
    float2 unused;
};

// A texture on a plane (`ScenePlaneTexture.equations`): at a point p, its
// u is dot(p, u.xyz) + u.w, its v likewise, and p is on the plane where
// dot(p, plane.xyz) + plane.w is 0 (plane.xyz its unit normal).
struct ScenePlane {
    float4 u;
    float4 v;
    float4 plane;
};

// What a reflection that meets nothing shows (`sky.w`: the most rays a soft
// shadow sends); `environment` what it sees in place of that color: x 1 when
// bound (at [[texture(17)]]), y how far down from straight up its texture
// reaches, z its strength, w the level sampled; `planes.x` the index of the
// directional light the cookie filters (-1 for none; at [[texture(16)]]),
// `planes.y` how many of the `overlays` are laid over the environment (at
// [[texture(18)]] on).
struct SceneTracing {
    float4 sky;
    float4 environment;
    float4 planes;
    ScenePlane cookie;
    ScenePlane overlays[4];
};

// The instance mask bit of the shapes that cast shadows.
constant uint shadow_mask = 1;
// The instance mask bit of the shapes reflections show (every opaque one).
constant uint reflection_mask = 2;
// How many rays a soft shadow sends a light, at most, is the scene's
// (`SceneTracing.sky.w`, 4 to 32): a quarter first, the rest only in a
// penumbra; a multiple of four, so each quarter is whole.
// How many textures reflections sample (the instances' `texture` indexes them).
constant int reflected_texture_count = 8;
// How a reflection samples a texture: its first level (a ray has no
// derivatives to pick one by), repeating as the lit pass's sampler does.
constexpr sampler reflected_sampler(filter::linear, address::repeat);
// How a cookie is sampled: repeating, its first level (the plane's texels
// are far larger than a pixel's footprint on the ground).
constexpr sampler cookie_sampler(filter::linear, address::repeat);
// How the environment is sampled: around the horizon it repeats, down it clamps.
constexpr sampler environment_sampler(filter::linear, mip_filter::linear, s_address::repeat, t_address::clamp_to_edge);
// How an overlay is sampled: repeating both ways.
constexpr sampler overlay_sampler(filter::linear, mip_filter::linear, address::repeat);

// Where a ray from `origin` along unit `direction` crosses a plane ahead:
// the plane's texture coordinates there, in `uv`, and how squarely the ray
// meets the plane (|cosine|) in `facing`; false when it doesn't cross ahead.
static bool plane_crossing(constant ScenePlane &plane, float3 origin, float3 direction, thread float2 &uv, thread float &facing) {
    const float along = dot(direction, plane.plane.xyz);
    facing = abs(along);
    if (facing < 1e-4) return false;
    const float reach = -(dot(origin, plane.plane.xyz) + plane.plane.w) / along;
    if (reach <= 0.0) return false;
    const float3 crossing = origin + direction * reach;
    uv = float2(dot(crossing, plane.u.xyz) + plane.u.w, dot(crossing, plane.v.xyz) + plane.v.w);
    return true;
}

// What a ray that meets nothing sees from `origin` along `direction`: the
// environment by direction (or the sky color without one), and over it, in
// order, each overlay where the ray crosses its plane ahead, by its alpha,
// fading where the ray grazes the plane.
static float3 sky_seen(constant SceneTracing *tracing, texture2d<float> environment, array<texture2d<float>, 4> overlays, float3 origin, float3 direction) {
    if (tracing->environment.x < 0.5) return tracing->sky.rgb;
    const float strength = tracing->environment.z;
    const float level_sampled = tracing->environment.w;
    const float polar = acos(clamp(direction.y, -1.0, 1.0));
    const float2 uv = float2(atan2(direction.z, direction.x) / 6.2831853, min(polar / tracing->environment.y, 1.0));
    float3 seen = environment.sample(environment_sampler, uv, level(level_sampled)).rgb * strength;
    const int count = min(int(tracing->planes.y), 4);
    for (int index = 0; index < count; index++) {
        float2 crossing;
        float facing;
        if (!plane_crossing(tracing->overlays[index], origin, direction, crossing, facing)) continue;
        const float4 texel = overlays[index].sample(overlay_sampler, crossing, level(level_sampled));
        seen = mix(seen, texel.rgb * strength, texel.a * smoothstep(0.02, 0.15, facing));
    }
    return seen;
}

// What of directional light `index` passes its cookie on the way to `world`:
// the texel where the ray toward the light crosses the cookie's plane,
// fading to white as the ray grazes it; white for another light or a ray
// that doesn't cross the plane ahead.
static float3 through_cookie(constant SceneTracing *tracing, texture2d<float> cookie, int index, float3 to_light, float3 world) {
    if (int(tracing->planes.x) != index) return float3(1.0);
    float2 crossing;
    float facing;
    if (!plane_crossing(tracing->cookie, world, to_light, crossing, facing)) return float3(1.0);
    const float3 texel = cookie.sample(cookie_sampler, crossing, level(0.0)).rgb;
    return mix(float3(1.0), texel, smoothstep(0.005, 0.02, facing));
}

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

// How far apart a soft shadow's first samples are: every fourth, but at
// least four of them (fewer agree by chance, which speckles a penumbra; one
// would always agree), so every second below 16 and all below 8. Only 1, 2
// and 4 spread well around the golden-angle spiral (3 bunches to one side).
static int first_stride(int count) {
    return count >= 16 ? 4 : (count >= 8 ? 2 : 1);
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
// meets, which would cost a ray a light to shadow; a cookie still filters it.
struct Unshadowed {
    constant SceneTracing *tracing;
    texture2d<float> cookie;

    float3 directional(constant SceneLights &lights, int index, float3 to_light, float3 world, float3 normal, float2 pixel) const {
        return through_cookie(tracing, cookie, index, to_light, world);
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
    texture2d<float> cookie;
    texture2d<float> environment;
    array<texture2d<float>, 4> overlays;

    // The light that reaches a point: its shadow's share, through its cookie.
    float3 directional(constant SceneLights &lights, int index, float3 to_light, float3 world, float3 normal, float2 pixel) const {
        float3 filtered = through_cookie(tracing, cookie, index, to_light, world);
        if (all(filtered <= float3(0.0))) return filtered;
        return filtered * shadowed(lights, index, to_light, world, normal, pixel);
    }

    // How much of a directional light's source a point sees, by rays toward it.
    float shadowed(constant SceneLights &lights, int index, float3 to_light, float3 world, float3 normal, float2 pixel) const {
        if (int(lights.directional_direction[index].w) < 0) return 1.0;
        float3 origin = off_surface(world, normal);
        float spread = lights.directional_color[index].w;
        if (spread <= 0.0) return blocked(shapes, origin, to_light, INFINITY) ? 0.0 : 1.0;
        const int soft_samples = int(tracing->sky.w);
        float3 across, up;
        square_to(to_light, across, up);
        float turn = pixel_noise(pixel);
        float lit = 0.0;
        // Every `stride`th sample first, spread over the source: where they agree the
        // point is wholly lit or shadowed (as most are) and the rest would agree.
        const int stride = first_stride(soft_samples);
        const float first = float(soft_samples / stride);
        for (int sample = 0; sample < soft_samples; sample += stride) {
            float2 offset = disc_sample(sample, soft_samples, turn) * spread;
            lit += blocked(shapes, origin, normalize(to_light + across * offset.x + up * offset.y), INFINITY) ? 0.0 : 1.0;
        }
        if (lit <= 0.0 || lit >= first || stride == 1) return lit / first;
        for (int sample = 0; sample < soft_samples; sample++) {
            if (sample % stride == 0) continue;
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
        // Past its shadow range, unshadowed: no rays; over the range's last fifth, the shadow fades out.
        const float shadow_range = lights.point_shadow[index].x;
        if (reach <= 0.0 || reach >= shadow_range) return 1.0;
        const float faded = smoothstep(0.8 * shadow_range, shadow_range, reach);
        if (radius <= 0.0) return blocked(shapes, origin, toward / reach, reach) ? faded : 1.0;
        const int soft_samples = int(lights.point_shadow[index].y);
        float3 across, up;
        square_to(toward / reach, across, up);
        float turn = pixel_noise(pixel);
        float lit = 0.0;
        // Every `stride`th sample first; the rest only in a penumbra, as for a directional light.
        const int stride = first_stride(soft_samples);
        const float first = float(soft_samples / stride);
        for (int pass = 0; pass < 2; pass++) {
            for (int sample = 0; sample < soft_samples; sample++) {
                if ((sample % stride == 0) != (pass == 0)) continue;
                float2 offset = disc_sample(sample, soft_samples, turn) * radius;
                float3 to_target = center + across * offset.x + up * offset.y - origin;
                float distance = length(to_target);
                // A sample on the point itself lights it, as a light at the point does (no ray: its direction would be NaN).
                lit += (distance <= 0.0 || !blocked(shapes, origin, to_target / distance, distance)) ? 1.0 : 0.0;
            }
            if (pass == 0 && (lit <= 0.0 || lit >= first || stride == 1)) return mix(lit / first, 1.0, faded);
        }
        return mix(lit / float(soft_samples), 1.0, faded);
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
        float3 seen = sky_seen(tracing, environment, overlays, mirror_ray.origin, direction);
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
        Unshadowed unshadowed = { tracing, cookie };
        float3 color = light_point(lights, unshadowed, albedo, world, normal, to_viewer, instance.color.w, max(instance.shininess, 1.0), true, float2(0.0));
        // An emissive surface shows its own color, unlit, by its share.
        return clamp(mix(color, albedo, instance.emission), 0.0, 1.0);
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
                                      array<texture2d<float>, reflected_texture_count> textures [[texture(8)]],
                                      texture2d<float> cookie [[texture(16)]],
                                      texture2d<float> environment [[texture(17)]],
                                      array<texture2d<float>, 4> overlays [[texture(18)]]) {
    TracedLighting lighting = { shapes, instances, triangles, &tracing, textures, cookie, environment, overlays };
    return shade(in, lights, surface, base_texture, base_sampler, lighting);
}
