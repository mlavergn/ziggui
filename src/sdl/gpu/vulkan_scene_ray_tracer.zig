//! The Vulkan ray tracing behind a scene's `SceneLightingTechnique.rayTraced`
//! shadows and reflections, on SDL_GPU's own device and command buffers
//! (`VulkanInterop`), as `MetalSceneRayTracer` does it on Metal: a bottom-level
//! acceleration structure per mesh, built once from the mesh's vertices and
//! indices (uploaded to one buffer of their own, since SDL's lack the usage
//! a build reads, and retired once the build is recorded: a structure is
//! never refitted) and kept by its key with its triangles' vertex normals until it
//! goes unused, and each frame a top-level structure placing the opaque
//! shapes, which the traced fragment shader (`scene_traced.frag`) meets ray
//! queries against: shadow rays see only the shapes that cast shadows
//! (instance mask bit 0), reflection rays every opaque shape (bit 1), shaded
//! from each instance's surface and its triangle's normals and texture
//! coordinates. A frame's first `reflected_texture_count` textures are sampled
//! where a reflection meets them; past them a texture shows as its average.
//!
//! A frame builds its structures on SDL's command buffer between its passes
//! (`prepare`, no pass open), with a barrier between the meshes' builds and
//! the top-level one and another before the fragment shader reads it. SDL_GPU
//! binds no acceleration structure, so `bind` hands the top-level structure,
//! the surfaces and the triangles to the shader by GPU address in a uniform
//! block (slot 2) and the textures in the sampler slots after the base
//! texture. What a scene's frame needs for itself (its structure, scratch,
//! instance and surface buffers, and the scratch its meshes' builds share)
//! comes from a pool of `FrameSet`s, each used
//! again once the frame that used it is surely done (past any frame still in
//! flight); what a frame replaces is retired and freed as late.
//!
//! Only where SDL is built with `vulkan_interop.c` (`has_vulkan_interop`),
//! on SDL's Vulkan driver, on a device that interop made able to trace rays.

const std = @import("std");
const log = std.log.scoped(.ziggui_vulkan_scene_ray_tracer);
const mod = @import("../module.zig");
const renderer = @import("renderer");
const scenes = @import("scenes");
const sdl_c = @import("sdl_c");
const vulkan_c = @import("vulkan_c");

/// A mesh triangle's vertex normals and texture coordinates, as
/// `SceneHitTriangle` in the shader (std430).
const HitTriangle = extern struct {
    const Self = @This();

    /// The three vertices' normals, in the mesh's space (w unused).
    normals: [3][4]f32,
    /// The three vertices' texture coordinates.
    uvs: [3][2]f32,
    /// Padding to the shader's layout.
    unused: [2]f32 = .{ 0, 0 },
};

/// An instance's surface, as `SceneHitInstance` in the shader (std430).
const HitInstance = extern struct {
    const Self = @This();

    /// The normal matrix's first three columns (w unused).
    normal_matrix: [3][4]f32,
    /// The color, linear (its texture's average in when `texture` is -1), and the highlight's brightness in w.
    color: [4]f32,
    /// Where its mesh's triangles start among the laid-out ones.
    first_triangle: u32,
    /// The highlight's Blinn-Phong exponent.
    shininess: f32,
    /// Which reflected texture it samples, -1 for none.
    texture: i32,
    /// How much of its color it gives off itself (`SceneMaterial.emissionShare`).
    emission: f32 = 0,
};

/// What the traced shader reads at uniform slot 2, as `SceneTracing` (std140:
/// each address a `uvec2`, low word first).
const Tracing = extern struct {
    const Self = @This();

    /// The sky, linear (w unused).
    sky: [4]f32,
    /// The top-level acceleration structure's address.
    shapes: u64,
    /// The instances' surfaces' address.
    instances: u64,
    /// The laid-out triangles' address.
    triangles: u64,
    /// Padding to a whole vec4.
    unused: u64 = 0,
};

/// One instance of a top-level structure, as Vulkan's
/// `VkAccelerationStructureInstanceKHR` (whose bit fields translate-c cannot
/// carry): a row-major 3×4 transform, then the custom index and mask, the
/// binding table offset and flags, and the bottom-level structure's address.
const InstanceRecord = extern struct {
    const Self = @This();

    /// The transform's three rows.
    transform: [3][4]f32,
    /// The custom index (low 24 bits, unused) and the mask (high 8).
    custom_index_and_mask: u32,
    /// The binding table offset (low 24 bits, unused) and the flags (high 8).
    offset_and_flags: u32,
    /// The bottom-level structure's device address.
    structure: u64,
};

/// A mesh's bottom-level structure, its buffers, and its triangles' normals.
const PrimitiveStructure = struct {
    const Self = @This();

    /// The mesh's key.
    key: u64,
    /// The structure.
    structure: vulkan_c.VkAccelerationStructureKHR,
    /// Its device address, which instances name.
    address: u64,
    /// The buffer holding it. The vertices and indices it was built from are
    /// not kept: a structure is never refitted, so they are retired once its
    /// build is recorded.
    storage: mod.VulkanBuffer,
    /// Each triangle's vertex normals, owned.
    triangles: []HitTriangle,
    /// The frame it was last placed in.
    used_in: u64,
};

/// A texture's average color, which a reflection shows it as.
const TextureTint = struct {
    const Self = @This();

    /// `SceneTexture.key`.
    key: u64,
    /// Its pixels' average, linear.
    color: scenes.Vec3,
    /// The frame it was last used in.
    used_in: u64,
};

/// What a frame made or replaced, freed once that frame is surely done.
const RetiredObject = struct {
    const Self = @This();

    /// A buffer, or null.
    buffer: ?mod.VulkanBuffer = null,
    /// An acceleration structure, or null.
    structure: vulkan_c.VkAccelerationStructureKHR = null,
    /// The frame it was retired in.
    made_in: u64,
};

/// What one scene's frame needs for itself: its top-level structure and the
/// buffers it is built and read from, used again by a later frame once this
/// one is surely done, and grown when a frame needs more.
const FrameSet = struct {
    const Self = @This();

    /// The instances (`InstanceRecord`), shared.
    instances: ?mod.VulkanBuffer = null,
    /// The instances' surfaces (`HitInstance`), shared.
    surfaces: ?mod.VulkanBuffer = null,
    /// The buffer holding `structure`, private.
    storage: ?mod.VulkanBuffer = null,
    /// The top-level structure, over the whole of `storage`.
    structure: vulkan_c.VkAccelerationStructureKHR = null,
    /// Its device address.
    address: u64 = 0,
    /// The buffer `structure` is built with, private.
    scratch: ?mod.VulkanBuffer = null,
    /// The buffer the bottom-level structures this set's frame builds share
    /// for scratch, each in a part of its own, private; kept while frames
    /// taking the set go on building meshes, retired by one that builds none.
    mesh_scratch: ?mod.VulkanBuffer = null,
    /// How much of `mesh_scratch` this set's frame has handed out, in bytes.
    mesh_scratch_used: usize = 0,
    /// The frame that last used it.
    used_in: u64,
};

/// Builds and binds the opaque shapes' acceleration structures of each
/// ray-traced scene's frame on SDL's Vulkan device (see the file's header).
pub const VulkanSceneRayTracer = struct {
    const Self = @This();

    /// How many textures reflections sample (the shader's `reflected0` to `reflected7`, bindings 1 to 8).
    const reflected_texture_count = 8;
    /// The uniform slot the shader reads `Tracing` at.
    const tracing_slot = 2;
    /// The instance mask bit shadow rays test (`shadow_mask` in the shader).
    const shadow_mask: u32 = 1;
    /// The instance mask bit reflection rays test (`reflection_mask`).
    const reflection_mask: u32 = 2;
    /// Frames a bottom-level structure or tint outlives its last use before
    /// it is freed, as `SceneRenderer`'s meshes do.
    const idle_frames = 120;
    /// Frames a frame's own objects are kept before they are freed or used
    /// again: past the frames SDL lets be in flight.
    pub const retire_frames = 4;
    /// Whether `bind` reads a light's cookie and the scene's environment:
    /// not yet (Metal only), so they are never uploaded for it.
    pub const reads_planes = false;
    /// The most objects `prepare` retires for each shape: a new mesh's
    /// vertex and index buffer, the mesh scratch it outgrew, and its
    /// structure and storage should it not be kept (3), with room to spare.
    const retires_per_shape = 4;
    /// The most objects `prepare` retires once a call: the old triangle
    /// buffer, the surface and instance buffers outgrown, the top-level
    /// structure's storage and scratch outgrown, and the mesh scratch of a
    /// frame that built nothing (6), with room to spare.
    const retires_per_call = 8;
    /// The least a pooled shared buffer is made, in bytes, so small scenes never grow one.
    const least_buffer_length = 4096;
    /// The most pixels a texture's average reads, spread across it.
    const tint_samples = 65536;
    /// `VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR` and
    /// `VK_GEOMETRY_INSTANCE_FORCE_OPAQUE_BIT_KHR`: both faces meet a ray,
    /// and every hit is final.
    const instance_flags: u32 = vulkan_c.VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR | vulkan_c.VK_GEOMETRY_INSTANCE_FORCE_OPAQUE_BIT_KHR;
    /// What a build reads its vertices, indices and instances from.
    const input_usage = vulkan_c.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR;
    /// What a structure is held in.
    const storage_usage = vulkan_c.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR;
    /// What a build's scratch, and what the shader reads by address, are.
    const storage_buffer_usage = vulkan_c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;

    /// Owns the lists.
    allocator: std.mem.Allocator,
    /// SDL_GPU's Vulkan device and its functions.
    interop: mod.VulkanInterop,
    /// The meshes' bottom-level structures.
    primitives: std.ArrayList(PrimitiveStructure) = .empty,
    /// The textures' average colors.
    tints: std.ArrayList(TextureTint) = .empty,
    /// What frames made or replaced, waiting to be freed.
    retired: std.ArrayList(RetiredObject) = .empty,
    /// The scenes' frames' own structures and buffers, used again once done.
    sets: std.ArrayList(FrameSet) = .empty,
    /// The bottom-level structures this frame places, each once (`prepare`).
    placed: std.ArrayList(vulkan_c.VkAccelerationStructureKHR) = .empty,
    /// The textures this frame's reflections sample, each once, at most `reflected_texture_count`.
    sampled: std.ArrayList(*sdl_c.SDL_GPUTexture) = .empty,
    /// The structures `triangles` holds the normals of, in order.
    layout: std.ArrayList(vulkan_c.VkAccelerationStructureKHR) = .empty,
    /// Where each of `layout`'s meshes starts in `triangles`.
    first_triangles: std.ArrayList(u32) = .empty,
    /// Every laid-out mesh's triangles, one shared buffer; null until a frame needs it.
    triangles: ?mod.VulkanBuffer = null,
    /// This frame's top-level structure, null until `prepare` builds one.
    instances: vulkan_c.VkAccelerationStructureKHR = null,
    /// Its device address.
    instances_address: u64 = 0,
    /// This frame's instances' surfaces, null until `prepare` makes them.
    surfaces: ?mod.VulkanBuffer = null,
    /// The frame being drawn (`nextFrame`).
    frame_number: u64 = 0,

    /// A ray tracer on a device that supports one.
    ///
    /// - `allocator`: owns its lists.
    /// - `device`: the SDL_GPU device.
    /// - Returns: the ray tracer, or null where `supported` is false or its functions are missing (logged).
    pub fn init(allocator: std.mem.Allocator, device: *sdl_c.SDL_GPUDevice) ?Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        if (comptime !mod.has_vulkan_interop) return null;
        const interop = mod.VulkanInterop.init(device) orelse return null;
        const self = Self{ .allocator = allocator, .interop = interop };
        return self;
    }

    /// Frees every structure and buffer it holds, once the device is idle.
    ///
    /// - `self`: the ray tracer.
    pub fn deinit(self: *Self) void {
        if (comptime !mod.has_vulkan_interop) return;
        _ = sdl_c.SDL_WaitForGPUIdle(self.interop.device);
        for (self.primitives.items) |primitive| self.releasePrimitive(primitive);
        self.primitives.deinit(self.allocator);
        self.tints.deinit(self.allocator);
        for (self.retired.items) |retired| self.free(retired);
        self.retired.deinit(self.allocator);
        for (self.sets.items) |*frame_set| self.releaseSet(frame_set);
        self.sets.deinit(self.allocator);
        self.placed.deinit(self.allocator);
        self.sampled.deinit(self.allocator);
        self.layout.deinit(self.allocator);
        self.first_triangles.deinit(self.allocator);
        if (self.triangles) |buffer| self.interop.releaseBuffer(buffer);
    }

    /// Whether a device traces a scene's rays: SDL built with
    /// `vulkan_interop.c`, the Vulkan driver, and a device it made able to.
    ///
    /// - `device`: an SDL_GPU device.
    /// - Returns: true when `init` can make a ray tracer for it.
    pub fn supported(device: *sdl_c.SDL_GPUDevice) bool {
        if (comptime !mod.has_vulkan_interop) return false;
        return mod.VulkanInterop.tracesRays(device);
    }

    /// Starts a frame: what this frame's predecessors retired is freed once
    /// `retire_frames` have passed, and a bottom-level structure, tint or
    /// frame set unused for `idle_frames` is freed.
    ///
    /// - `self`: the ray tracer.
    /// - `frame_number`: the frame now drawn (`SceneRenderer`'s count).
    pub fn nextFrame(self: *Self, frame_number: u64) void {
        if (comptime !mod.has_vulkan_interop) return;
        self.frame_number = frame_number;
        self.instances = null;
        self.instances_address = 0;
        self.surfaces = null;
        self.placed.clearRetainingCapacity();
        self.sampled.clearRetainingCapacity();
        var index: usize = 0;
        while (index < self.retired.items.len) {
            const retired = self.retired.items[index];
            if (retired.made_in + retire_frames > frame_number) {
                index += 1;
                continue;
            }
            self.free(retired);
            _ = self.retired.swapRemove(index);
        }
        index = 0;
        while (index < self.primitives.items.len) {
            const primitive = self.primitives.items[index];
            if (primitive.used_in + idle_frames >= frame_number) {
                index += 1;
                continue;
            }
            // The laid-out triangles hold its normals: they go too, laid
            // out again when a frame next needs them.
            self.layout.clearRetainingCapacity();
            if (self.triangles) |buffer| self.retire(.{ .buffer = buffer, .made_in = frame_number });
            self.triangles = null;
            self.releasePrimitive(primitive);
            _ = self.primitives.swapRemove(index);
        }
        index = 0;
        while (index < self.sets.items.len) {
            if (self.sets.items[index].used_in + idle_frames >= frame_number) {
                index += 1;
                continue;
            }
            self.releaseSet(&self.sets.items[index]);
            _ = self.sets.swapRemove(index);
        }
        index = 0;
        while (index < self.tints.items.len) {
            if (self.tints.items[index].used_in + idle_frames >= frame_number) {
                index += 1;
                continue;
            }
            _ = self.tints.swapRemove(index);
        }
    }

    /// Builds this frame's structures on SDL's command buffer, no pass open:
    /// the bottom-level structure of each mesh that has none yet, the
    /// shapes' surfaces, and the top-level structure placing every shape,
    /// with the barriers that order them before the fragment shader.
    ///
    /// - `self`: the ray tracer.
    /// - `arena`: the frame's arena, for the meshes built again.
    /// - `command_buffer`: the frame's command buffer, no pass open.
    /// - `shapes`: the opaque shapes, at least one.
    /// - Returns: true when the structures are ready for `bind`; false (logged) when they could not be made, so the frame draws shadow maps.
    pub fn prepare(self: *Self, arena: std.mem.Allocator, command_buffer: *sdl_c.SDL_GPUCommandBuffer, shapes: []const mod.SceneRayShape) bool {
        if (comptime !mod.has_vulkan_interop) return false;
        if (shapes.len == 0) return false;
        const vulkan_command_buffer = self.interop.commandBuffer(command_buffer);
        if (vulkan_command_buffer == null) {
            log.warn("scene not ray traced: a pass is open on the command buffer", .{});
            return false;
        }
        // Room on the retired list for everything this call may retire, made
        // before anything is recorded: an entry that could not be listed would
        // be freed at once, while commands recorded into this frame's command
        // buffer, not yet submitted, still use it.
        self.retired.ensureUnusedCapacity(self.allocator, shapes.len * retires_per_shape + retires_per_call) catch |err| return Self.notDrawn(err);
        const records = arena.alloc(InstanceRecord, shapes.len) catch |err| return Self.notDrawn(err);
        const places = arena.alloc(u32, shapes.len) catch |err| return Self.notDrawn(err);
        // Taken before the meshes: their builds share its mesh scratch.
        const set_index = self.takeSet() orelse return false;
        var built = false;
        for (shapes, records, places) |shape, *record, *place| {
            const primitive = self.primitiveFor(arena, vulkan_command_buffer, &self.sets.items[set_index], shape, &built) orelse return self.abandonBuilds(vulkan_command_buffer, built);
            place.* = self.placeIndex(primitive.structure) orelse return self.abandonBuilds(vulkan_command_buffer, built);
            const mask = (if (shape.reflected) reflection_mask else 0) | (if (shape.casts_shadows) shadow_mask else 0);
            record.* = .{
                .transform = Self.rowTransform(shape.world),
                .custom_index_and_mask = mask << 24,
                .offset_and_flags = instance_flags << 24,
                .structure = primitive.address,
            };
        }
        // The top-level build reads the bottom-level structures built above.
        if (built) self.barrier(vulkan_command_buffer, vulkan_c.VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR);
        // A frame that built no mesh lets the set's mesh scratch go, so a
        // burst of new meshes holds no memory once it is over.
        if (!built) self.releaseMeshScratch(&self.sets.items[set_index]);
        if (!self.layOutTriangles()) return false;
        self.surfaces = self.makeSurfaces(arena, shapes, places, set_index);
        if (self.surfaces == null) return false;
        if (!self.buildInstances(vulkan_command_buffer, records, set_index)) return false;
        // The fragment shader's ray queries read the top-level structure.
        self.barrier(vulkan_command_buffer, vulkan_c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
        const frame_set = &self.sets.items[set_index];
        self.instances = frame_set.structure;
        self.instances_address = frame_set.address;
        return true;
    }

    /// Hands this frame's structures to the lit pass: the top-level
    /// structure's, the surfaces' and the triangles' addresses and the sky
    /// in the fragment uniforms at `tracing_slot`, and the sampled textures
    /// in the sampler slots after the base texture. Call after the pass
    /// begins and before it draws.
    ///
    /// - `self`: the ray tracer.
    /// - `command_buffer`: the frame's command buffer, the lit pass open on it.
    /// - `pass`: the lit pass.
    /// - `sky`: what a reflection that meets nothing shows, linear.
    /// - `cookie`: unused: cookies apply on Metal only.
    /// - `environment`: unused: environments apply on Metal only.
    /// - `soft_rays`: unused: Vulkan's shader sends 16.
    /// - `blank`: a texture bound in the slots no texture fills.
    /// - `sampler`: what the textures are sampled with.
    /// - Returns: false when nothing was prepared.
    pub fn bind(self: *Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer, pass: *sdl_c.SDL_GPURenderPass, sky: scenes.Vec3, cookie: ?mod.SceneRayCookie, environment: ?mod.SceneRayEnvironment, soft_rays: u32, blank: *sdl_c.SDL_GPUTexture, sampler: *sdl_c.SDL_GPUSampler) bool {
        _ = soft_rays;
        _ = environment;
        _ = cookie;
        if (comptime !mod.has_vulkan_interop) return false;
        if (self.instances == null) return false;
        const surfaces = self.surfaces orelse return false;
        const triangles = self.triangles orelse return false;
        const tracing = Tracing{
            .sky = .{ sky.x, sky.y, sky.z, 0 },
            .shapes = self.instances_address,
            .instances = surfaces.address,
            .triangles = triangles.address,
        };
        sdl_c.SDL_PushGPUFragmentUniformData(command_buffer, tracing_slot, &tracing, @sizeOf(Tracing));
        var bindings: [reflected_texture_count]sdl_c.SDL_GPUTextureSamplerBinding = undefined;
        for (&bindings, 0..) |*binding, index| {
            binding.* = .{ .texture = if (index < self.sampled.items.len) self.sampled.items[index] else blank, .sampler = sampler };
        }
        sdl_c.SDL_BindGPUFragmentSamplers(pass, 1, &bindings, bindings.len);
        return true;
    }

    /// Logs a frame drawn without rays for want of memory.
    ///
    /// - `failure`: why.
    /// - Returns: false, for the caller to return.
    fn notDrawn(failure: anyerror) bool {
        log.warn("scene not ray traced: {s}", .{@errorName(failure)});
        return false;
    }

    /// Gives up on a frame's structures part way through the meshes: still
    /// records the barrier after the bottom-level builds recorded so far, since
    /// they are kept and a later top-level build (another scene this frame, or
    /// the next frame) reads them as built.
    ///
    /// - `self`: the ray tracer.
    /// - `command_buffer`: the frame's `VkCommandBuffer`, no pass open.
    /// - `built`: whether a bottom-level build was recorded this call.
    /// - Returns: false, for `prepare` to return.
    fn abandonBuilds(self: *Self, command_buffer: vulkan_c.VkCommandBuffer, built: bool) bool {
        if (built) self.barrier(command_buffer, vulkan_c.VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR);
        return false;
    }

    /// A shape's mesh's bottom-level structure: the one kept by its key, else
    /// one built now, from its vertices and indices uploaded to one buffer
    /// that is retired once the build is recorded, with scratch from the
    /// frame set's mesh scratch.
    ///
    /// - `self`: the ray tracer.
    /// - `arena`: the frame's arena, for the mesh built again.
    /// - `command_buffer`: the `VkCommandBuffer`, no pass open.
    /// - `frame_set`: the call's frame set, whose mesh scratch the build uses.
    /// - `shape`: the shape whose mesh it is.
    /// - `built`: set when a structure is built.
    /// - Returns: the structure's entry, or null when it could not be made (logged).
    fn primitiveFor(self: *Self, arena: std.mem.Allocator, command_buffer: vulkan_c.VkCommandBuffer, frame_set: *FrameSet, shape: mod.SceneRayShape, built: *bool) ?*const PrimitiveStructure {
        for (self.primitives.items) |*primitive| {
            if (primitive.key != shape.key) continue;
            primitive.used_in = self.frame_number;
            return primitive;
        }
        const data = shape.geometry.build(arena) catch |err| {
            log.warn("ray tracing mesh not built: {s}", .{@errorName(err)});
            return null;
        };
        if (data.indices.len < 3 or data.vertices.len == 0) {
            log.warn("ray tracing mesh not built: no triangles", .{});
            return null;
        }
        const triangles = self.triangleNormals(data) orelse return null;
        const vertex_bytes = std.mem.sliceAsBytes(data.vertices);
        const index_bytes = std.mem.sliceAsBytes(data.indices);
        // The indices after the vertices, at a multiple of their size.
        const index_offset = std.mem.alignForward(usize, vertex_bytes.len, @sizeOf(u32));
        const inputs = self.interop.makeBuffer(index_offset + index_bytes.len, input_usage, .shared) orelse {
            self.allocator.free(triangles);
            return null;
        };
        @memcpy(inputs.mapped.?[0..vertex_bytes.len], vertex_bytes);
        @memcpy(inputs.mapped.?[index_offset..][0..index_bytes.len], index_bytes);
        const geometry: vulkan_c.VkAccelerationStructureGeometryKHR = .{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
            .geometryType = vulkan_c.VK_GEOMETRY_TYPE_TRIANGLES_KHR,
            .geometry = .{ .triangles = .{
                .sType = vulkan_c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
                .vertexFormat = vulkan_c.VK_FORMAT_R32G32B32_SFLOAT,
                .vertexData = .{ .deviceAddress = inputs.address + @offsetOf(scenes.SceneVertex, "position") },
                .vertexStride = @sizeOf(scenes.SceneVertex),
                .maxVertex = @intCast(data.vertices.len - 1),
                .indexType = vulkan_c.VK_INDEX_TYPE_UINT32,
                .indexData = .{ .deviceAddress = inputs.address + index_offset },
            } },
            .flags = vulkan_c.VK_GEOMETRY_OPAQUE_BIT_KHR,
        };
        const triangle_count: u32 = @intCast(data.indices.len / 3);
        var structure: vulkan_c.VkAccelerationStructureKHR = null;
        var storage: mod.VulkanBuffer = undefined;
        if (!self.build(command_buffer, frame_set, &geometry, triangle_count, &structure, &storage)) {
            self.interop.releaseBuffer(inputs);
            self.allocator.free(triangles);
            return null;
        }
        built.* = true;
        // Read by the build just recorded, then never again.
        self.retire(.{ .buffer = inputs, .made_in = self.frame_number });
        const entry: PrimitiveStructure = .{
            .key = shape.key,
            .structure = structure,
            .address = self.structureAddress(structure),
            .storage = storage,
            .triangles = triangles,
            .used_in = self.frame_number,
        };
        self.primitives.append(self.allocator, entry) catch |err| {
            // Built already: freed once its build is surely done.
            log.warn("ray tracing structure not kept: {s}", .{@errorName(err)});
            self.allocator.free(triangles);
            self.retire(.{ .structure = structure, .buffer = storage, .made_in = self.frame_number });
            return null;
        };
        return &self.primitives.items[self.primitives.items.len - 1];
    }

    /// Each triangle's vertex normals and texture coordinates, from a built mesh.
    ///
    /// - `self`: the ray tracer.
    /// - `data`: the mesh.
    /// - Returns: the triangles, owned by the caller; null (logged) for want of memory.
    fn triangleNormals(self: *Self, data: scenes.SceneGeometryData) ?[]HitTriangle {
        const triangles = self.allocator.alloc(HitTriangle, data.indices.len / 3) catch |err| {
            log.warn("ray tracing mesh not built: {s}", .{@errorName(err)});
            return null;
        };
        for (triangles, 0..) |*triangle, index| {
            triangle.unused = .{ 0, 0 };
            for (&triangle.normals, &triangle.uvs, data.indices[index * 3 ..][0..3]) |*normal, *uv, vertex| {
                const source = data.vertices[vertex];
                normal.* = .{ source.normal[0], source.normal[1], source.normal[2], 0 };
                uv.* = source.uv;
            }
        }
        return triangles;
    }

    /// Records a bottom-level structure's build on the command buffer: its
    /// sizes asked, a private buffer made to hold it, the structure made over
    /// that buffer, and a part of the frame set's mesh scratch to build it with.
    ///
    /// - `self`: the ray tracer.
    /// - `command_buffer`: the `VkCommandBuffer`, no pass open.
    /// - `frame_set`: the call's frame set, whose mesh scratch the build uses.
    /// - `geometry`: what it is built from.
    /// - `count`: its triangles.
    /// - `structure`: receives the structure, owned by the caller.
    /// - `storage`: receives the buffer holding it, owned by the caller.
    /// - Returns: false (logged) when it could not be made.
    fn build(self: *Self, command_buffer: vulkan_c.VkCommandBuffer, frame_set: *FrameSet, geometry: *const vulkan_c.VkAccelerationStructureGeometryKHR, count: u32, structure: *vulkan_c.VkAccelerationStructureKHR, storage: *mod.VulkanBuffer) bool {
        const kind = vulkan_c.VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR;
        var info = Self.buildInfo(kind, geometry);
        const sizes = self.buildSizes(&info, count);
        storage.* = self.interop.makeBuffer(sizes.accelerationStructureSize, storage_usage, .private) orelse return false;
        structure.* = self.makeStructure(storage.*, kind) orelse {
            self.interop.releaseBuffer(storage.*);
            return false;
        };
        const scratch = self.meshScratch(frame_set, sizes.buildScratchSize) orelse {
            self.interop.functions.vkDestroyAccelerationStructureKHR.?(self.interop.vulkan_device, structure.*, null);
            self.interop.releaseBuffer(storage.*);
            return false;
        };
        info.dstAccelerationStructure = structure.*;
        info.scratchData = .{ .deviceAddress = scratch };
        self.recordBuild(command_buffer, &info, count);
        return true;
    }

    /// A part of the frame set's mesh scratch for one build, aligned for
    /// scratch and apart from every other part this frame handed out, so the
    /// frame's builds run at once. When the rest is too small the buffer is
    /// made anew, half as large again (at least `least_buffer_length`), the
    /// old one retired, since builds recorded this frame still use it.
    ///
    /// - `self`: the ray tracer.
    /// - `frame_set`: the call's frame set.
    /// - `size`: the scratch the build needs, in bytes.
    /// - Returns: the part's device address, or null (logged) when no buffer could be made.
    fn meshScratch(self: *Self, frame_set: *FrameSet, size: u64) ?u64 {
        const needed: usize = @intCast(size +| self.interop.scratch_alignment);
        const fits = if (frame_set.mesh_scratch) |buffer| buffer.size - frame_set.mesh_scratch_used >= needed else false;
        if (!fits) {
            const grown = if (frame_set.mesh_scratch) |old| old.size +| old.size / 2 else 0;
            self.releaseMeshScratch(frame_set);
            frame_set.mesh_scratch = self.interop.makeBuffer(@max(needed, grown, least_buffer_length), storage_buffer_usage, .private) orelse return null;
        }
        const buffer = frame_set.mesh_scratch.?;
        const address = self.alignedScratch(buffer.address + frame_set.mesh_scratch_used);
        frame_set.mesh_scratch_used = @intCast(address + size - buffer.address);
        return address;
    }

    /// Retires a frame set's mesh scratch: builds recorded this frame may
    /// still use it.
    ///
    /// - `self`: the ray tracer.
    /// - `frame_set`: the set.
    fn releaseMeshScratch(self: *Self, frame_set: *FrameSet) void {
        if (frame_set.mesh_scratch) |old| self.retire(.{ .buffer = old, .made_in = self.frame_number });
        frame_set.mesh_scratch = null;
        frame_set.mesh_scratch_used = 0;
    }

    /// A build's description, for a fresh build preferring fast tracing.
    ///
    /// - `kind`: bottom- or top-level.
    /// - `geometry`: what it is built from.
    /// - Returns: the description, its structure and scratch still to fill.
    fn buildInfo(kind: vulkan_c.VkAccelerationStructureTypeKHR, geometry: *const vulkan_c.VkAccelerationStructureGeometryKHR) vulkan_c.VkAccelerationStructureBuildGeometryInfoKHR {
        return .{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
            .type = kind,
            .flags = vulkan_c.VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR,
            .mode = vulkan_c.VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR,
            .geometryCount = 1,
            .pGeometries = geometry,
        };
    }

    /// How large a structure and its build's scratch must be.
    ///
    /// - `self`: the ray tracer.
    /// - `info`: the build.
    /// - `count`: its triangles, or its instances.
    /// - Returns: the sizes.
    fn buildSizes(self: *Self, info: *const vulkan_c.VkAccelerationStructureBuildGeometryInfoKHR, count: u32) vulkan_c.VkAccelerationStructureBuildSizesInfoKHR {
        var sizes: vulkan_c.VkAccelerationStructureBuildSizesInfoKHR = .{ .sType = vulkan_c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR };
        self.interop.functions.vkGetAccelerationStructureBuildSizesKHR.?(self.interop.vulkan_device, vulkan_c.VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR, info, &count, &sizes);
        return sizes;
    }

    /// Makes a structure over the whole of a buffer.
    ///
    /// - `self`: the ray tracer.
    /// - `storage`: the buffer.
    /// - `kind`: bottom- or top-level.
    /// - Returns: the structure, owned by the caller; null (logged) when it could not be made.
    fn makeStructure(self: *Self, storage: mod.VulkanBuffer, kind: vulkan_c.VkAccelerationStructureTypeKHR) vulkan_c.VkAccelerationStructureKHR {
        const create_info: vulkan_c.VkAccelerationStructureCreateInfoKHR = .{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
            .buffer = storage.buffer,
            .size = storage.size,
            .type = kind,
        };
        var structure: vulkan_c.VkAccelerationStructureKHR = null;
        if (self.interop.functions.vkCreateAccelerationStructureKHR.?(self.interop.vulkan_device, &create_info, null, &structure) != vulkan_c.VK_SUCCESS) {
            log.warn("scene not ray traced: no acceleration structure of {d} bytes", .{storage.size});
            return null;
        }
        return structure;
    }

    /// Records one build of `count` triangles or instances.
    ///
    /// - `self`: the ray tracer.
    /// - `command_buffer`: the `VkCommandBuffer`, no pass open.
    /// - `info`: the build, its structure and scratch filled.
    /// - `count`: its triangles, or its instances.
    fn recordBuild(self: *Self, command_buffer: vulkan_c.VkCommandBuffer, info: *const vulkan_c.VkAccelerationStructureBuildGeometryInfoKHR, count: u32) void {
        const range: vulkan_c.VkAccelerationStructureBuildRangeInfoKHR = .{ .primitiveCount = count };
        const ranges = [_]*const vulkan_c.VkAccelerationStructureBuildRangeInfoKHR{&range};
        self.interop.functions.vkCmdBuildAccelerationStructuresKHR.?(command_buffer, 1, info, &ranges);
    }

    /// A structure's device address.
    ///
    /// - `self`: the ray tracer.
    /// - `structure`: the structure.
    /// - Returns: its address.
    fn structureAddress(self: *Self, structure: vulkan_c.VkAccelerationStructureKHR) u64 {
        const info: vulkan_c.VkAccelerationStructureDeviceAddressInfoKHR = .{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
            .accelerationStructure = structure,
        };
        return self.interop.functions.vkGetAccelerationStructureDeviceAddressKHR.?(self.interop.vulkan_device, &info);
    }

    /// A scratch buffer's address rounded up to the alignment builds need
    /// (the buffer is made that much larger).
    ///
    /// - `self`: the ray tracer.
    /// - `address`: the buffer's address.
    /// - Returns: the aligned address.
    fn alignedScratch(self: *const Self, address: u64) u64 {
        return std.mem.alignForward(u64, address, self.interop.scratch_alignment);
    }

    /// Records a barrier making every acceleration structure built before it
    /// readable by `stage`.
    ///
    /// - `self`: the ray tracer.
    /// - `command_buffer`: the `VkCommandBuffer`, no pass open.
    /// - `stage`: what reads the structures next: a build, or the fragment shader.
    fn barrier(self: *Self, command_buffer: vulkan_c.VkCommandBuffer, stage: vulkan_c.VkPipelineStageFlags) void {
        const memory_barrier: vulkan_c.VkMemoryBarrier = .{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_MEMORY_BARRIER,
            .srcAccessMask = vulkan_c.VK_ACCESS_ACCELERATION_STRUCTURE_WRITE_BIT_KHR,
            .dstAccessMask = vulkan_c.VK_ACCESS_ACCELERATION_STRUCTURE_READ_BIT_KHR,
        };
        self.interop.functions.vkCmdPipelineBarrier.?(command_buffer, vulkan_c.VK_PIPELINE_STAGE_ACCELERATION_STRUCTURE_BUILD_BIT_KHR, stage, 0, 1, &memory_barrier, 0, null, 0, null);
    }

    /// Where a bottom-level structure sits among those this frame places,
    /// added the first time it is placed.
    ///
    /// - `self`: the ray tracer.
    /// - `structure`: the structure.
    /// - Returns: its index, or null when it could not be added (logged).
    fn placeIndex(self: *Self, structure: vulkan_c.VkAccelerationStructureKHR) ?u32 {
        for (self.placed.items, 0..) |placed, index| if (placed == structure) return @intCast(index);
        self.placed.append(self.allocator, structure) catch |err| {
            log.warn("scene not ray traced: {s}", .{@errorName(err)});
            return null;
        };
        return @intCast(self.placed.items.len - 1);
    }

    /// Makes sure `triangles` holds the normals of this frame's placed
    /// meshes, in their order: kept while the placed meshes are the laid-out
    /// ones or the first of them (a frame's second scene places its first's
    /// meshes and more, and the next frame's first scene its first again),
    /// else laid out again in a new buffer (the old one retired).
    ///
    /// - `self`: the ray tracer.
    /// - Returns: false (logged) when the buffer could not be made.
    fn layOutTriangles(self: *Self) bool {
        if (self.triangles != null and std.mem.startsWith(vulkan_c.VkAccelerationStructureKHR, self.layout.items, self.placed.items)) return true;
        self.layout.clearRetainingCapacity();
        self.first_triangles.clearRetainingCapacity();
        var count: usize = 0;
        for (self.placed.items) |structure| {
            self.first_triangles.append(self.allocator, @intCast(count)) catch |err| return Self.notDrawn(err);
            const primitive = self.primitiveOf(structure) orelse return false;
            count += primitive.triangles.len;
        }
        const buffer = self.interop.makeBuffer(@max(count, 1) * @sizeOf(HitTriangle), storage_buffer_usage, .shared) orelse return false;
        const contents: [*]HitTriangle = @ptrCast(@alignCast(buffer.mapped.?));
        for (self.placed.items, self.first_triangles.items) |structure, first| {
            // Every placed structure was found above.
            const triangles = self.primitiveOf(structure).?.triangles;
            @memcpy(contents[first..][0..triangles.len], triangles);
        }
        if (self.triangles) |old| self.retire(.{ .buffer = old, .made_in = self.frame_number });
        self.triangles = buffer;
        self.layout.appendSlice(self.allocator, self.placed.items) catch |err| {
            // Laid out but not remembered: laid out again next frame.
            self.layout.clearRetainingCapacity();
            log.warn("ray tracing layout not kept: {s}", .{@errorName(err)});
        };
        return true;
    }

    /// The kept bottom-level structure that is `structure`.
    ///
    /// - `self`: the ray tracer.
    /// - `structure`: a structure this frame placed.
    /// - Returns: its entry, or null when none is kept (logged).
    fn primitiveOf(self: *const Self, structure: vulkan_c.VkAccelerationStructureKHR) ?*const PrimitiveStructure {
        for (self.primitives.items) |*primitive| if (primitive.structure == structure) return primitive;
        log.warn("scene not ray traced: a placed structure is not kept", .{});
        return null;
    }

    /// This frame's instances' surfaces, in the shapes' order, in the frame
    /// set's surface buffer.
    ///
    /// - `self`: the ray tracer.
    /// - `arena`: the frame's arena.
    /// - `shapes`: the shapes.
    /// - `places`: each shape's mesh's index among the placed ones.
    /// - `set_index`: the frame set's index (`takeSet`).
    /// - Returns: the buffer, or null when it could not be made (logged).
    fn makeSurfaces(self: *Self, arena: std.mem.Allocator, shapes: []const mod.SceneRayShape, places: []const u32, set_index: usize) ?mod.VulkanBuffer {
        const surfaces = arena.alloc(HitInstance, shapes.len) catch |err| {
            log.warn("scene not ray traced: {s}", .{@errorName(err)});
            return null;
        };
        for (surfaces, shapes, places) |*surface, shape, place| {
            var color = scenes.SceneFrame.linear(shape.material.base_color);
            const sampled = if (shape.texture) |texture| self.samplerIndex(texture) else -1;
            if (sampled < 0) if (shape.material.texture) |texture| {
                color = color.multiply(self.tintOf(texture));
            };
            surface.* = .{
                .normal_matrix = .{
                    .{ shape.normal.columns[0].x, shape.normal.columns[0].y, shape.normal.columns[0].z, 0 },
                    .{ shape.normal.columns[1].x, shape.normal.columns[1].y, shape.normal.columns[1].z, 0 },
                    .{ shape.normal.columns[2].x, shape.normal.columns[2].y, shape.normal.columns[2].z, 0 },
                },
                .color = .{ color.x, color.y, color.z, @max(shape.material.specular, 0) },
                .first_triangle = self.first_triangles.items[place],
                .shininess = shape.material.shininess,
                .texture = sampled,
                .emission = shape.material.emissionShare(),
            };
        }
        const frame_set = &self.sets.items[set_index];
        return self.fill(&frame_set.surfaces, std.mem.sliceAsBytes(surfaces), storage_buffer_usage);
    }

    /// Which of this frame's sampled textures a texture is, added the first
    /// time while there is room.
    ///
    /// - `self`: the ray tracer.
    /// - `texture`: the texture.
    /// - Returns: its index, or -1 past `reflected_texture_count` (or when it could not be added).
    fn samplerIndex(self: *Self, texture: *sdl_c.SDL_GPUTexture) i32 {
        for (self.sampled.items, 0..) |sampled, index| if (sampled == texture) return @intCast(index);
        if (self.sampled.items.len >= reflected_texture_count) return -1;
        self.sampled.append(self.allocator, texture) catch |err| {
            log.warn("texture shown by its average in reflections: {s}", .{@errorName(err)});
            return -1;
        };
        return @intCast(self.sampled.items.len - 1);
    }

    /// A texture's average color, linear, worked out once and kept by its
    /// key: what a reflection shows a textured surface as.
    ///
    /// - `self`: the ray tracer.
    /// - `texture`: the texture.
    /// - Returns: the average, white when it has no pixels to read.
    fn tintOf(self: *Self, texture: scenes.SceneTexture) scenes.Vec3 {
        const key = texture.key();
        for (self.tints.items) |*tint| {
            if (tint.key != key) continue;
            tint.used_in = self.frame_number;
            return tint.color;
        }
        const image = texture.image;
        const white = scenes.Vec3.init(1, 1, 1);
        if (image.width == 0 or image.height == 0 or !image.isWhole()) return white;
        const pixel_count: usize = @as(usize, image.width) * image.height;
        const step = @max(pixel_count / tint_samples, 1);
        var sum = scenes.Vec3.zero;
        var samples: f32 = 0;
        var index: usize = 0;
        while (index < pixel_count) : (index += step) {
            const pixel = image.pixels[index * 4 ..][0..4];
            const color = renderer.Color{ .r = @as(f32, @floatFromInt(pixel[0])) / 255, .g = @as(f32, @floatFromInt(pixel[1])) / 255, .b = @as(f32, @floatFromInt(pixel[2])) / 255 };
            sum = sum.add(scenes.SceneFrame.linear(color));
            samples += 1;
        }
        const average = sum.scale(1 / samples);
        self.tints.append(self.allocator, .{ .key = key, .color = average, .used_in = self.frame_number }) catch |err| {
            log.warn("texture's average not kept: {s}", .{@errorName(err)});
        };
        return average;
    }

    /// Records this frame's top-level build from its instances, into the
    /// frame set's structure with its scratch buffer (each made larger first
    /// when this frame needs more, the old ones retired).
    ///
    /// - `self`: the ray tracer.
    /// - `command_buffer`: the `VkCommandBuffer`, no pass open.
    /// - `records`: one instance per shape.
    /// - `set_index`: the frame set's index (`takeSet`).
    /// - Returns: false (logged) when it could not be made.
    fn buildInstances(self: *Self, command_buffer: vulkan_c.VkCommandBuffer, records: []const InstanceRecord, set_index: usize) bool {
        const frame_set = &self.sets.items[set_index];
        const instances = self.fill(&frame_set.instances, std.mem.sliceAsBytes(records), input_usage) orelse return false;
        const geometry: vulkan_c.VkAccelerationStructureGeometryKHR = .{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
            .geometryType = vulkan_c.VK_GEOMETRY_TYPE_INSTANCES_KHR,
            .geometry = .{ .instances = .{
                .sType = vulkan_c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
                .arrayOfPointers = vulkan_c.VK_FALSE,
                .data = .{ .deviceAddress = instances.address },
            } },
            .flags = vulkan_c.VK_GEOMETRY_OPAQUE_BIT_KHR,
        };
        const count: u32 = @intCast(records.len);
        var info = Self.buildInfo(vulkan_c.VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR, &geometry);
        const sizes = self.buildSizes(&info, count);
        if (frame_set.storage == null or frame_set.storage.?.size < sizes.accelerationStructureSize) {
            if (frame_set.storage) |storage| self.retire(.{ .structure = frame_set.structure, .buffer = storage, .made_in = self.frame_number });
            frame_set.storage = null;
            frame_set.structure = null;
            const storage = self.interop.makeBuffer(sizes.accelerationStructureSize, storage_usage, .private) orelse return false;
            const structure = self.makeStructure(storage, vulkan_c.VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR) orelse {
                self.interop.releaseBuffer(storage);
                return false;
            };
            frame_set.storage = storage;
            frame_set.structure = structure;
            frame_set.address = self.structureAddress(structure);
        }
        const scratch_needed = sizes.buildScratchSize + self.interop.scratch_alignment;
        if (frame_set.scratch == null or frame_set.scratch.?.size < scratch_needed) {
            if (frame_set.scratch) |scratch| self.retire(.{ .buffer = scratch, .made_in = self.frame_number });
            frame_set.scratch = self.interop.makeBuffer(scratch_needed, storage_buffer_usage, .private) orelse return false;
        }
        info.dstAccelerationStructure = frame_set.structure;
        info.scratchData = .{ .deviceAddress = self.alignedScratch(frame_set.scratch.?.address) };
        self.recordBuild(command_buffer, &info, count);
        return true;
    }

    /// A frame set for this scene's frame: one no frame still in flight
    /// uses, else a new, empty one.
    ///
    /// - `self`: the ray tracer.
    /// - Returns: the set's index, or null when a new one could not be listed (logged).
    fn takeSet(self: *Self) ?usize {
        for (self.sets.items, 0..) |*frame_set, index| {
            if (frame_set.used_in + retire_frames > self.frame_number) continue;
            frame_set.used_in = self.frame_number;
            // No frame still in flight uses its mesh scratch: handed out afresh.
            frame_set.mesh_scratch_used = 0;
            return index;
        }
        self.sets.append(self.allocator, .{ .used_in = self.frame_number }) catch |err| {
            log.warn("scene not ray traced: {s}", .{@errorName(err)});
            return null;
        };
        return self.sets.items.len - 1;
    }

    /// Copies `bytes` into a pooled shared buffer, made anew half as large
    /// again (at least `least_buffer_length`) when they do not fit, the old
    /// one retired.
    ///
    /// - `self`: the ray tracer.
    /// - `slot`: the pooled buffer, null until first made.
    /// - `bytes`: what it is to hold.
    /// - `usage`: its `VkBufferUsageFlags`.
    /// - Returns: the buffer, or null when it could not be made (logged).
    fn fill(self: *Self, slot: *?mod.VulkanBuffer, bytes: []const u8, usage: vulkan_c.VkBufferUsageFlags) ?mod.VulkanBuffer {
        if (slot.* == null or slot.*.?.size < bytes.len) {
            if (slot.*) |old| self.retire(.{ .buffer = old, .made_in = self.frame_number });
            slot.* = self.interop.makeBuffer(@max(bytes.len +| bytes.len / 2, least_buffer_length), usage, .shared);
        }
        const buffer = slot.* orelse return null;
        @memcpy(buffer.mapped.?[0..bytes.len], bytes);
        return buffer;
    }

    /// Frees a bottom-level structure, its buffers and its triangles' normals.
    /// The GPU must be done with it.
    ///
    /// - `self`: the ray tracer.
    /// - `primitive`: the entry.
    fn releasePrimitive(self: *Self, primitive: PrimitiveStructure) void {
        self.interop.functions.vkDestroyAccelerationStructureKHR.?(self.interop.vulkan_device, primitive.structure, null);
        self.interop.releaseBuffer(primitive.storage);
        self.allocator.free(primitive.triangles);
    }

    /// Frees a frame set's structure and buffers. The GPU must be done with them.
    ///
    /// - `self`: the ray tracer.
    /// - `frame_set`: the set.
    fn releaseSet(self: *Self, frame_set: *FrameSet) void {
        self.free(.{ .structure = frame_set.structure, .buffer = frame_set.storage, .made_in = 0 });
        if (frame_set.instances) |buffer| self.interop.releaseBuffer(buffer);
        if (frame_set.surfaces) |buffer| self.interop.releaseBuffer(buffer);
        if (frame_set.scratch) |buffer| self.interop.releaseBuffer(buffer);
        if (frame_set.mesh_scratch) |buffer| self.interop.releaseBuffer(buffer);
    }

    /// Frees what a retired entry holds.
    ///
    /// - `self`: the ray tracer.
    /// - `retired`: the entry.
    fn free(self: *Self, retired: RetiredObject) void {
        if (retired.structure != null) self.interop.functions.vkDestroyAccelerationStructureKHR.?(self.interop.vulkan_device, retired.structure, null);
        if (retired.buffer) |buffer| self.interop.releaseBuffer(buffer);
    }

    /// Keeps what this frame made or replaced until `retire_frames` have
    /// passed. `prepare` reserves the room first, so what it retires is always
    /// listed; elsewhere (an eviction between frames, nothing recorded since),
    /// an entry that cannot be listed waits for the device and is freed now.
    ///
    /// - `self`: the ray tracer.
    /// - `retired`: the entry, owned.
    fn retire(self: *Self, retired: RetiredObject) void {
        self.retired.append(self.allocator, retired) catch |err| {
            log.warn("ray tracing object freed early: {s}", .{@errorName(err)});
            _ = sdl_c.SDL_WaitForGPUIdle(self.interop.device);
            self.free(retired);
        };
    }

    /// A column-major transform as Vulkan's `VkTransformMatrixKHR`: the
    /// first three rows of its four columns (the last row of an affine
    /// transform is 0, 0, 0, 1).
    ///
    /// - `world`: the transform.
    /// - Returns: the rows.
    fn rowTransform(world: scenes.Mat4) [3][4]f32 {
        const columns = world.columns;
        return .{
            .{ columns[0].x, columns[1].x, columns[2].x, columns[3].x },
            .{ columns[0].y, columns[1].y, columns[2].y, columns[3].y },
            .{ columns[0].z, columns[1].z, columns[2].z, columns[3].z },
        };
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the instance, surface, triangle and tracing records have the shader's layout, and a transform packs by rows" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(InstanceRecord));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(InstanceRecord, "custom_index_and_mask"));
    try std.testing.expectEqual(@as(usize, 56), @offsetOf(InstanceRecord, "structure"));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(HitInstance));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(HitInstance, "first_triangle"));
    try std.testing.expectEqual(@as(usize, 72), @offsetOf(HitInstance, "texture"));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(HitTriangle));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(HitTriangle, "uvs"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Tracing, "shapes"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(Tracing, "triangles"));
    const moved = scenes.Mat4.translation(scenes.Vec3.init(1, 2, 3));
    const rows = VulkanSceneRayTracer.rowTransform(moved);
    try std.testing.expectEqualSlices(f32, &.{ 1, 0, 0, 1 }, &rows[0]);
    try std.testing.expectEqualSlices(f32, &.{ 0, 1, 0, 2 }, &rows[1]);
    try std.testing.expectEqualSlices(f32, &.{ 0, 0, 1, 3 }, &rows[2]);
}
