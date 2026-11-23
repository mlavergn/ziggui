//! Draws 3D scenes (`renderer.SceneStep`, a `SceneView`'s) on the GPU device
//! the UI draws with: the lit and blended pipelines and the shadow maps' depth
//! pipeline, the vertices and textures each geometry and material uploads
//! (kept by key and freed once unused), a depth buffer the size of the target,
//! and up to four shadow maps.
//!
//! A scene step breaks the UI's render pass: shadow passes first, one per
//! directional light that casts a shadow, then a pass over the target (its
//! pixels kept, a fresh depth buffer) viewported to the view and cut to its
//! clip: the opaque shapes, then the translucent ones from back to front.
//! A scene that asks for `SceneLightingTechnique.rayTraced` on a device that
//! traces rays (`SceneRayTracer`) draws no shadow maps: its opaque shapes'
//! acceleration structures are built instead, and the pass draws with the
//! traced fragment shader, which meets rays toward each light (soft ones
//! from a light with a source size, point lights' too) and along a
//! reflective surface's mirror direction against them.
//! Like the rest of the `sdl` module this file links C and is never part of
//! the core library or its tests.

const std = @import("std");
const log = std.log.scoped(.ziggui_scene_renderer);
const mod = @import("../module.zig");
const renderer = @import("renderer");
const scenes = @import("scenes");
const sdl_c = @import("sdl_c");

/// The shaders a `SceneRenderer`'s pipelines are made from, made by `Gpu`
/// (which holds the HLSL compiler), released by it once the pipelines exist.
pub const SceneShaders = struct {
    const Self = @This();

    /// The lit vertex shader (`scene_vertex`).
    lit_vertex: *sdl_c.SDL_GPUShader,
    /// The lit fragment shader (`scene_fragment`).
    lit_fragment: *sdl_c.SDL_GPUShader,
    /// The shadow map's vertex shader (`scene_shadow_vertex`).
    shadow_vertex: *sdl_c.SDL_GPUShader,
    /// The shadow map's fragment shader (`scene_shadow_fragment`).
    shadow_fragment: *sdl_c.SDL_GPUShader,
    /// The lit fragment shader with ray-traced shadows and reflections
    /// (`scene_traced_fragment`), only where rays can be traced; null draws
    /// every scene's shadows from shadow maps.
    traced_fragment: ?*sdl_c.SDL_GPUShader = null,
};

/// The lit and blended pipelines over the traced fragment shader.
const TracedPipelines = struct {
    const Self = @This();

    /// Opaque shapes, as `SceneRenderer.lit_pipeline`.
    lit: *sdl_c.SDL_GPUGraphicsPipeline,
    /// Translucent shapes, as `SceneRenderer.blended_pipeline`.
    blended: *sdl_c.SDL_GPUGraphicsPipeline,
};

/// A geometry's vertices and indices on the GPU.
const MeshEntry = struct {
    const Self = @This();

    /// `SceneGeometry.key`.
    key: u64,
    /// The vertices.
    vertex_buffer: *sdl_c.SDL_GPUBuffer,
    /// The indices.
    index_buffer: *sdl_c.SDL_GPUBuffer,
    /// How many indices it draws.
    index_count: u32,
    /// The frame it last drew in.
    used_in: u64,
};

/// A material's texture on the GPU, with its mipmaps.
const TextureEntry = struct {
    const Self = @This();

    /// `SceneTexture.key`.
    key: u64,
    /// The texture.
    texture: *sdl_c.SDL_GPUTexture,
    /// The frame it last drew in.
    used_in: u64,
};

/// The lit vertex shader's uniforms; layout as `SceneVertexUniforms` in the shaders.
const VertexUniforms = extern struct {
    const Self = @This();

    model: scenes.Mat4,
    normal_matrix: scenes.Mat4,
    view_projection: scenes.Mat4,
};

/// The shadow vertex shader's uniforms; layout as `SceneShadowUniforms`.
const ShadowUniforms = extern struct {
    const Self = @This();

    model: scenes.Mat4,
    light: scenes.Mat4,
};

/// The lit fragment shader's lights; layout as `SceneLights` (std140, every
/// member a float4 or a float4x4).
const LightUniforms = extern struct {
    const Self = @This();

    eye: [4]f32,
    ambient: [4]f32,
    directional_direction: [scenes.SceneFrame.max_directional_lights][4]f32,
    directional_color: [scenes.SceneFrame.max_directional_lights][4]f32,
    point_position: [scenes.SceneFrame.max_point_lights][4]f32,
    point_color: [scenes.SceneFrame.max_point_lights][4]f32,
    shadow: [scenes.SceneFrame.max_directional_lights]scenes.Mat4,
    shadow_parameters: [4]f32,
};

/// The lit fragment shader's surface; layout as `SceneSurface`.
const SurfaceUniforms = extern struct {
    const Self = @This();

    base_color: [4]f32,
    surface: [4]f32,
};

/// Draws 3D scenes on a GPU device. Made by `Gpu` on the first scene step,
/// released with it.
pub const SceneRenderer = struct {
    const Self = @This();

    /// A shadow map's side, in texels.
    pub const shadow_map_side = 2048;
    /// Frames a mesh, texture, depth buffer or shadow map outlives its last
    /// draw before it is freed (about two seconds at 60 frames a second).
    const idle_frames = 120;
    /// The depth subtracted before a shadow test, against acne.
    const shadow_bias = 0.002;
    /// Straight-alpha `over`, as the UI's pipelines blend: the translucent
    /// shapes' blend, rasterized or traced.
    const over_blend = sdl_c.SDL_GPUColorTargetBlendState{
        .src_color_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
        .dst_color_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = sdl_c.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .alpha_blend_op = sdl_c.SDL_GPU_BLENDOP_ADD,
        .enable_blend = true,
    };

    /// Owns the caches.
    allocator: std.mem.Allocator,
    /// The GPU device.
    device: *sdl_c.SDL_GPUDevice,
    /// Opaque shapes: depth tested and written, no blending.
    lit_pipeline: *sdl_c.SDL_GPUGraphicsPipeline,
    /// Translucent shapes: depth tested, not written, blended over.
    blended_pipeline: *sdl_c.SDL_GPUGraphicsPipeline,
    /// Shadow maps: depth only.
    shadow_pipeline: *sdl_c.SDL_GPUGraphicsPipeline,
    /// Base-color textures: linear, mipmapped, repeating.
    base_sampler: *sdl_c.SDL_GPUSampler,
    /// Shadow maps: nearest, clamped.
    shadow_sampler: *sdl_c.SDL_GPUSampler,
    /// The depth buffer's format.
    depth_format: sdl_c.SDL_GPUTextureFormat,
    /// The shadow maps' format (sampled as well as written).
    shadow_format: sdl_c.SDL_GPUTextureFormat,
    /// Whether the shaders encode their output to sRGB (a UNORM target).
    encode_srgb: bool,
    /// A white texel, for a material with no texture.
    white_texture: ?*sdl_c.SDL_GPUTexture = null,
    /// A cleared depth texel, bound where a light has no shadow map.
    blank_shadow: ?*sdl_c.SDL_GPUTexture = null,
    /// Whether the white and blank texels hold their values yet.
    defaults_ready: bool = false,
    /// The depth buffer, the size of the target.
    depth_texture: ?*sdl_c.SDL_GPUTexture = null,
    /// The depth buffer's width.
    depth_width: u32 = 0,
    /// The depth buffer's height.
    depth_height: u32 = 0,
    /// One shadow map per directional light, made on first need.
    shadow_maps: [scenes.SceneFrame.max_directional_lights]?*sdl_c.SDL_GPUTexture = @splat(null),
    /// The geometries on the GPU.
    meshes: std.ArrayList(MeshEntry) = .empty,
    /// The textures on the GPU.
    textures: std.ArrayList(TextureEntry) = .empty,
    /// The pipelines that trace shadow rays, null where rays cannot be traced.
    traced_pipelines: ?TracedPipelines = null,
    /// Builds and binds the opaque shapes' acceleration structures, beside `traced_pipelines`.
    ray_tracer: ?mod.SceneRayTracer = null,
    /// Counts the frames (`nextFrame`).
    frame_counter: u64 = 0,
    /// The frame a scene last drew in.
    drawn_in: u64 = 0,

    /// Makes the pipelines and samplers.
    ///
    /// - `allocator`: owns the caches.
    /// - `device`: the GPU device.
    /// - `target_format`: the format of the texture scenes are drawn into.
    /// - `shaders`: the shaders, which the caller releases afterwards.
    /// - Returns: the renderer, or null when the device cannot make them (logged).
    pub fn init(allocator: std.mem.Allocator, device: *sdl_c.SDL_GPUDevice, target_format: sdl_c.SDL_GPUTextureFormat, shaders: SceneShaders) ?Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const depth_usage = sdl_c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET;
        const depth_format = Self.firstSupported(device, &.{ sdl_c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT, sdl_c.SDL_GPU_TEXTUREFORMAT_D24_UNORM, sdl_c.SDL_GPU_TEXTUREFORMAT_D16_UNORM }, depth_usage) orelse {
            log.warn("no depth format for 3D scenes", .{});
            return null;
        };
        const shadow_format = Self.firstSupported(device, &.{ sdl_c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT, sdl_c.SDL_GPU_TEXTUREFORMAT_D16_UNORM }, depth_usage | sdl_c.SDL_GPU_TEXTUREUSAGE_SAMPLER) orelse {
            log.warn("no sampled depth format for shadow maps", .{});
            return null;
        };

        const attributes = [_]sdl_c.SDL_GPUVertexAttribute{
            .{ .location = 0, .buffer_slot = 0, .format = sdl_c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(scenes.SceneVertex, "position") },
            .{ .location = 1, .buffer_slot = 0, .format = sdl_c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(scenes.SceneVertex, "normal") },
            .{ .location = 2, .buffer_slot = 0, .format = sdl_c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(scenes.SceneVertex, "uv") },
        };
        const vertex_buffer = sdl_c.SDL_GPUVertexBufferDescription{
            .slot = 0,
            .pitch = @sizeOf(scenes.SceneVertex),
            .input_rate = sdl_c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
        };
        const vertex_input = sdl_c.SDL_GPUVertexInputState{
            .vertex_buffer_descriptions = &vertex_buffer,
            .num_vertex_buffers = 1,
            .vertex_attributes = &attributes,
            .num_vertex_attributes = attributes.len,
        };
        // Neither face is culled: a plane shows from both sides, and the
        // winding then never depends on a backend's clip-space flips.
        const rasterizer_state = sdl_c.SDL_GPURasterizerState{
            .fill_mode = sdl_c.SDL_GPU_FILLMODE_FILL,
            .cull_mode = sdl_c.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl_c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
        };
        var color_target = sdl_c.SDL_GPUColorTargetDescription{ .format = target_format, .blend_state = .{} };
        var create_info = sdl_c.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = shaders.lit_vertex,
            .fragment_shader = shaders.lit_fragment,
            .vertex_input_state = vertex_input,
            .primitive_type = sdl_c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = rasterizer_state,
            .multisample_state = .{},
            .depth_stencil_state = .{
                .compare_op = sdl_c.SDL_GPU_COMPAREOP_LESS,
                .enable_depth_test = true,
                .enable_depth_write = true,
            },
            .target_info = .{
                .color_target_descriptions = &color_target,
                .num_color_targets = 1,
                .depth_stencil_format = depth_format,
                .has_depth_stencil_target = true,
            },
            .props = 0,
        };
        const lit_pipeline = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse {
            log.warn("no lit pipeline for 3D scenes [{s}]", .{sdl_c.SDL_GetError()});
            return null;
        };
        errdefer sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, lit_pipeline);
        const lit_info = create_info;

        color_target.blend_state = over_blend;
        create_info.depth_stencil_state.enable_depth_write = false;
        const blended_pipeline = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse {
            log.warn("no blended pipeline for 3D scenes [{s}]", .{sdl_c.SDL_GetError()});
            return null;
        };
        errdefer sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, blended_pipeline);

        create_info.vertex_shader = shaders.shadow_vertex;
        create_info.fragment_shader = shaders.shadow_fragment;
        create_info.depth_stencil_state.enable_depth_write = true;
        create_info.rasterizer_state.enable_depth_bias = true;
        create_info.rasterizer_state.depth_bias_slope_factor = 1.0;
        create_info.target_info = .{ .num_color_targets = 0, .depth_stencil_format = shadow_format, .has_depth_stencil_target = true };
        const shadow_pipeline = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse {
            log.warn("no shadow pipeline for 3D scenes [{s}]", .{sdl_c.SDL_GetError()});
            return null;
        };
        errdefer sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, shadow_pipeline);

        const base_sampler = sdl_c.SDL_CreateGPUSampler(device, &.{
            .min_filter = sdl_c.SDL_GPU_FILTER_LINEAR,
            .mag_filter = sdl_c.SDL_GPU_FILTER_LINEAR,
            .mipmap_mode = sdl_c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
            .address_mode_u = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
            .address_mode_v = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
            .address_mode_w = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
            .max_lod = 1000,
        }) orelse return null;
        errdefer sdl_c.SDL_ReleaseGPUSampler(device, base_sampler);
        const shadow_sampler = sdl_c.SDL_CreateGPUSampler(device, &.{
            .min_filter = sdl_c.SDL_GPU_FILTER_NEAREST,
            .mag_filter = sdl_c.SDL_GPU_FILTER_NEAREST,
            .mipmap_mode = sdl_c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
            .address_mode_u = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        }) orelse return null;

        var traced_pipelines: ?TracedPipelines = null;
        var ray_tracer: ?mod.SceneRayTracer = null;
        if (shaders.traced_fragment) |traced_fragment| {
            traced_pipelines = Self.makeTracedPipelines(device, lit_info, target_format, traced_fragment);
            if (traced_pipelines != null) ray_tracer = mod.SceneRayTracer.init(allocator, device);
            if (ray_tracer == null) if (traced_pipelines) |pipelines| {
                log.warn("scenes draw rasterized: no ray tracer", .{});
                Self.releaseTracedPipelines(device, pipelines);
                traced_pipelines = null;
            };
        }

        const self = Self{
            .allocator = allocator,
            .device = device,
            .lit_pipeline = lit_pipeline,
            .blended_pipeline = blended_pipeline,
            .shadow_pipeline = shadow_pipeline,
            .base_sampler = base_sampler,
            .shadow_sampler = shadow_sampler,
            .depth_format = depth_format,
            .shadow_format = shadow_format,
            .encode_srgb = target_format != sdl_c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB and target_format != sdl_c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB,
            .traced_pipelines = traced_pipelines,
            .ray_tracer = ray_tracer,
        };
        return self;
    }

    /// Releases the pipelines, samplers, textures and buffers.
    ///
    /// - `self`: the renderer.
    pub fn deinit(self: *Self) void {
        const device = self.device;
        if (self.ray_tracer) |*ray_tracer| ray_tracer.deinit();
        if (self.traced_pipelines) |pipelines| Self.releaseTracedPipelines(device, pipelines);
        for (self.meshes.items) |entry| Self.releaseMesh(device, entry);
        self.meshes.deinit(self.allocator);
        for (self.textures.items) |entry| sdl_c.SDL_ReleaseGPUTexture(device, entry.texture);
        self.textures.deinit(self.allocator);
        self.releaseTargets();
        if (self.white_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(device, texture);
        if (self.blank_shadow) |texture| sdl_c.SDL_ReleaseGPUTexture(device, texture);
        sdl_c.SDL_ReleaseGPUSampler(device, self.base_sampler);
        sdl_c.SDL_ReleaseGPUSampler(device, self.shadow_sampler);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.lit_pipeline);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blended_pipeline);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.shadow_pipeline);
    }

    /// Starts a frame: what has gone unused for `idle_frames` is freed.
    ///
    /// - `self`: the renderer.
    pub fn nextFrame(self: *Self) void {
        self.frame_counter += 1;
        const device = self.device;
        var index: usize = 0;
        while (index < self.meshes.items.len) {
            const entry = self.meshes.items[index];
            if (entry.used_in + idle_frames >= self.frame_counter) {
                index += 1;
                continue;
            }
            Self.releaseMesh(device, entry);
            _ = self.meshes.swapRemove(index);
        }
        index = 0;
        while (index < self.textures.items.len) {
            const entry = self.textures.items[index];
            if (entry.used_in + idle_frames >= self.frame_counter) {
                index += 1;
                continue;
            }
            sdl_c.SDL_ReleaseGPUTexture(device, entry.texture);
            _ = self.textures.swapRemove(index);
        }
        if (self.drawn_in + idle_frames < self.frame_counter) self.releaseTargets();
        if (self.ray_tracer) |*ray_tracer| ray_tracer.nextFrame(self.frame_counter);
    }

    /// Whether this renderer traces a scene's shadow rays (else every scene's
    /// shadows come from shadow maps).
    ///
    /// - `self`: the renderer.
    /// - Returns: true where it has the traced pipelines and a ray tracer.
    pub fn tracesRays(self: *const Self) bool {
        return self.ray_tracer != null;
    }

    /// Draws a scene step into the target: its shadow maps (or, ray traced,
    /// its opaque shapes' acceleration structures), then its shapes over what the
    /// target holds, viewported to its rect and cut to its clip.
    ///
    /// - `self`: the renderer.
    /// - `arena`: the frame's arena, for the gathered frame and uploads' data.
    /// - `command_buffer`: the frame's command buffer, outside any pass.
    /// - `step`: the scene step.
    /// - `target`: the texture drawn into.
    /// - `target_width`: its width, in pixels.
    /// - `target_height`: its height, in pixels.
    /// - Returns: true when it drew; false (nothing drawn) when the scene
    ///   could not be had or uploaded, so the caller draws its placeholder.
    pub fn draw(self: *Self, arena: std.mem.Allocator, command_buffer: *sdl_c.SDL_GPUCommandBuffer, step: renderer.SceneStep, target: *sdl_c.SDL_GPUTexture, target_width: u32, target_height: u32) bool {
        const scissor = Self.scissorOf(step, target_width, target_height) orelse return true;
        const scene: *const scenes.Scene = @ptrCast(@alignCast(step.scene));
        const frame = scenes.SceneFrame.gather(arena, scene, step.rect[2] / step.rect[3]) catch |err| {
            log.warn("scene not gathered: {s}", .{@errorName(err)});
            return false;
        };
        self.drawn_in = self.frame_counter;
        if (!self.ensureDefaults(command_buffer)) return false;
        const meshes = arena.alloc(?MeshEntry, frame.draws.len) catch |err| {
            log.warn("scene's meshes not listed: {s}", .{@errorName(err)});
            return false;
        };
        const textures = arena.alloc(*sdl_c.SDL_GPUTexture, frame.draws.len) catch |err| {
            log.warn("scene's textures not listed: {s}", .{@errorName(err)});
            return false;
        };
        if (!self.prepare(arena, command_buffer, frame, meshes, textures)) return false;
        if (!self.ensureDepth(target_width, target_height)) return false;

        var lights = self.lightUniforms(frame);
        const prepared = self.prepareTraced(arena, command_buffer, scene, frame, meshes, textures, &lights);
        if (!prepared) self.drawShadows(command_buffer, frame, meshes, &lights);
        const color_target = sdl_c.SDL_GPUColorTargetInfo{
            .texture = target,
            .load_op = sdl_c.SDL_GPU_LOADOP_LOAD,
            .store_op = sdl_c.SDL_GPU_STOREOP_STORE,
        };
        const depth_target = sdl_c.SDL_GPUDepthStencilTargetInfo{
            .texture = self.depth_texture,
            .clear_depth = 1,
            .load_op = sdl_c.SDL_GPU_LOADOP_CLEAR,
            .store_op = sdl_c.SDL_GPU_STOREOP_DONT_CARE,
            .stencil_load_op = sdl_c.SDL_GPU_LOADOP_DONT_CARE,
            .stencil_store_op = sdl_c.SDL_GPU_STOREOP_DONT_CARE,
            .cycle = true,
        };
        const pass = sdl_c.SDL_BeginGPURenderPass(command_buffer, &color_target, 1, &depth_target) orelse return false;
        defer sdl_c.SDL_EndGPURenderPass(pass);
        // The viewport is the part on the target (a backend may refuse one past
        // its edges), the projection remapped so the scene lands as the whole
        // rect would put it.
        const viewport = [4]f32{ @floatFromInt(scissor.x), @floatFromInt(scissor.y), @floatFromInt(scissor.w), @floatFromInt(scissor.h) };
        sdl_c.SDL_SetGPUViewport(pass, &.{ .x = viewport[0], .y = viewport[1], .w = viewport[2], .h = viewport[3], .min_depth = 0, .max_depth = 1 });
        sdl_c.SDL_SetGPUScissor(pass, &scissor);
        // Bound on SDL's encoder once the pass is open; should that fail, the
        // lit shaders draw, unshadowed (the blank map answers every test).
        const traced = prepared and self.ray_tracer.?.bind(command_buffer, Self.skyOf(scene, frame), self.white_texture.?);
        if (prepared and !traced) lights = self.lightUniforms(frame);
        sdl_c.SDL_PushGPUFragmentUniformData(command_buffer, 0, &lights, @sizeOf(LightUniforms));
        if (!traced) {
            var shadow_bindings: [scenes.SceneFrame.max_directional_lights]sdl_c.SDL_GPUTextureSamplerBinding = undefined;
            for (&shadow_bindings, self.shadow_maps) |*binding, map| binding.* = .{ .texture = map orelse self.blank_shadow, .sampler = self.shadow_sampler };
            sdl_c.SDL_BindGPUFragmentSamplers(pass, 1, &shadow_bindings, shadow_bindings.len);
        }
        const lit_pipeline = if (traced) self.traced_pipelines.?.lit else self.lit_pipeline;
        const blended_pipeline = if (traced) self.traced_pipelines.?.blended else self.blended_pipeline;
        const view_projection = Self.fittedProjection(frame.projection, step.rect, viewport).multiply(frame.view);
        for (frame.draws, meshes, textures, 0..) |shape, mesh, texture, index| {
            const entry = mesh orelse continue;
            sdl_c.SDL_BindGPUGraphicsPipeline(pass, if (index < frame.opaque_count) lit_pipeline else blended_pipeline);
            sdl_c.SDL_BindGPUVertexBuffers(pass, 0, &.{ .buffer = entry.vertex_buffer, .offset = 0 }, 1);
            sdl_c.SDL_BindGPUIndexBuffer(pass, &.{ .buffer = entry.index_buffer, .offset = 0 }, sdl_c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
            sdl_c.SDL_BindGPUFragmentSamplers(pass, 0, &.{ .texture = texture, .sampler = self.base_sampler }, 1);
            const vertex_uniforms = VertexUniforms{ .model = shape.world, .normal_matrix = shape.normal, .view_projection = view_projection };
            sdl_c.SDL_PushGPUVertexUniformData(command_buffer, 0, &vertex_uniforms, @sizeOf(VertexUniforms));
            const base = scenes.SceneFrame.linear(shape.material.base_color);
            const surface = SurfaceUniforms{
                .base_color = .{ base.x, base.y, base.z, std.math.clamp(shape.material.base_color.a, 0, 1) },
                .surface = .{ @max(shape.material.specular, 0), shape.material.shininess, if (shape.receives_shadows) 1 else 0, if (traced) Self.reflectivityOf(shape.material) else 0 },
            };
            sdl_c.SDL_PushGPUFragmentUniformData(command_buffer, 1, &surface, @sizeOf(SurfaceUniforms));
            sdl_c.SDL_DrawGPUIndexedPrimitives(pass, entry.index_count, 1, 0, 0, 0);
        }
        return true;
    }

    /// The lit and blended pipelines over the traced fragment shader, made as
    /// the lit and blended ones are.
    ///
    /// - `device`: the GPU device.
    /// - `lit_info`: the lit pipeline's create info, its color target replaced here.
    /// - `target_format`: the format of the texture scenes are drawn into.
    /// - `traced_fragment`: the traced fragment shader.
    /// - Returns: the pipelines, or null when the device cannot make them (logged).
    fn makeTracedPipelines(device: *sdl_c.SDL_GPUDevice, lit_info: sdl_c.SDL_GPUGraphicsPipelineCreateInfo, target_format: sdl_c.SDL_GPUTextureFormat, traced_fragment: *sdl_c.SDL_GPUShader) ?TracedPipelines {
        var create_info = lit_info;
        create_info.fragment_shader = traced_fragment;
        const lit_target = sdl_c.SDL_GPUColorTargetDescription{ .format = target_format, .blend_state = .{} };
        create_info.target_info.color_target_descriptions = &lit_target;
        const lit = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse {
            log.warn("scenes draw rasterized: no traced lit pipeline [{s}]", .{sdl_c.SDL_GetError()});
            return null;
        };
        // Depth tested but not written, as `blended_pipeline`.
        const blended_target = sdl_c.SDL_GPUColorTargetDescription{ .format = target_format, .blend_state = over_blend };
        create_info.target_info.color_target_descriptions = &blended_target;
        create_info.depth_stencil_state.enable_depth_write = false;
        const blended = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse {
            log.warn("scenes draw rasterized: no traced blended pipeline [{s}]", .{sdl_c.SDL_GetError()});
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, lit);
            return null;
        };
        const pipelines = TracedPipelines{ .lit = lit, .blended = blended };
        return pipelines;
    }

    /// Frees the traced pipelines.
    ///
    /// - `device`: the GPU device.
    /// - `pipelines`: the pipelines.
    fn releaseTracedPipelines(device: *sdl_c.SDL_GPUDevice, pipelines: TracedPipelines) void {
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, pipelines.lit);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, pipelines.blended);
    }

    /// Builds a frame's acceleration structures when its scene asks for
    /// ray tracing, this renderer traces rays, and something needs a ray: a
    /// directional light casting a shadow, a point light casting one, or a
    /// reflective shape. The lights' uniforms then carry what the traced
    /// shader reads: a shadowing directional light names its own index (one
    /// with none stays -1) and its cone's width, a point light its source's
    /// radius (-1 for one casting none).
    ///
    /// - `self`: the renderer.
    /// - `arena`: the frame's arena, for the shapes' list.
    /// - `command_buffer`: the command buffer, outside any pass, the meshes uploaded on it.
    /// - `scene`: the scene.
    /// - `frame`: the frame.
    /// - `meshes`: each shape's mesh, null for one that could not be had.
    /// - `textures`: each shape's texture (the white texel for none).
    /// - `lights`: the lights' uniforms.
    /// - Returns: true when the frame's shadows are traced; false draws them from shadow maps.
    fn prepareTraced(self: *Self, arena: std.mem.Allocator, command_buffer: *sdl_c.SDL_GPUCommandBuffer, scene: *const scenes.Scene, frame: scenes.SceneFrame, meshes: []const ?MeshEntry, textures: []const *sdl_c.SDL_GPUTexture, lights: *LightUniforms) bool {
        if (scene.lighting_technique != .rayTraced) return false;
        const ray_tracer = if (self.ray_tracer) |*tracer| tracer else return false;
        var needs_rays = false;
        for (frame.directional_lights) |light| needs_rays = needs_rays or light.shadow != null;
        for (frame.point_lights) |light| needs_rays = needs_rays or light.casts_shadows;
        for (frame.draws) |shape| needs_rays = needs_rays or Self.reflectivityOf(shape.material) > 0;
        if (!needs_rays) return false;
        var shapes: std.ArrayList(mod.SceneRayShape) = .empty;
        for (frame.draws[0..frame.opaque_count], meshes[0..frame.opaque_count], textures[0..frame.opaque_count]) |shape, mesh, texture| {
            const entry = mesh orelse continue;
            shapes.append(arena, .{
                .key = entry.key,
                .geometry = shape.geometry,
                .vertex_buffer = entry.vertex_buffer,
                .index_buffer = entry.index_buffer,
                .index_count = entry.index_count,
                .world = shape.world,
                .normal = shape.normal,
                .material = shape.material,
                .texture = if (shape.material.texture != null) texture else null,
                .casts_shadows = shape.casts_shadows,
            }) catch |err| {
                log.warn("scene not ray traced: {s}", .{@errorName(err)});
                return false;
            };
        }
        if (!ray_tracer.prepare(arena, command_buffer, shapes.items)) return false;
        for (frame.directional_lights, 0..) |light, index| {
            if (light.shadow != null) lights.directional_direction[index][3] = @floatFromInt(index);
            lights.directional_color[index][3] = @tan(light.angular_radius);
        }
        for (frame.point_lights, 0..) |light, index| {
            lights.point_color[index][3] = if (light.casts_shadows) light.radius else -1;
        }
        return true;
    }

    /// How much a surface reflects, 0 to 1; 0 for a reflectivity that is not
    /// a number (`clamp` would make NaN 1, a mirror).
    ///
    /// - `material`: the surface.
    /// - Returns: the reflectivity.
    fn reflectivityOf(material: scenes.SceneMaterial) f32 {
        return if (material.reflectivity > 0) @min(material.reflectivity, 1) else 0;
    }

    /// What a reflection that meets nothing shows: the scene's background,
    /// else its ambient light.
    ///
    /// - `scene`: the scene.
    /// - `frame`: the frame.
    /// - Returns: the color, linear.
    fn skyOf(scene: *const scenes.Scene, frame: scenes.SceneFrame) scenes.Vec3 {
        if (scene.background) |background| return scenes.SceneFrame.linear(background);
        return frame.ambient;
    }

    /// The first of `formats` the device takes for a 2D texture of `usage`.
    ///
    /// - `device`: the GPU device.
    /// - `formats`: the formats, the preferred first.
    /// - `usage`: what the texture is used for.
    /// - Returns: the format, or null when it takes none.
    fn firstSupported(device: *sdl_c.SDL_GPUDevice, formats: []const sdl_c.SDL_GPUTextureFormat, usage: sdl_c.SDL_GPUTextureUsageFlags) ?sdl_c.SDL_GPUTextureFormat {
        for (formats) |format| {
            if (sdl_c.SDL_GPUTextureSupportsFormat(device, format, sdl_c.SDL_GPU_TEXTURETYPE_2D, usage)) return format;
        }
        return null;
    }

    /// The part of the target a step draws on: its rect cut to its clip and
    /// to the target, in whole pixels.
    ///
    /// - `step`: the scene step.
    /// - `target_width`: the target's width.
    /// - `target_height`: the target's height.
    /// - Returns: the scissor, or null when nothing of it shows.
    fn scissorOf(step: renderer.SceneStep, target_width: u32, target_height: u32) ?sdl_c.SDL_Rect {
        if (!(step.rect[2] > 0 and step.rect[3] > 0)) return null;
        const left = @max(@max(step.rect[0], step.clip[0]), 0);
        const top = @max(@max(step.rect[1], step.clip[1]), 0);
        const right = @min(@min(step.rect[0] + step.rect[2], step.clip[0] + step.clip[2]), @as(f32, @floatFromInt(target_width)));
        const bottom = @min(@min(step.rect[1] + step.rect[3], step.clip[1] + step.clip[3]), @as(f32, @floatFromInt(target_height)));
        if (right <= left or bottom <= top) return null;
        const x: c_int = @intFromFloat(@floor(left));
        const y: c_int = @intFromFloat(@floor(top));
        return .{ .x = x, .y = y, .w = @as(c_int, @intFromFloat(@ceil(right))) - x, .h = @as(c_int, @intFromFloat(@ceil(bottom))) - y };
    }

    /// A projection for the whole rect, remapped to draw through a viewport
    /// that covers only part of it: clip space scaled and moved so each point
    /// lands on the pixel the whole rect's viewport would put it on.
    ///
    /// - `projection`: the projection for the whole rect.
    /// - `rect`: the whole rect (x, y, width, height), in pixels.
    /// - `viewport`: the part drawn through (x, y, width, height), in pixels.
    /// - Returns: the remapped projection.
    fn fittedProjection(projection: scenes.Mat4, rect: [4]f32, viewport: [4]f32) scenes.Mat4 {
        // Pixel x of an NDC x in the rect: rect.x + (ndc + 1) / 2 × rect.width;
        // the viewport's NDC of that pixel: (pixel - viewport.x) / viewport.width × 2 - 1.
        // Y runs down in pixels and up in NDC.
        const scale_x = rect[2] / viewport[2];
        const scale_y = rect[3] / viewport[3];
        const offset_x = (2 * (rect[0] - viewport[0]) + rect[2]) / viewport[2] - 1;
        const offset_y = 1 - (2 * (rect[1] - viewport[1]) + rect[3]) / viewport[3];
        const remap = scenes.Mat4{ .columns = .{
            .{ .x = scale_x },
            .{ .y = scale_y },
            .{ .z = 1 },
            .{ .x = offset_x, .y = offset_y, .w = 1 },
        } };
        return remap.multiply(projection);
    }

    /// The fragment shader's lights for a frame (shadow maps assigned to
    /// lights in order, their projections set as `drawShadows` draws them).
    ///
    /// - `self`: the renderer.
    /// - `frame`: the frame.
    /// - Returns: the uniforms.
    fn lightUniforms(self: *const Self, frame: scenes.SceneFrame) LightUniforms {
        var lights = std.mem.zeroes(LightUniforms);
        lights.eye = .{ frame.eye.x, frame.eye.y, frame.eye.z, @floatFromInt(frame.directional_lights.len) };
        lights.ambient = .{ frame.ambient.x, frame.ambient.y, frame.ambient.z, @floatFromInt(frame.point_lights.len) };
        for (frame.directional_lights, 0..) |light, index| {
            lights.directional_direction[index] = .{ light.direction.x, light.direction.y, light.direction.z, -1 };
            lights.directional_color[index] = .{ light.color.x, light.color.y, light.color.z, 0 };
            lights.shadow[index] = scenes.Mat4.identity;
        }
        for (frame.point_lights, 0..) |light, index| {
            lights.point_position[index] = .{ light.position.x, light.position.y, light.position.z, light.range };
            lights.point_color[index] = .{ light.color.x, light.color.y, light.color.z, 0 };
        }
        lights.shadow_parameters = .{ 1.0 / @as(f32, shadow_map_side), shadow_bias, if (self.encode_srgb) 1 else 0, 0 };
        return lights;
    }

    /// Draws the shadow maps: for each directional light that casts a shadow
    /// this frame, the depth of every opaque shape that casts one, seen
    /// along the light. A light whose map cannot be had casts none.
    ///
    /// - `self`: the renderer.
    /// - `command_buffer`: the command buffer, outside any pass.
    /// - `frame`: the frame.
    /// - `meshes`: each shape's mesh, null for one that could not be had.
    /// - `lights`: the lights' uniforms, given each map and projection drawn.
    fn drawShadows(self: *Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer, frame: scenes.SceneFrame, meshes: []const ?MeshEntry, lights: *LightUniforms) void {
        for (frame.directional_lights, 0..) |light, index| {
            const projection = light.shadow orelse continue;
            const map = self.shadowMap(index) orelse continue;
            const depth_target = sdl_c.SDL_GPUDepthStencilTargetInfo{
                .texture = map,
                .clear_depth = 1,
                .load_op = sdl_c.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl_c.SDL_GPU_STOREOP_STORE,
                .stencil_load_op = sdl_c.SDL_GPU_LOADOP_DONT_CARE,
                .stencil_store_op = sdl_c.SDL_GPU_STOREOP_DONT_CARE,
                .cycle = true,
            };
            const pass = sdl_c.SDL_BeginGPURenderPass(command_buffer, null, 0, &depth_target) orelse continue;
            sdl_c.SDL_BindGPUGraphicsPipeline(pass, self.shadow_pipeline);
            for (frame.draws[0..frame.opaque_count], meshes[0..frame.opaque_count]) |shape, mesh| {
                if (!shape.casts_shadows) continue;
                const entry = mesh orelse continue;
                sdl_c.SDL_BindGPUVertexBuffers(pass, 0, &.{ .buffer = entry.vertex_buffer, .offset = 0 }, 1);
                sdl_c.SDL_BindGPUIndexBuffer(pass, &.{ .buffer = entry.index_buffer, .offset = 0 }, sdl_c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
                const uniforms = ShadowUniforms{ .model = shape.world, .light = projection };
                sdl_c.SDL_PushGPUVertexUniformData(command_buffer, 0, &uniforms, @sizeOf(ShadowUniforms));
                sdl_c.SDL_DrawGPUIndexedPrimitives(pass, entry.index_count, 1, 0, 0, 0);
            }
            sdl_c.SDL_EndGPURenderPass(pass);
            lights.directional_direction[index][3] = @floatFromInt(index);
            lights.shadow[index] = projection;
        }
    }

    /// Finds or uploads each shape's mesh and texture, in one copy pass,
    /// then makes the new textures' mipmaps.
    ///
    /// - `self`: the renderer.
    /// - `arena`: the frame's arena, for the geometries' data.
    /// - `command_buffer`: the command buffer, outside any pass.
    /// - `frame`: the frame.
    /// - `meshes`: filled with each shape's mesh, null for one that cannot be drawn.
    /// - `textures`: filled with each shape's texture (the white texel for none).
    /// - Returns: false when the copy pass could not begin.
    fn prepare(self: *Self, arena: std.mem.Allocator, command_buffer: *sdl_c.SDL_GPUCommandBuffer, frame: scenes.SceneFrame, meshes: []?MeshEntry, textures: []*sdl_c.SDL_GPUTexture) bool {
        var copy: ?*sdl_c.SDL_GPUCopyPass = null;
        var made: std.ArrayList(*sdl_c.SDL_GPUTexture) = .empty;
        for (frame.draws, meshes, textures) |shape, *mesh, *texture| {
            mesh.* = self.findMesh(shape.geometry.key()) orelse made_mesh: {
                if (copy == null) copy = sdl_c.SDL_BeginGPUCopyPass(command_buffer) orelse return false;
                break :made_mesh self.uploadMesh(arena, copy.?, shape.geometry);
            };
            texture.* = self.white_texture.?;
            const material_texture = shape.material.texture orelse continue;
            texture.* = self.findTexture(material_texture.key()) orelse made_texture: {
                if (copy == null) copy = sdl_c.SDL_BeginGPUCopyPass(command_buffer) orelse return false;
                const uploaded = self.uploadTexture(copy.?, material_texture) orelse break :made_texture self.white_texture.?;
                made.append(arena, uploaded) catch |err| log.warn("texture's mipmaps not made: {s}", .{@errorName(err)});
                break :made_texture uploaded;
            };
        }
        if (copy) |pass| sdl_c.SDL_EndGPUCopyPass(pass);
        for (made.items) |texture| sdl_c.SDL_GenerateMipmapsForGPUTexture(command_buffer, texture);
        return true;
    }

    /// A geometry's mesh on the GPU, marked used this frame.
    ///
    /// - `self`: the renderer.
    /// - `key`: the geometry's key.
    /// - Returns: the mesh, or null when it has none yet.
    fn findMesh(self: *Self, key: u64) ?MeshEntry {
        for (self.meshes.items) |*entry| {
            if (entry.key != key) continue;
            entry.used_in = self.frame_counter;
            return entry.*;
        }
        return null;
    }

    /// A texture on the GPU, marked used this frame.
    ///
    /// - `self`: the renderer.
    /// - `key`: the texture's key.
    /// - Returns: the texture, or null when it has none yet.
    fn findTexture(self: *Self, key: u64) ?*sdl_c.SDL_GPUTexture {
        for (self.textures.items) |*entry| {
            if (entry.key != key) continue;
            entry.used_in = self.frame_counter;
            return entry.texture;
        }
        return null;
    }

    /// Builds a geometry's vertices and indices and uploads them.
    ///
    /// - `self`: the renderer.
    /// - `arena`: the frame's arena, for the built data.
    /// - `copy`: the open copy pass.
    /// - `geometry`: the geometry.
    /// - Returns: the mesh, or null when it cannot be drawn (an invalid mesh)
    ///   or uploaded (logged).
    fn uploadMesh(self: *Self, arena: std.mem.Allocator, copy: *sdl_c.SDL_GPUCopyPass, geometry: scenes.SceneGeometry) ?MeshEntry {
        const data = geometry.build(arena) catch |err| {
            log.warn("geometry not drawn: {s}", .{@errorName(err)});
            return null;
        };
        const vertex_bytes = std.mem.sliceAsBytes(data.vertices);
        const index_bytes = std.mem.sliceAsBytes(data.indices);
        const vertex_buffer = self.uploadBuffer(copy, sdl_c.SDL_GPU_BUFFERUSAGE_VERTEX, vertex_bytes) orelse return null;
        const index_buffer = self.uploadBuffer(copy, sdl_c.SDL_GPU_BUFFERUSAGE_INDEX, index_bytes) orelse {
            sdl_c.SDL_ReleaseGPUBuffer(self.device, vertex_buffer);
            return null;
        };
        const entry = MeshEntry{ .key = geometry.key(), .vertex_buffer = vertex_buffer, .index_buffer = index_buffer, .index_count = @intCast(data.indices.len), .used_in = self.frame_counter };
        self.meshes.append(self.allocator, entry) catch |err| {
            log.warn("mesh not kept: {s}", .{@errorName(err)});
            Self.releaseMesh(self.device, entry);
            return null;
        };
        return entry;
    }

    /// A buffer filled with bytes through a transfer buffer released once
    /// the upload is recorded (SDL keeps it until the command buffer is done).
    ///
    /// - `self`: the renderer.
    /// - `copy`: the open copy pass.
    /// - `usage`: what the buffer is for.
    /// - `bytes`: what it holds.
    /// - Returns: the buffer, or null when it could not be made (logged).
    fn uploadBuffer(self: *Self, copy: *sdl_c.SDL_GPUCopyPass, usage: sdl_c.SDL_GPUBufferUsageFlags, bytes: []const u8) ?*sdl_c.SDL_GPUBuffer {
        const size: u32 = std.math.cast(u32, bytes.len) orelse return null;
        const buffer = sdl_c.SDL_CreateGPUBuffer(self.device, &.{ .usage = usage, .size = size }) orelse {
            log.warn("scene buffer not made [{s}]", .{sdl_c.SDL_GetError()});
            return null;
        };
        if (!self.fillTransfer(copy, bytes, .{ .buffer = buffer })) {
            sdl_c.SDL_ReleaseGPUBuffer(self.device, buffer);
            return null;
        }
        return buffer;
    }

    /// Uploads a material's texture as sRGB, with room for its mipmaps.
    ///
    /// - `self`: the renderer.
    /// - `copy`: the open copy pass.
    /// - `texture`: the texture.
    /// - Returns: the GPU texture, or null when it has no pixels to read or
    ///   could not be made (logged).
    fn uploadTexture(self: *Self, copy: *sdl_c.SDL_GPUCopyPass, texture: scenes.SceneTexture) ?*sdl_c.SDL_GPUTexture {
        const image = texture.image;
        if (image.width == 0 or image.height == 0 or !image.isWhole()) return null;
        const levels: u32 = std.math.log2_int(u32, @max(image.width, image.height)) + 1;
        const made = sdl_c.SDL_CreateGPUTexture(self.device, &.{
            .type = sdl_c.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl_c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
            .usage = sdl_c.SDL_GPU_TEXTUREUSAGE_SAMPLER | sdl_c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
            .width = image.width,
            .height = image.height,
            .layer_count_or_depth = 1,
            .num_levels = levels,
        }) orelse {
            log.warn("scene texture not made [{s}]", .{sdl_c.SDL_GetError()});
            return null;
        };
        const bytes = image.pixels[0..@intCast(image.byteLength())];
        if (!self.fillTransfer(copy, bytes, .{ .texture = .{ .texture = made, .width = image.width, .height = image.height } })) {
            sdl_c.SDL_ReleaseGPUTexture(self.device, made);
            return null;
        }
        self.textures.append(self.allocator, .{ .key = texture.key(), .texture = made, .used_in = self.frame_counter }) catch |err| {
            log.warn("scene texture not kept: {s}", .{@errorName(err)});
            sdl_c.SDL_ReleaseGPUTexture(self.device, made);
            return null;
        };
        return made;
    }

    /// Copies bytes into a buffer or a texture's first level through a
    /// transfer buffer of their size.
    ///
    /// - `self`: the renderer.
    /// - `copy`: the open copy pass.
    /// - `bytes`: what is copied.
    /// - `destination`: where it goes.
    /// - Returns: false when the transfer buffer could not be made or mapped (logged).
    fn fillTransfer(self: *Self, copy: *sdl_c.SDL_GPUCopyPass, bytes: []const u8, destination: UploadDestination) bool {
        const size: u32 = std.math.cast(u32, bytes.len) orelse return false;
        const transfer = sdl_c.SDL_CreateGPUTransferBuffer(self.device, &.{ .usage = sdl_c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = size }) orelse {
            log.warn("scene upload not made [{s}]", .{sdl_c.SDL_GetError()});
            return false;
        };
        defer sdl_c.SDL_ReleaseGPUTransferBuffer(self.device, transfer);
        const mapped: [*]u8 = @ptrCast(sdl_c.SDL_MapGPUTransferBuffer(self.device, transfer, false) orelse {
            log.warn("scene upload not mapped [{s}]", .{sdl_c.SDL_GetError()});
            return false;
        });
        @memcpy(mapped[0..bytes.len], bytes);
        sdl_c.SDL_UnmapGPUTransferBuffer(self.device, transfer);
        switch (destination) {
            .buffer => |buffer| sdl_c.SDL_UploadToGPUBuffer(copy, &.{ .transfer_buffer = transfer, .offset = 0 }, &.{ .buffer = buffer, .offset = 0, .size = size }, false),
            .texture => |texture| sdl_c.SDL_UploadToGPUTexture(
                copy,
                &.{ .transfer_buffer = transfer, .offset = 0, .pixels_per_row = texture.width, .rows_per_layer = texture.height },
                &.{ .texture = texture.texture, .w = texture.width, .h = texture.height, .d = 1 },
                false,
            ),
        }
        return true;
    }

    /// Makes the white texel and the blank shadow texel the first time a
    /// scene draws: white uploaded, the depth texel cleared to 1.
    ///
    /// - `self`: the renderer.
    /// - `command_buffer`: the command buffer, outside any pass.
    /// - Returns: false when they could not be made (logged).
    fn ensureDefaults(self: *Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer) bool {
        if (self.defaults_ready) return true;
        if (self.white_texture == null) self.white_texture = sdl_c.SDL_CreateGPUTexture(self.device, &.{
            .type = sdl_c.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl_c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
            .usage = sdl_c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            .width = 1,
            .height = 1,
            .layer_count_or_depth = 1,
            .num_levels = 1,
        });
        if (self.blank_shadow == null) self.blank_shadow = self.makeDepthTexture(1, 1, self.shadow_format, true);
        const white = self.white_texture orelse {
            log.warn("scene's white texel not made [{s}]", .{sdl_c.SDL_GetError()});
            return false;
        };
        const blank = self.blank_shadow orelse return false;
        const copy = sdl_c.SDL_BeginGPUCopyPass(command_buffer) orelse return false;
        const filled = self.fillTransfer(copy, &.{ 255, 255, 255, 255 }, .{ .texture = .{ .texture = white, .width = 1, .height = 1 } });
        sdl_c.SDL_EndGPUCopyPass(copy);
        if (!filled) return false;
        const depth_target = sdl_c.SDL_GPUDepthStencilTargetInfo{
            .texture = blank,
            .clear_depth = 1,
            .load_op = sdl_c.SDL_GPU_LOADOP_CLEAR,
            .store_op = sdl_c.SDL_GPU_STOREOP_STORE,
            .stencil_load_op = sdl_c.SDL_GPU_LOADOP_DONT_CARE,
            .stencil_store_op = sdl_c.SDL_GPU_STOREOP_DONT_CARE,
        };
        const pass = sdl_c.SDL_BeginGPURenderPass(command_buffer, null, 0, &depth_target) orelse return false;
        sdl_c.SDL_EndGPURenderPass(pass);
        self.defaults_ready = true;
        return true;
    }

    /// Makes sure the depth buffer is the target's size.
    ///
    /// - `self`: the renderer.
    /// - `width`: the target's width.
    /// - `height`: the target's height.
    /// - Returns: false when it could not be made (logged).
    fn ensureDepth(self: *Self, width: u32, height: u32) bool {
        if (self.depth_texture != null and self.depth_width == width and self.depth_height == height) return true;
        if (self.depth_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(self.device, texture);
        self.depth_texture = self.makeDepthTexture(width, height, self.depth_format, false);
        self.depth_width = width;
        self.depth_height = height;
        return self.depth_texture != null;
    }

    /// A light's shadow map, made on first need.
    ///
    /// - `self`: the renderer.
    /// - `index`: the light's place among the frame's directional lights.
    /// - Returns: the map, or null when it could not be made (logged).
    fn shadowMap(self: *Self, index: usize) ?*sdl_c.SDL_GPUTexture {
        if (self.shadow_maps[index] == null) self.shadow_maps[index] = self.makeDepthTexture(shadow_map_side, shadow_map_side, self.shadow_format, true);
        return self.shadow_maps[index];
    }

    /// A depth texture.
    ///
    /// - `self`: the renderer.
    /// - `width`: its width.
    /// - `height`: its height.
    /// - `format`: its depth format.
    /// - `sampled`: whether shaders sample it too (a shadow map).
    /// - Returns: the texture, or null when it could not be made (logged).
    fn makeDepthTexture(self: *Self, width: u32, height: u32, format: sdl_c.SDL_GPUTextureFormat, sampled: bool) ?*sdl_c.SDL_GPUTexture {
        const usage = sdl_c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET | (if (sampled) sdl_c.SDL_GPU_TEXTUREUSAGE_SAMPLER else 0);
        return sdl_c.SDL_CreateGPUTexture(self.device, &.{
            .type = sdl_c.SDL_GPU_TEXTURETYPE_2D,
            .format = format,
            .usage = usage,
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
        }) orelse {
            log.warn("scene depth texture not made [{s}]", .{sdl_c.SDL_GetError()});
            return null;
        };
    }

    /// Frees the depth buffer and the shadow maps (made again on need).
    ///
    /// - `self`: the renderer.
    fn releaseTargets(self: *Self) void {
        if (self.depth_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(self.device, texture);
        self.depth_texture = null;
        self.depth_width = 0;
        self.depth_height = 0;
        for (&self.shadow_maps) |*map| {
            if (map.*) |texture| sdl_c.SDL_ReleaseGPUTexture(self.device, texture);
            map.* = null;
        }
    }

    /// Frees a mesh's buffers.
    ///
    /// - `device`: the GPU device.
    /// - `entry`: the mesh.
    fn releaseMesh(device: *sdl_c.SDL_GPUDevice, entry: MeshEntry) void {
        sdl_c.SDL_ReleaseGPUBuffer(device, entry.vertex_buffer);
        sdl_c.SDL_ReleaseGPUBuffer(device, entry.index_buffer);
    }
};

/// A texture's first level as an upload's destination.
const TextureDestination = struct {
    const Self = @This();

    /// The texture.
    texture: *sdl_c.SDL_GPUTexture,
    /// Its width.
    width: u32,
    /// Its height.
    height: u32,
};

/// Where an upload goes.
const UploadDestination = union(enum) {
    const Self = @This();

    /// A buffer, from its start.
    buffer: *sdl_c.SDL_GPUBuffer,
    /// A texture's first level.
    texture: TextureDestination,
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the light uniforms match the shaders' std140 layout" {
    try std.testing.expectEqual(@as(usize, 688), @sizeOf(LightUniforms));
    try std.testing.expectEqual(@as(usize, 192), @sizeOf(VertexUniforms));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(scenes.SceneVertex));
}

test "a scene's scissor is its rect cut to its clip and the target" {
    const marker: u8 = 0;
    const step = renderer.SceneStep{ .rect = .{ 10.5, 20, 100, 50 }, .clip = .{ 0, 0, 60, 1000 }, .scene = &marker, .placeholder = .{ .first = 0, .count = 0 } };
    const scissor = SceneRenderer.scissorOf(step, 800, 600).?;
    try std.testing.expectEqual(@as(c_int, 10), scissor.x);
    try std.testing.expectEqual(@as(c_int, 20), scissor.y);
    try std.testing.expectEqual(@as(c_int, 50), scissor.w);
    try std.testing.expectEqual(@as(c_int, 50), scissor.h);
    var hidden = step;
    hidden.clip = .{ 500, 0, 10, 10 };
    try std.testing.expectEqual(null, SceneRenderer.scissorOf(hidden, 800, 600));
}

/// A small 3D scene drawn offscreen through the real GPU pipeline, for the
/// tests below: a frame, the scene's view of it, and its pixels.
const TestDraw = struct {
    const Self = @This();

    /// The image's side, in pixels.
    const side = 64;

    /// The pixels, RGBA8, `side` × `side`.
    pixels: []u8,

    /// Draws a scene filling the image over a black ground, then a white
    /// square in its top-left corner after it (UI on top).
    ///
    /// - `gpu`: the offscreen GPU.
    /// - `arena`: the frame's arena.
    /// - `scene`: the scene.
    /// - Returns: the drawing, or null when the GPU drew nothing.
    fn render(gpu: *mod.Gpu, arena: std.mem.Allocator, scene: *const scenes.Scene) ?Self {
        const whole = renderer.Rect{ .x = 0, .y = 0, .width = side, .height = side };
        const commands = [_]renderer.DrawCommand{
            .{ .fillRoundedRect = .{ .rect = whole, .color = renderer.Color.black } },
            .{ .scene = .{ .rect = whole, .scene = scene, .ground = renderer.Color.black, .ink = renderer.Color.black } },
            .{ .fillRoundedRect = .{ .rect = .{ .x = 0, .y = 0, .width = 4, .height = 4 }, .color = renderer.Color.white } },
        };
        const pixels = gpu.renderToRgba(arena, &commands, renderer.Color.black, side, side) orelse return null;
        const self = Self{ .pixels = pixels };
        return self;
    }

    /// Fills a scene with a box over a floor, lit from straight above by a
    /// directional light that casts its shadow, seen from above and in front.
    ///
    /// - `scene`: an empty scene.
    /// - Returns: the light's node; propagates allocation failure.
    fn shadowedBox(scene: *scenes.Scene) !scenes.SceneNodeId {
        scene.ambient_intensity = 0.1;
        var camera = scenes.SceneNode{ .camera = .{}, .transform = .{ .position = scenes.Vec3.init(0, 3, 5) } };
        camera.lookAt(scenes.Vec3.zero, scenes.Vec3.up);
        scene.point_of_view = try scene.addChild(scene.root(), camera);
        const down = scenes.Quaternion.fromAxisAngle(scenes.Vec3.init(1, 0, 0), -std.math.pi / 2.0);
        _ = try scene.addChild(scene.root(), .{ .geometry = .{ .plane = .{ .width = 6, .height = 6 } }, .transform = .{ .position = scenes.Vec3.init(0, -1, 0), .rotation = down }, .material = .{ .specular = 0 } });
        _ = try scene.addChild(scene.root(), .{ .geometry = .{ .box = .{} }, .material = .{ .specular = 0 } });
        return scene.addChild(scene.root(), .{ .light = .{}, .transform = .{ .rotation = down } });
    }

    /// The pixel a point of the scene lands on, through its camera.
    ///
    /// - `self`: the drawing.
    /// - `arena`: for gathering the scene's frame.
    /// - `scene`: the scene.
    /// - `point`: the point, in the scene's space.
    /// - Returns: its pixel's red, green, blue and alpha.
    fn at(self: *const Self, arena: std.mem.Allocator, scene: *const scenes.Scene, point: scenes.Vec3) ![4]u8 {
        const frame = try scenes.SceneFrame.gather(arena, scene, 1);
        const ndc = frame.projection.multiply(frame.view).transformPoint(point);
        const x: usize = @intFromFloat(std.math.clamp((ndc.x * 0.5 + 0.5) * side, 0, side - 1));
        const y: usize = @intFromFloat(std.math.clamp((0.5 - ndc.y * 0.5) * side, 0, side - 1));
        return self.pixels[(y * side + x) * 4 ..][0..4].*;
    }
};

test "a lit box draws its color where it is, the UI after it on top, the ground beside it" {
    if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
    defer sdl_c.SDL_Quit();
    var gpu = mod.Gpu.init(std.testing.allocator, null) orelse return error.SkipZigTest;
    defer gpu.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    scene.ambient_intensity = 0;
    _ = try scene.addChild(scene.root(), .{ .geometry = .{ .box = .{} }, .material = .{ .base_color = renderer.Color.red, .specular = 0 } });
    // A light along -Z meets the box's front face square on.
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .directional = .{ .casts_shadows = false } } } });
    const drawn = TestDraw.render(&gpu, arena.allocator(), &scene) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(drawn.pixels);
    const center = try drawn.at(arena.allocator(), &scene, scenes.Vec3.init(0, 0, 0.5));
    try std.testing.expect(center[0] >= 250 and center[1] <= 5 and center[2] <= 5);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, drawn.pixels[(1 * TestDraw.side + 1) * 4 ..][0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255 }, drawn.pixels[(TestDraw.side - 2) * 4 ..][0..4]);
}

test "a scene half off the target draws where its whole rect puts it" {
    if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
    defer sdl_c.SDL_Quit();
    var gpu = mod.Gpu.init(std.testing.allocator, null) orelse return error.SkipZigTest;
    defer gpu.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    scene.ambient_intensity = 0;
    _ = try scene.addChild(scene.root(), .{ .geometry = .{ .box = .{ .width = 0.5, .height = 0.5, .length = 0.5 } }, .material = .{ .base_color = renderer.Color.red, .specular = 0 } });
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .directional = .{ .casts_shadows = false } } } });
    // A rect twice the target's width, from 32 pixels off its left edge: its center is the target's.
    const rect = renderer.Rect{ .x = -32, .y = 0, .width = 128, .height = 64 };
    const commands = [_]renderer.DrawCommand{
        .{ .scene = .{ .rect = rect, .scene = &scene, .ground = renderer.Color.black, .ink = renderer.Color.black } },
    };
    const pixels = gpu.renderToRgba(arena.allocator(), &commands, renderer.Color.black, TestDraw.side, TestDraw.side) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(pixels);
    const center = pixels[(32 * TestDraw.side + 32) * 4 ..][0..4];
    try std.testing.expect(center[0] >= 250 and center[1] <= 5);
    // The box is small: the target's edges show the black ground.
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255 }, pixels[(32 * TestDraw.side + 1) * 4 ..][0..4]);
}

test "a texture is sampled, and a translucent pane blends over what is behind it" {
    if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
    defer sdl_c.SDL_Quit();
    var gpu = mod.Gpu.init(std.testing.allocator, null) orelse return error.SkipZigTest;
    defer gpu.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    scene.ambient_intensity = 0;
    const green_pixels = [_]u8{ 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255 };
    const green = renderer.Image{ .width = 2, .height = 2, .pixels = &green_pixels };
    _ = try scene.addChild(scene.root(), .{ .geometry = .{ .box = .{ .width = 2, .height = 2, .length = 0.1 } }, .material = .{ .texture = .{ .image = green }, .specular = 0 } });
    // A half-clear blue pane in front of the left half only.
    _ = try scene.addChild(scene.root(), .{
        .geometry = .{ .plane = .{ .width = 1, .height = 2 } },
        .material = .{ .base_color = renderer.Color.blue.withAlpha(0.5), .specular = 0 },
        .transform = .{ .position = scenes.Vec3.init(-0.5, 0, 1) },
    });
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .directional = .{ .casts_shadows = false } } } });
    const drawn = TestDraw.render(&gpu, arena.allocator(), &scene) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(drawn.pixels);
    const textured = try drawn.at(arena.allocator(), &scene, scenes.Vec3.init(0.5, 0, 0.05));
    try std.testing.expect(textured[1] >= 250 and textured[0] <= 5 and textured[2] <= 5);
    const behind_glass = try drawn.at(arena.allocator(), &scene, scenes.Vec3.init(-0.5, 0, 1));
    try std.testing.expect(behind_glass[1] > 100 and behind_glass[2] > 100 and behind_glass[0] <= 5);
}

test "a directional light's shadow darkens the floor under a box, the floor beside it lit" {
    if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
    defer sdl_c.SDL_Quit();
    var gpu = mod.Gpu.init(std.testing.allocator, null) orelse return error.SkipZigTest;
    defer gpu.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    _ = try TestDraw.shadowedBox(&scene);
    const drawn = TestDraw.render(&gpu, arena.allocator(), &scene) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(drawn.pixels);
    // Under the box's front edge (seen past its bottom) is in shadow; well to the side is lit.
    const shaded = try drawn.at(arena.allocator(), &scene, scenes.Vec3.init(0, -1, 0.3));
    const lit = try drawn.at(arena.allocator(), &scene, scenes.Vec3.init(1.8, -1, 0.3));
    try std.testing.expect(lit[0] > 200);
    try std.testing.expect(shaded[0] < 100);
}

test "a ray-traced shadow darkens the floor under a box, the floor beside it lit, and draws no shadow map" {
    if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
    defer sdl_c.SDL_Quit();
    var gpu = mod.Gpu.init(std.testing.allocator, null) orelse return error.SkipZigTest;
    defer gpu.deinit();
    if (!mod.SceneRayTracer.supported(gpu.device)) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    _ = try TestDraw.shadowedBox(&scene);
    scene.lighting_technique = .rayTraced;
    const drawn = TestDraw.render(&gpu, arena.allocator(), &scene) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(drawn.pixels);
    // Traced: the floor's and the box's structures built, no shadow map made.
    const scene_renderer = &gpu.scene_renderer.?;
    try std.testing.expect(scene_renderer.tracesRays());
    try std.testing.expectEqual(@as(usize, 2), scene_renderer.ray_tracer.?.primitives.items.len);
    try std.testing.expectEqual(null, scene_renderer.shadow_maps[0]);
    const shaded = try drawn.at(arena.allocator(), &scene, scenes.Vec3.init(0, -1, 0.3));
    const lit = try drawn.at(arena.allocator(), &scene, scenes.Vec3.init(1.8, -1, 0.3));
    try std.testing.expect(lit[0] > 200);
    try std.testing.expect(shaded[0] < 100);
}

/// An offscreen GPU that traces rays, for the ray tracing tests below.
const TracingGpu = struct {
    const Self = @This();

    /// The backend.
    gpu: mod.Gpu,
    /// The frame's arena.
    arena: std.heap.ArenaAllocator,

    /// Starts SDL's video and a GPU that traces rays.
    ///
    /// - Returns: the GPU, or `error.SkipZigTest` where there is none or it traces no rays.
    fn start() !Self {
        if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
        errdefer sdl_c.SDL_Quit();
        var gpu = mod.Gpu.init(std.testing.allocator, null) orelse return error.SkipZigTest;
        errdefer gpu.deinit();
        if (!mod.SceneRayTracer.supported(gpu.device)) return error.SkipZigTest;
        const self = Self{ .gpu = gpu, .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        return self;
    }

    /// Frees the GPU and stops SDL's video.
    ///
    /// - `self`: the GPU.
    fn stop(self: *Self) void {
        self.arena.deinit();
        self.gpu.deinit();
        sdl_c.SDL_Quit();
    }

    /// Fills a scene with a mirror facing the default camera and, behind
    /// the camera, a box it reflects, lit evenly by ambient light alone so
    /// the box shows its own colors.
    ///
    /// - `scene`: an empty scene.
    /// - `box_material`: the box's surface.
    /// - Returns: nothing; propagates allocation failure.
    fn mirrorAndBox(scene: *scenes.Scene, box_material: scenes.SceneMaterial) !void {
        scene.ambient_intensity = 1;
        _ = try scene.addChild(scene.root(), .{ .geometry = .{ .plane = .{ .width = 6, .height = 6 } }, .material = .{ .base_color = renderer.Color.black, .specular = 0, .reflectivity = 1 } });
        _ = try scene.addChild(scene.root(), .{ .geometry = .{ .box = .{ .width = 3, .height = 3, .length = 1 } }, .material = box_material, .transform = .{ .position = scenes.Vec3.init(0, 0, 8) } });
    }

    /// The red channel where a point of the scene lands, drawn ray traced.
    ///
    /// - `self`: the GPU.
    /// - `scene`: the scene, asked to be ray traced.
    /// - `point`: the point, in the scene's space.
    /// - Returns: its pixel's red; `error.SkipZigTest` when the GPU drew nothing.
    fn redAt(self: *Self, scene: *scenes.Scene, point: scenes.Vec3) !u8 {
        scene.lighting_technique = .rayTraced;
        const drawn = TestDraw.render(&self.gpu, self.arena.allocator(), scene) orelse return error.SkipZigTest;
        defer std.testing.allocator.free(drawn.pixels);
        return (try drawn.at(self.arena.allocator(), scene, point))[0];
    }
};

test "a ray-traced point light casts a shadow under a box, which shadow maps never cast" {
    var tracing = try TracingGpu.start();
    defer tracing.stop();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    const sun = try TestDraw.shadowedBox(&scene);
    // The sun turned off; a bright lamp straight over the box casts instead.
    scene.node(sun).?.hidden = true;
    _ = try scene.addChild(scene.root(), .{ .light = .{ .kind = .{ .point = .{ .range = 20, .casts_shadows = true } }, .intensity = 3 }, .transform = .{ .position = scenes.Vec3.init(0, 3, 0) } });
    const shaded = try tracing.redAt(&scene, scenes.Vec3.init(0, -1, 0.3));
    const lit = try tracing.redAt(&scene, scenes.Vec3.init(1.8, -1, 0.3));
    try std.testing.expect(lit > 150);
    // The ambient light alone (0.1, linear) is 89 in sRGB.
    try std.testing.expect(shaded < 100);
    scene.lighting_technique = .rasterized;
    const drawn = TestDraw.render(&tracing.gpu, tracing.arena.allocator(), &scene) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(drawn.pixels);
    try std.testing.expect((try drawn.at(tracing.arena.allocator(), &scene, scenes.Vec3.init(0, -1, 0.3)))[0] > 150);
}

test "a ray-traced shadow from a wide source darkens the floor just past its hard edge" {
    var tracing = try TracingGpu.start();
    defer tracing.stop();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    const sun = try TestDraw.shadowedBox(&scene);
    // Just past the box's side, which a hard shadow from straight above leaves lit.
    const past_edge = scenes.Vec3.init(0.6, -1, 0);
    const hard = try tracing.redAt(&scene, past_edge);
    scene.node(sun).?.light.?.kind.directional.angular_diameter = 30;
    const soft = try tracing.redAt(&scene, past_edge);
    try std.testing.expect(hard > 200);
    try std.testing.expect(soft < hard - 20);
}

test "a ray-traced mirror shows the box behind the camera, and the sky where nothing is" {
    var tracing = try TracingGpu.start();
    defer tracing.stop();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    scene.background = renderer.Color.blue;
    try TracingGpu.mirrorAndBox(&scene, .{ .base_color = renderer.Color.red, .specular = 0 });
    const mirrored = try tracing.redAt(&scene, scenes.Vec3.zero);
    try std.testing.expect(mirrored > 200);
    // The mirror's edge, seen at an angle, reflects past the box: the blue sky.
    scene.lighting_technique = .rayTraced;
    const drawn = TestDraw.render(&tracing.gpu, tracing.arena.allocator(), &scene) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(drawn.pixels);
    const edge = try drawn.at(tracing.arena.allocator(), &scene, scenes.Vec3.init(2.8, 2.8, 0));
    try std.testing.expect(edge[2] > 200 and edge[0] < 60);
}

test "a ray-traced mirror samples the reflected shape's texture, not its average" {
    var tracing = try TracingGpu.start();
    defer tracing.stop();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    // Red, green, red: the middle (where the mirror's center looks) is green,
    // the average mostly red.
    const strip = [_]u8{ 255, 0, 0, 255, 0, 255, 0, 255, 255, 0, 0, 255 };
    try TracingGpu.mirrorAndBox(&scene, .{ .texture = .{ .image = .{ .width = 3, .height = 1, .pixels = &strip } }, .specular = 0 });
    scene.lighting_technique = .rayTraced;
    const drawn = TestDraw.render(&tracing.gpu, tracing.arena.allocator(), &scene) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(drawn.pixels);
    // Sampled: green, a little red filtered in from the neighbours; the
    // average would be about 214 red, 156 green.
    const mirrored = try drawn.at(tracing.arena.allocator(), &scene, scenes.Vec3.zero);
    try std.testing.expect(mirrored[1] > 200 and mirrored[0] < 150);
}

test "a reflectivity is kept between 0 and 1, and one that is not a number reflects nothing" {
    try std.testing.expectEqual(@as(f32, 0.5), SceneRenderer.reflectivityOf(.{ .reflectivity = 0.5 }));
    try std.testing.expectEqual(@as(f32, 1), SceneRenderer.reflectivityOf(.{ .reflectivity = 3 }));
    try std.testing.expectEqual(@as(f32, 0), SceneRenderer.reflectivityOf(.{ .reflectivity = -1 }));
    try std.testing.expectEqual(@as(f32, 0), SceneRenderer.reflectivityOf(.{ .reflectivity = std.math.nan(f32) }));
}

test "two ray-traced scenes a frame keep one triangle buffer from frame to frame" {
    var tracing = try TracingGpu.start();
    defer tracing.stop();
    // The second scene places the first's meshes and a sphere.
    var first = try scenes.Scene.init(std.testing.allocator);
    defer first.deinit();
    _ = try TestDraw.shadowedBox(&first);
    first.lighting_technique = .rayTraced;
    var second = try scenes.Scene.init(std.testing.allocator);
    defer second.deinit();
    _ = try TestDraw.shadowedBox(&second);
    _ = try second.addChild(second.root(), .{ .geometry = .{ .sphere = .{ .radius = 0.3 } }, .transform = .{ .position = scenes.Vec3.init(1.5, -0.7, 0) } });
    second.lighting_technique = .rayTraced;
    const commands = [_]renderer.DrawCommand{
        .{ .scene = .{ .rect = .{ .x = 0, .y = 0, .width = 32, .height = 64 }, .scene = &first, .ground = renderer.Color.black, .ink = renderer.Color.black } },
        .{ .scene = .{ .rect = .{ .x = 32, .y = 0, .width = 32, .height = 64 }, .scene = &second, .ground = renderer.Color.black, .ink = renderer.Color.black } },
    };
    var buffers: [3]mod.Id = undefined;
    for (&buffers) |*buffer| {
        const pixels = tracing.gpu.renderToRgba(tracing.arena.allocator(), &commands, renderer.Color.black, TestDraw.side, TestDraw.side) orelse return error.SkipZigTest;
        std.testing.allocator.free(pixels);
        buffer.* = tracing.gpu.scene_renderer.?.ray_tracer.?.triangles;
    }
    try std.testing.expect(buffers[0] != null);
    try std.testing.expectEqual(buffers[0], buffers[1]);
    try std.testing.expectEqual(buffers[1], buffers[2]);
}

test "a scene drawn twice on its meshes' first frame is shadowed in both views" {
    var tracing = try TracingGpu.start();
    defer tracing.stop();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    _ = try TestDraw.shadowedBox(&scene);
    scene.lighting_technique = .rayTraced;
    // The first view builds the meshes' structures; the second places them
    // the same frame, before they were built if its instances went ahead.
    const half = TestDraw.side / 2;
    const commands = [_]renderer.DrawCommand{
        .{ .scene = .{ .rect = .{ .x = 0, .y = 0, .width = half, .height = TestDraw.side }, .scene = &scene, .ground = renderer.Color.black, .ink = renderer.Color.black } },
        .{ .scene = .{ .rect = .{ .x = half, .y = 0, .width = half, .height = TestDraw.side }, .scene = &scene, .ground = renderer.Color.black, .ink = renderer.Color.black } },
    };
    const pixels = tracing.gpu.renderToRgba(tracing.arena.allocator(), &commands, renderer.Color.black, TestDraw.side, TestDraw.side) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(pixels);
    const frame = try scenes.SceneFrame.gather(tracing.arena.allocator(), &scene, 0.5);
    for ([_]usize{ 0, half }) |left| {
        const shaded = frame.projection.multiply(frame.view).transformPoint(scenes.Vec3.init(0, -1, 0.3));
        const x = left + @as(usize, @intFromFloat(std.math.clamp((shaded.x * 0.5 + 0.5) * half, 0, half - 1)));
        const y: usize = @intFromFloat(std.math.clamp((0.5 - shaded.y * 0.5) * TestDraw.side, 0, TestDraw.side - 1));
        try std.testing.expect(pixels[(y * TestDraw.side + x) * 4] < 100);
    }
}

test "a ray-traced frame's structure and buffers are used again once that frame is done" {
    var tracing = try TracingGpu.start();
    defer tracing.stop();
    var scene = try scenes.Scene.init(std.testing.allocator);
    defer scene.deinit();
    _ = try TestDraw.shadowedBox(&scene);
    scene.lighting_technique = .rayTraced;
    var structures: [10]mod.Id = undefined;
    for (&structures) |*structure| {
        const drawn = TestDraw.render(&tracing.gpu, tracing.arena.allocator(), &scene) orelse return error.SkipZigTest;
        std.testing.allocator.free(drawn.pixels);
        structure.* = tracing.gpu.scene_renderer.?.ray_tracer.?.instances;
    }
    const ray_tracer = &tracing.gpu.scene_renderer.?.ray_tracer.?;
    // One set a frame in flight, each frame's structure the one a set held
    // `retire_frames` frames before, and nothing made anew to release.
    try std.testing.expectEqual(@as(usize, mod.SceneRayTracer.retire_frames), ray_tracer.sets.items.len);
    for (structures[mod.SceneRayTracer.retire_frames..], structures[0 .. structures.len - mod.SceneRayTracer.retire_frames]) |later, earlier| {
        try std.testing.expectEqual(earlier, later);
    }
    try std.testing.expectEqual(@as(usize, 0), ray_tracer.retired.items.len);
}

test "a projection fitted to part of the rect puts each point on the pixel the whole rect would" {
    const projection = scenes.Mat4.perspective(1, 2, 0.1, 100);
    const rect = [4]f32{ -100, 50, 400, 200 };
    const viewport = [4]f32{ 0, 50, 250, 120 };
    const fitted = SceneRenderer.fittedProjection(projection, rect, viewport);
    for ([_]scenes.Vec3{ scenes.Vec3.init(0.3, -0.2, -2), scenes.Vec3.init(-1, 0.5, -5) }) |point| {
        const whole = projection.transformPoint(point);
        const part = fitted.transformPoint(point);
        const whole_pixel = [2]f32{ rect[0] + (whole.x + 1) / 2 * rect[2], rect[1] + (1 - whole.y) / 2 * rect[3] };
        const part_pixel = [2]f32{ viewport[0] + (part.x + 1) / 2 * viewport[2], viewport[1] + (1 - part.y) / 2 * viewport[3] };
        try std.testing.expectApproxEqAbs(whole_pixel[0], part_pixel[0], 1e-3);
        try std.testing.expectApproxEqAbs(whole_pixel[1], part_pixel[1], 1e-3);
        try std.testing.expectApproxEqAbs(whole.z, part.z, 1e-6);
    }
}
