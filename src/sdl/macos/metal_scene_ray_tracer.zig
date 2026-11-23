//! The Metal ray tracing behind a scene's `SceneLightingTechnique.rayTraced`
//! shadows and reflections, on SDL_GPU's own device and command buffers
//! (`MetalInterop`): a primitive acceleration structure per mesh, built from
//! the mesh's SDL buffers once and kept by its key (with its triangles'
//! vertex normals) until it goes unused, and each frame an instance
//! acceleration structure placing the opaque shapes, which the traced
//! fragment shader (`scene_traced.metal`) meets rays against: shadow rays see
//! only the shapes that cast shadows (instance mask bit 0), reflection rays
//! every opaque shape (bit 1), shaded from each instance's surface (normal
//! matrix, color, highlight, texture) and its triangle's normals and texture
//! coordinates. A frame's first `reflected_texture_count` textures are
//! sampled where a reflection meets them; past them a texture shows as its
//! average color.
//!
//! A frame builds its structures between SDL's passes (`prepare`, after the
//! meshes' upload), then binds them on SDL's render encoder once the lit pass
//! begins (`bind`), past the slots SDL_GPU binds: the instance structure at
//! fragment buffer 16 (each primitive structure made resident), the
//! instances' surfaces at 17, the triangles at 18, the sky at 19, and the
//! textures at fragment textures 8 to 15.
//! Metal orders the builds after the uploads and before the pass, since SDL's
//! resources are hazard-tracked. The instance structure is built in a command
//! buffer of its own on SDL's queue, committed at once, so it runs before the
//! whole frame rather than stalling the scene's pass in the frame's middle;
//! only a frame that builds a mesh's structure (after that mesh's upload),
//! for any of its scenes, builds its instance structures in SDL's. What a scene's frame needs for itself (its instance
//! structure, its scratch, instance and surface buffers) comes from a pool of
//! `FrameSet`s, each used again once the frame that used it is surely done
//! (past any frame still in flight) and grown only when a frame needs more:
//! a structure or buffer made anew stalls the frame as a mid-frame build does.
//!
//! Only on Apple silicon (the Objective-C bridge returns structs larger than
//! 16 bytes, as `accelerationStructureSizesWithDescriptor:` does, the arm64
//! way), with SDL built from the release (`has_metal_interop`), on a device
//! that traces rays from a render pipeline. macOS only: other targets reach
//! it only behind `os_tag == .macos`, and `supported` is false there.

const std = @import("std");
const log = std.log.scoped(.ziggui_metal_scene_ray_tracer);
const mod = @import("module.zig");
const renderer = @import("renderer");
const scenes = @import("scenes");
const sdl_c = @import("sdl_c");

/// A mesh triangle's vertex normals and texture coordinates, as
/// `SceneHitTriangle` in the shader.
const HitTriangle = extern struct {
    const Self = @This();

    /// The three vertices' normals, in the mesh's space (w unused).
    normals: [3][4]f32,
    /// The three vertices' texture coordinates.
    uvs: [3][2]f32,
    /// Padding to the shader's layout.
    unused: [2]f32 = .{ 0, 0 },
};

/// An instance's surface, as `SceneHitInstance` in the shader.
const HitInstance = extern struct {
    const Self = @This();

    /// The normal matrix's first three columns (w unused).
    normal_matrix: [3][4]f32,
    /// The color, linear (its texture's average in when `texture` is -1), and the highlight's brightness in w.
    color: [4]f32,
    /// Where its mesh's triangles start among the bound ones.
    first_triangle: u32,
    /// The highlight's Blinn-Phong exponent.
    shininess: f32,
    /// Which bound texture it samples, -1 for none.
    texture: i32,
    /// Padding to the shader's layout.
    unused: f32 = 0,
};

/// What a reflection that meets nothing shows, as `SceneTracing` in the shader.
const Tracing = extern struct {
    const Self = @This();

    /// The sky, linear (w unused).
    sky: [4]f32,
};

/// A mesh's primitive acceleration structure and its triangles' normals.
const PrimitiveStructure = struct {
    const Self = @This();

    /// The mesh's key.
    key: u64,
    /// The `id<MTLAccelerationStructure>`, owned.
    structure: mod.Id,
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

/// An object a frame made for itself, released once that frame is surely done.
const RetiredObject = struct {
    const Self = @This();

    /// The object, owned.
    object: mod.Id,
    /// The frame it was made in.
    made_in: u64,
};

/// What one scene's frame needs for itself: its instance structure and the
/// buffers it is built and read from, used again by a later frame once this
/// one is surely done, and grown when a frame needs more.
const FrameSet = struct {
    const Self = @This();

    /// The instances' descriptors (`InstanceDescriptor`), shared, owned.
    instances: mod.Id = null,
    /// `instances`' length, in bytes.
    instances_capacity: usize = 0,
    /// The instances' surfaces (`HitInstance`), shared, owned.
    surfaces: mod.Id = null,
    /// `surfaces`' length, in bytes.
    surfaces_capacity: usize = 0,
    /// The instance acceleration structure, owned.
    structure: mod.Id = null,
    /// `structure`'s size, in bytes.
    structure_size: usize = 0,
    /// The private buffer `structure` is built with, owned.
    scratch: mod.Id = null,
    /// `scratch`'s length, in bytes.
    scratch_capacity: usize = 0,
    /// The frame that last used it.
    used_in: u64,

    /// Releases its structure and buffers.
    ///
    /// - `self`: the set.
    fn deinit(self: *Self) void {
        mod.ObjectiveC.release(self.instances);
        mod.ObjectiveC.release(self.surfaces);
        mod.ObjectiveC.release(self.structure);
        mod.ObjectiveC.release(self.scratch);
    }
};

/// What a pooled object is made as (`MetalSceneRayTracer.grown`).
const PooledKind = enum {
    const Self = @This();

    /// A buffer the CPU writes and the GPU reads, made half as large again
    /// as asked (at least `MetalSceneRayTracer.least_buffer_length`), so a
    /// growing scene seldom makes it anew.
    sharedBuffer,
    /// A buffer only the GPU uses (a build's scratch), made as large as asked.
    privateBuffer,
    /// An acceleration structure, made as large as asked.
    structure,
};

/// Metal's `MTLAccelerationStructureSizes`.
const AccelerationStructureSizes = extern struct {
    const Self = @This();

    /// `accelerationStructureSize`.
    acceleration_structure_size: usize,
    /// `buildScratchBufferSize`.
    build_scratch_buffer_size: usize,
    /// `refitScratchBufferSize`.
    refit_scratch_buffer_size: usize,
};

/// Metal's `MTLAccelerationStructureInstanceDescriptor` (the default type).
const InstanceDescriptor = extern struct {
    const Self = @This();

    /// `transformationMatrix`: a `MTLPackedFloat4x3`, four columns of three.
    transformation_matrix: [4][3]f32,
    /// `options`.
    options: u32,
    /// `mask`.
    mask: u32,
    /// `intersectionFunctionTableOffset`.
    intersection_function_table_offset: u32,
    /// `accelerationStructureIndex`.
    acceleration_structure_index: u32,
};

/// Builds and binds the acceleration structures of a scene's opaque shapes.
pub const MetalSceneRayTracer = struct {
    const Self = @This();

    /// Whether this build traces rays at all: SDL built with `MetalInterop`,
    /// on Apple silicon (the bridge returns structs larger than 16 bytes the
    /// arm64 way). Every method is a no-op without it.
    const enabled = mod.has_metal_interop and mod.cpu_arch == .aarch64;
    /// The fragment buffer slot the traced shader reads the instance
    /// structure from (`[[buffer(16)]]` in `scene_traced.metal`); the
    /// instances' surfaces, the triangles and the sky follow it.
    pub const shapes_slot = 16;
    /// The first fragment texture slot reflections sample from (`[[texture(8)]]`).
    const reflected_texture_slot = 8;
    /// How many textures reflections sample (`reflected_texture_count`).
    const reflected_texture_count = 8;
    /// The instance mask bit shadow rays test (`shadow_mask` in the shader).
    const shadow_mask: u32 = 1;
    /// The instance mask bit reflection rays test (`reflection_mask`).
    const reflection_mask: u32 = 2;
    /// Frames a primitive structure or tint outlives its last use before it
    /// is freed, as `SceneRenderer`'s meshes do.
    const idle_frames = 120;
    /// Frames a frame's own objects are kept before they are released or
    /// used again: past the frames SDL lets be in flight.
    pub const retire_frames = 4;
    /// The least a pooled buffer is made, in bytes, so small scenes never grow one.
    const least_buffer_length = 4096;
    /// The most pixels a texture's average reads, spread across it.
    const tint_samples = 65536;
    /// `MTLResourceStorageModeShared`.
    const storage_shared: usize = 0;
    /// `MTLResourceStorageModePrivate`.
    const storage_private: usize = 2 << 4;
    /// `MTLIndexTypeUInt32`.
    const index_type_uint32: usize = 1;
    /// `MTLAccelerationStructureInstanceOptionDisableTriangleCulling` and
    /// `…Opaque`: both faces meet a ray, and no intersection function runs.
    const instance_options: u32 = (1 << 0) | (1 << 2);
    /// `MTLResourceUsageRead`.
    const usage_read: usize = 1;
    /// `MTLRenderStageFragment`.
    const stage_fragment: usize = 2;

    /// Owns the lists.
    allocator: std.mem.Allocator,
    /// SDL_GPU's Metal objects.
    interop: mod.MetalInterop,
    /// The `id<MTLDevice>`, SDL's.
    device: mod.Id,
    /// The meshes' primitive structures.
    primitives: std.ArrayList(PrimitiveStructure) = .empty,
    /// The textures' average colors.
    tints: std.ArrayList(TextureTint) = .empty,
    /// What frames made for themselves, waiting to be released.
    retired: std.ArrayList(RetiredObject) = .empty,
    /// The scenes' frames' own structures and buffers, used again once done.
    sets: std.ArrayList(FrameSet) = .empty,
    /// The primitive structures this frame places, each once (`prepare`).
    placed: std.ArrayList(mod.Id) = .empty,
    /// The textures this frame's reflections sample, each once, at most `reflected_texture_count`.
    sampled: std.ArrayList(*sdl_c.SDL_GPUTexture) = .empty,
    /// The primitive structures `triangles` holds the normals of, in order.
    layout: std.ArrayList(mod.Id) = .empty,
    /// Where each of `layout`'s meshes starts in `triangles`.
    first_triangles: std.ArrayList(u32) = .empty,
    /// Every laid-out mesh's triangles, one buffer, owned; null until a frame needs it.
    triangles: mod.Id = null,
    /// This frame's instance structure, null until `prepare` builds one.
    instances: mod.Id = null,
    /// This frame's instances' surfaces, null until `prepare` makes them.
    surfaces: mod.Id = null,
    /// The frame being drawn (`nextFrame`).
    frame_number: u64 = 0,
    /// Whether a mesh's structure was built this frame, in SDL's command
    /// buffer: every instance structure this frame then follows it there,
    /// since one built ahead of the frame would run before it.
    built_this_frame: bool = false,

    /// A ray tracer on a device that supports one.
    ///
    /// - `allocator`: owns its lists.
    /// - `device`: the SDL_GPU device.
    /// - Returns: the ray tracer, or null where `supported` is false.
    pub fn init(allocator: std.mem.Allocator, device: *sdl_c.SDL_GPUDevice) ?Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        if (comptime !enabled) return null;
        if (!Self.supported(device)) return null;
        const interop = mod.MetalInterop.init(device) orelse return null;
        const self = Self{ .allocator = allocator, .interop = interop, .device = interop.metalDevice() };
        return self;
    }

    /// Releases every structure and buffer it holds, once the device is idle.
    ///
    /// - `self`: the ray tracer.
    pub fn deinit(self: *Self) void {
        if (comptime !enabled) return;
        _ = sdl_c.SDL_WaitForGPUIdle(self.interop.device);
        for (self.primitives.items) |primitive| self.releasePrimitive(primitive);
        self.primitives.deinit(self.allocator);
        self.tints.deinit(self.allocator);
        for (self.retired.items) |retired| mod.ObjectiveC.release(retired.object);
        self.retired.deinit(self.allocator);
        for (self.sets.items) |*frame_set| frame_set.deinit();
        self.sets.deinit(self.allocator);
        self.placed.deinit(self.allocator);
        self.sampled.deinit(self.allocator);
        self.layout.deinit(self.allocator);
        self.first_triangles.deinit(self.allocator);
        mod.ObjectiveC.release(self.triangles);
    }

    /// Whether a device traces a scene's rays: Apple silicon, SDL built
    /// with `MetalInterop`, the Metal driver, and a device that traces rays
    /// from a render pipeline.
    ///
    /// - `device`: an SDL_GPU device.
    /// - Returns: true when `init` makes a ray tracer for it.
    pub fn supported(device: *sdl_c.SDL_GPUDevice) bool {
        if (comptime !enabled) return false;
        const interop = mod.MetalInterop.init(device) orelse return false;
        const metal_device = interop.metalDevice();
        return Self.answers(metal_device, "supportsRaytracing") and Self.answers(metal_device, "supportsRaytracingFromRender");
    }

    /// Starts a frame: what this frame's predecessors made is released once
    /// `retire_frames` have passed, and a primitive structure, tint or frame
    /// set unused for `idle_frames` is freed.
    ///
    /// - `self`: the ray tracer.
    /// - `frame_number`: the frame now drawn (`SceneRenderer`'s count).
    pub fn nextFrame(self: *Self, frame_number: u64) void {
        if (comptime !enabled) return;
        self.frame_number = frame_number;
        self.built_this_frame = false;
        self.instances = null;
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
            mod.ObjectiveC.release(retired.object);
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
            if (self.triangles != null) self.retire(self.triangles);
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
            self.sets.items[index].deinit();
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

    /// Builds this frame's structures, outside any of SDL's passes: the
    /// primitive structure of each mesh that has none yet on SDL's command
    /// buffer (its buffers uploaded on it), the shapes' surfaces, and the
    /// instance structure placing every shape, ahead of SDL's command buffer
    /// when no mesh's structure was built this frame (see the file's header).
    ///
    /// - `self`: the ray tracer.
    /// - `arena`: the frame's arena, for the meshes built again.
    /// - `command_buffer`: the frame's command buffer, no pass open.
    /// - `shapes`: the opaque shapes, at least one.
    /// - Returns: true when the structures are ready for `bind`; false (logged) when they could not be made, so the frame draws shadow maps.
    pub fn prepare(self: *Self, arena: std.mem.Allocator, command_buffer: *sdl_c.SDL_GPUCommandBuffer, shapes: []const mod.SceneRayShape) bool {
        if (comptime !enabled) return false;
        if (shapes.len == 0) return false;
        const metal_command_buffer = self.interop.commandBuffer(command_buffer);
        if (metal_command_buffer == null) {
            log.warn("scene not ray traced: a pass is open on the command buffer", .{});
            return false;
        }
        const pool = mod.ObjectiveC.pushPool();
        defer mod.ObjectiveC.popPool(pool);

        const descriptors = arena.alloc(InstanceDescriptor, shapes.len) catch |err| return Self.notDrawn(err);
        const places = arena.alloc(u32, shapes.len) catch |err| return Self.notDrawn(err);
        var builds: mod.Id = null;
        for (shapes, descriptors, places) |shape, *descriptor, *place| {
            const structure = self.primitiveFor(arena, metal_command_buffer, &builds, shape) orelse return Self.endBuilds(builds, false);
            place.* = self.placeIndex(structure) orelse return Self.endBuilds(builds, false);
            descriptor.* = .{
                .transformation_matrix = Self.packedTransform(shape.world),
                .options = instance_options,
                .mask = reflection_mask | (if (shape.casts_shadows) shadow_mask else 0),
                .intersection_function_table_offset = 0,
                .acceleration_structure_index = place.*,
            };
        }
        // The instance structure is built in an encoder after the primitive
        // ones', so Metal orders it after them.
        _ = Self.endBuilds(builds, true);
        if (!self.layOutTriangles()) return false;
        const set_index = self.takeSet() orelse return false;
        self.surfaces = self.makeSurfaces(arena, shapes, places, set_index);
        if (self.surfaces == null) return false;
        // With no mesh structure built this frame (by this scene or an
        // earlier one), the instance structure depends on nothing SDL's
        // command buffer does: built in a command buffer of its own on SDL's
        // queue, committed now, it runs before the whole frame instead of
        // stalling the scene's pass in its middle.
        const early_command_buffer = if (!self.built_this_frame) mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.send(mod.Id, metal_command_buffer, "commandQueue", .{}), "commandBuffer", .{}) else null;
        self.instances = self.buildInstances(if (early_command_buffer != null) early_command_buffer else metal_command_buffer, descriptors, set_index);
        if (early_command_buffer != null) mod.ObjectiveC.send(void, early_command_buffer, "commit", .{});
        return self.instances != null;
    }

    /// Binds this frame's structures on the lit pass's render encoder: the
    /// instance structure at `shapes_slot` (each primitive structure it
    /// places made resident for the fragment stage), the instances' surfaces
    /// and the triangles after it, and the sky. Call after the pass begins
    /// and before it draws.
    ///
    /// - `self`: the ray tracer.
    /// - `command_buffer`: the frame's command buffer, the lit pass open on it.
    /// - `pass`: the lit pass (unused: Metal binds on its encoder).
    /// - `sky`: what a reflection that meets nothing shows, linear.
    /// - `blank`: a texture bound in the texture slots no texture fills.
    /// - `sampler`: unused: the shader samples with its own (`reflected_sampler`).
    /// - Returns: false when nothing was prepared or no render pass is open.
    pub fn bind(self: *Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer, pass: *sdl_c.SDL_GPURenderPass, sky: scenes.Vec3, blank: *sdl_c.SDL_GPUTexture, sampler: *sdl_c.SDL_GPUSampler) bool {
        _ = pass;
        _ = sampler;
        if (comptime !enabled) return false;
        if (self.instances == null or self.surfaces == null or self.triangles == null) return false;
        const encoder = self.interop.renderEncoder(command_buffer);
        if (encoder == null) return false;
        for (self.placed.items) |structure| mod.ObjectiveC.send(void, encoder, "useResource:usage:stages:", .{ structure, usage_read, stage_fragment });
        mod.ObjectiveC.send(void, encoder, "setFragmentAccelerationStructure:atBufferIndex:", .{ self.instances, @as(usize, shapes_slot) });
        mod.ObjectiveC.send(void, encoder, "setFragmentBuffer:offset:atIndex:", .{ self.surfaces, @as(usize, 0), @as(usize, shapes_slot + 1) });
        mod.ObjectiveC.send(void, encoder, "setFragmentBuffer:offset:atIndex:", .{ self.triangles, @as(usize, 0), @as(usize, shapes_slot + 2) });
        const tracing = Tracing{ .sky = .{ sky.x, sky.y, sky.z, 0 } };
        mod.ObjectiveC.send(void, encoder, "setFragmentBytes:length:atIndex:", .{ @as(*const anyopaque, &tracing), @as(usize, @sizeOf(Tracing)), @as(usize, shapes_slot + 3) });
        for (0..reflected_texture_count) |index| {
            const texture = if (index < self.sampled.items.len) self.sampled.items[index] else blank;
            mod.ObjectiveC.send(void, encoder, "setFragmentTexture:atIndex:", .{ self.interop.texture(texture), @as(usize, reflected_texture_slot + index) });
        }
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

    /// Whether an object answers a `BOOL` property with YES, false when it
    /// does not know the property.
    ///
    /// - `object`: the object.
    /// - `property`: the property's getter.
    /// - Returns: the property's value.
    fn answers(object: mod.Id, property: [*:0]const u8) bool {
        if (object == null) return false;
        if (mod.ObjectiveC.send(u8, object, "respondsToSelector:", .{mod.ObjectiveC.selectorNamed(property)}) == 0) return false;
        return mod.ObjectiveC.send(u8, object, property, .{}) != 0;
    }

    /// A mesh's primitive structure, built on `builds` (an acceleration
    /// structure encoder opened on first need), with its triangles' normals,
    /// when it has none yet.
    ///
    /// - `self`: the ray tracer.
    /// - `arena`: the frame's arena, for the mesh built again.
    /// - `metal_command_buffer`: the `id<MTLCommandBuffer>`.
    /// - `builds`: the open build encoder, or null until one is needed.
    /// - `shape`: the shape whose mesh it is.
    /// - Returns: the structure, or null when it could not be made (logged).
    fn primitiveFor(self: *Self, arena: std.mem.Allocator, metal_command_buffer: mod.Id, builds: *mod.Id, shape: mod.SceneRayShape) mod.Id {
        for (self.primitives.items) |*primitive| {
            if (primitive.key != shape.key) continue;
            primitive.used_in = self.frame_number;
            return primitive.structure;
        }
        const triangles = self.triangleNormals(arena, shape.geometry) orelse return null;
        const geometry = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("MTLAccelerationStructureTriangleGeometryDescriptor"), "descriptor", .{});
        mod.ObjectiveC.send(void, geometry, "setVertexBuffer:", .{self.interop.buffer(shape.vertex_buffer)});
        mod.ObjectiveC.send(void, geometry, "setVertexBufferOffset:", .{@as(usize, @offsetOf(scenes.SceneVertex, "position"))});
        mod.ObjectiveC.send(void, geometry, "setVertexStride:", .{@as(usize, @sizeOf(scenes.SceneVertex))});
        mod.ObjectiveC.send(void, geometry, "setIndexBuffer:", .{self.interop.buffer(shape.index_buffer)});
        mod.ObjectiveC.send(void, geometry, "setIndexType:", .{index_type_uint32});
        mod.ObjectiveC.send(void, geometry, "setTriangleCount:", .{@as(usize, shape.index_count / 3)});
        mod.ObjectiveC.send(void, geometry, "setOpaque:", .{@as(u8, 1)});
        const descriptor = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("MTLPrimitiveAccelerationStructureDescriptor"), "descriptor", .{});
        mod.ObjectiveC.send(void, descriptor, "setGeometryDescriptors:", .{Self.array(&.{geometry})});
        if (builds.* == null) builds.* = mod.ObjectiveC.send(mod.Id, metal_command_buffer, "accelerationStructureCommandEncoder", .{});
        self.built_this_frame = true;
        const structure = self.build(builds.*, descriptor) orelse {
            self.allocator.free(triangles);
            return null;
        };
        self.primitives.append(self.allocator, .{ .key = shape.key, .structure = structure, .triangles = triangles, .used_in = self.frame_number }) catch |err| {
            // Built already: released once its build is surely done.
            log.warn("ray tracing structure not kept: {s}", .{@errorName(err)});
            self.allocator.free(triangles);
            self.retire(structure);
            return null;
        };
        return structure;
    }

    /// Each triangle's vertex normals, from the mesh built again.
    ///
    /// - `self`: the ray tracer.
    /// - `arena`: the frame's arena, for the built mesh.
    /// - `geometry`: the mesh's geometry.
    /// - Returns: the normals, owned by the caller; null when the mesh could not be built (logged).
    fn triangleNormals(self: *Self, arena: std.mem.Allocator, geometry: scenes.SceneGeometry) ?[]HitTriangle {
        const data = geometry.build(arena) catch |err| {
            log.warn("ray tracing mesh not built: {s}", .{@errorName(err)});
            return null;
        };
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

    /// Ends a build encoder, if one was opened.
    ///
    /// - `builds`: the encoder, or null.
    /// - `result`: what the caller returns.
    /// - Returns: `result`.
    fn endBuilds(builds: mod.Id, result: bool) bool {
        if (builds != null) mod.ObjectiveC.send(void, builds, "endEncoding", .{});
        return result;
    }

    /// Where a primitive structure sits among those this frame places,
    /// added the first time it is placed.
    ///
    /// - `self`: the ray tracer.
    /// - `structure`: the structure.
    /// - Returns: its index, or null when it could not be added (logged).
    fn placeIndex(self: *Self, structure: mod.Id) ?u32 {
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
        if (self.triangles != null and std.mem.startsWith(mod.Id, self.layout.items, self.placed.items)) return true;
        self.layout.clearRetainingCapacity();
        self.first_triangles.clearRetainingCapacity();
        var count: usize = 0;
        for (self.placed.items) |structure| {
            self.first_triangles.append(self.allocator, @intCast(count)) catch |err| return Self.notDrawn(err);
            const primitive = self.primitiveOf(structure) orelse return false;
            count += primitive.triangles.len;
        }
        const buffer = mod.ObjectiveC.send(mod.Id, self.device, "newBufferWithLength:options:", .{ @max(count, 1) * @sizeOf(HitTriangle), storage_shared });
        if (buffer == null) {
            log.warn("scene not ray traced: no triangle buffer", .{});
            return false;
        }
        const contents: [*]HitTriangle = @ptrCast(@alignCast(mod.ObjectiveC.send(?*anyopaque, buffer, "contents", .{}).?));
        for (self.placed.items, self.first_triangles.items) |structure, first| {
            // Every placed structure was found above.
            const triangles = self.primitiveOf(structure).?.triangles;
            @memcpy(contents[first..][0..triangles.len], triangles);
        }
        if (self.triangles != null) self.retire(self.triangles);
        self.triangles = buffer;
        self.layout.appendSlice(self.allocator, self.placed.items) catch |err| {
            // Laid out but not remembered: laid out again next frame.
            self.layout.clearRetainingCapacity();
            log.warn("ray tracing layout not kept: {s}", .{@errorName(err)});
        };
        return true;
    }

    /// The kept primitive structure that is `structure`.
    ///
    /// - `self`: the ray tracer.
    /// - `structure`: a structure this frame placed.
    /// - Returns: its entry, or null when none is kept (logged).
    fn primitiveOf(self: *const Self, structure: mod.Id) ?*const PrimitiveStructure {
        for (self.primitives.items) |*primitive| if (primitive.structure == structure) return primitive;
        log.warn("scene not ray traced: a placed structure is not kept", .{});
        return null;
    }

    /// This frame's instances' surfaces, in the shapes' order, in the
    /// frame set's surface buffer.
    ///
    /// - `self`: the ray tracer.
    /// - `arena`: the frame's arena.
    /// - `shapes`: the shapes.
    /// - `places`: each shape's mesh's index among the placed ones.
    /// - `set_index`: the frame set's index (`takeSet`).
    /// - Returns: the buffer, or null when it could not be made (logged).
    fn makeSurfaces(self: *Self, arena: std.mem.Allocator, shapes: []const mod.SceneRayShape, places: []const u32, set_index: usize) mod.Id {
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
            };
        }
        const frame_set = &self.sets.items[set_index];
        return self.fill(&frame_set.surfaces, &frame_set.surfaces_capacity, std.mem.sliceAsBytes(surfaces), "surface buffer");
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

    /// Builds this frame's instance structure from its instances, in an
    /// encoder of its own, into the frame set's structure with its scratch
    /// buffer (each made larger first when this frame needs more).
    ///
    /// - `self`: the ray tracer.
    /// - `metal_command_buffer`: the `id<MTLCommandBuffer>`.
    /// - `descriptors`: one instance per shape.
    /// - `set_index`: the frame set's index (`takeSet`).
    /// - Returns: the structure, or null when it could not be made (logged).
    fn buildInstances(self: *Self, metal_command_buffer: mod.Id, descriptors: []const InstanceDescriptor, set_index: usize) mod.Id {
        const frame_set = &self.sets.items[set_index];
        const buffer = self.fill(&frame_set.instances, &frame_set.instances_capacity, std.mem.sliceAsBytes(descriptors), "instance buffer");
        if (buffer == null) return null;
        const descriptor = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("MTLInstanceAccelerationStructureDescriptor"), "descriptor", .{});
        mod.ObjectiveC.send(void, descriptor, "setInstancedAccelerationStructures:", .{Self.array(self.placed.items)});
        mod.ObjectiveC.send(void, descriptor, "setInstanceCount:", .{descriptors.len});
        mod.ObjectiveC.send(void, descriptor, "setInstanceDescriptorBuffer:", .{buffer});
        const sizes = mod.ObjectiveC.send(AccelerationStructureSizes, self.device, "accelerationStructureSizesWithDescriptor:", .{descriptor});
        if (!self.grown(&frame_set.structure, &frame_set.structure_size, sizes.acceleration_structure_size, .structure, "acceleration structure")) return null;
        if (!self.grown(&frame_set.scratch, &frame_set.scratch_capacity, sizes.build_scratch_buffer_size, .privateBuffer, "scratch buffer")) return null;
        const encoder = mod.ObjectiveC.send(mod.Id, metal_command_buffer, "accelerationStructureCommandEncoder", .{});
        if (encoder == null) {
            log.warn("scene not ray traced: no acceleration structure encoder", .{});
            return null;
        }
        mod.ObjectiveC.send(void, encoder, "buildAccelerationStructure:descriptor:scratchBuffer:scratchBufferOffset:", .{ frame_set.structure, descriptor, frame_set.scratch, @as(usize, 0) });
        mod.ObjectiveC.send(void, encoder, "endEncoding", .{});
        return frame_set.structure;
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
            return index;
        }
        self.sets.append(self.allocator, .{ .used_in = self.frame_number }) catch |err| {
            log.warn("scene not ray traced: {s}", .{@errorName(err)});
            return null;
        };
        return self.sets.items.len - 1;
    }

    /// Copies `bytes` into a pooled shared buffer, made larger first when
    /// they do not fit (`grown`).
    ///
    /// - `self`: the ray tracer.
    /// - `buffer`: the pooled buffer, null until first made.
    /// - `capacity`: its length, in bytes.
    /// - `bytes`: what it is to hold.
    /// - `what`: what it is, for the log.
    /// - Returns: the buffer, or null when it could not be made (logged).
    fn fill(self: *Self, buffer: *mod.Id, capacity: *usize, bytes: []const u8, what: []const u8) mod.Id {
        if (!self.grown(buffer, capacity, bytes.len, .sharedBuffer, what)) return null;
        const contents: [*]u8 = @ptrCast(mod.ObjectiveC.send(?*anyopaque, buffer.*, "contents", .{}).?);
        @memcpy(contents[0..bytes.len], bytes);
        return buffer.*;
    }

    /// Makes sure a pooled object holds at least `needed` bytes: kept when
    /// it does, else made anew as `kind` says, the old one retired.
    ///
    /// - `self`: the ray tracer.
    /// - `object`: the pooled object, null until first made (and after a failure).
    /// - `size`: its size, in bytes (0 while it is null).
    /// - `needed`: the least size this frame needs.
    /// - `kind`: what it is made as.
    /// - `what`: what it is, for the log.
    /// - Returns: false (logged) when it could not be made.
    fn grown(self: *Self, object: *mod.Id, size: *usize, needed: usize, kind: PooledKind, what: []const u8) bool {
        if (object.* != null and size.* >= needed) return true;
        if (object.* != null) self.retire(object.*);
        size.* = 0;
        const length = switch (kind) {
            .sharedBuffer => @max(needed +| needed / 2, least_buffer_length),
            .privateBuffer => @max(needed, 16),
            .structure => needed,
        };
        object.* = switch (kind) {
            .sharedBuffer => mod.ObjectiveC.send(mod.Id, self.device, "newBufferWithLength:options:", .{ length, storage_shared }),
            .privateBuffer => mod.ObjectiveC.send(mod.Id, self.device, "newBufferWithLength:options:", .{ length, storage_private }),
            .structure => mod.ObjectiveC.send(mod.Id, self.device, "newAccelerationStructureWithSize:", .{length}),
        };
        if (object.* == null) {
            log.warn("scene not ray traced: no {s} of {d} bytes", .{ what, length });
            return false;
        }
        size.* = length;
        return true;
    }

    /// Builds a mesh's primitive acceleration structure on an encoder, with
    /// a scratch buffer kept until the frame is surely done.
    ///
    /// - `self`: the ray tracer.
    /// - `encoder`: the open `id<MTLAccelerationStructureCommandEncoder>`.
    /// - `descriptor`: what it is built from.
    /// - Returns: the structure, owned by the caller; null when it could not be made (logged).
    fn build(self: *Self, encoder: mod.Id, descriptor: mod.Id) mod.Id {
        if (encoder == null) {
            log.warn("scene not ray traced: no acceleration structure encoder", .{});
            return null;
        }
        const sizes = mod.ObjectiveC.send(AccelerationStructureSizes, self.device, "accelerationStructureSizesWithDescriptor:", .{descriptor});
        const structure = mod.ObjectiveC.send(mod.Id, self.device, "newAccelerationStructureWithSize:", .{sizes.acceleration_structure_size});
        if (structure == null) {
            log.warn("scene not ray traced: no acceleration structure of {d} bytes", .{sizes.acceleration_structure_size});
            return null;
        }
        const scratch = mod.ObjectiveC.send(mod.Id, self.device, "newBufferWithLength:options:", .{ @max(sizes.build_scratch_buffer_size, 16), storage_private });
        if (scratch == null) {
            log.warn("scene not ray traced: no scratch buffer of {d} bytes", .{sizes.build_scratch_buffer_size});
            mod.ObjectiveC.release(structure);
            return null;
        }
        self.retire(scratch);
        mod.ObjectiveC.send(void, encoder, "buildAccelerationStructure:descriptor:scratchBuffer:scratchBufferOffset:", .{ structure, descriptor, scratch, @as(usize, 0) });
        return structure;
    }

    /// Releases a primitive structure, once any frame using it is surely
    /// done, and frees its triangles' normals.
    ///
    /// - `self`: the ray tracer.
    /// - `primitive`: the entry.
    fn releasePrimitive(self: *Self, primitive: PrimitiveStructure) void {
        mod.ObjectiveC.release(primitive.structure);
        self.allocator.free(primitive.triangles);
    }

    /// Keeps an object this frame made until `retire_frames` have passed; if
    /// it cannot be listed, waits for the device instead and releases it now.
    ///
    /// - `self`: the ray tracer.
    /// - `object`: the object, owned.
    fn retire(self: *Self, object: mod.Id) void {
        self.retired.append(self.allocator, .{ .object = object, .made_in = self.frame_number }) catch |err| {
            log.warn("ray tracing object released early: {s}", .{@errorName(err)});
            _ = sdl_c.SDL_WaitForGPUIdle(self.interop.device);
            mod.ObjectiveC.release(object);
        };
    }

    /// An autoreleased `NSArray` of objects.
    ///
    /// - `objects`: the objects.
    /// - Returns: the array.
    fn array(objects: []const mod.Id) mod.Id {
        return mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("NSArray"), "arrayWithObjects:count:", .{ @as([*]const mod.Id, objects.ptr), objects.len });
    }

    /// A column-major transform as Metal's `MTLPackedFloat4x3`: its four
    /// columns' first three rows (the last row of an affine transform is
    /// 0, 0, 0, 1).
    ///
    /// - `world`: the transform.
    /// - Returns: the packed columns.
    fn packedTransform(world: scenes.Mat4) [4][3]f32 {
        var columns: [4][3]f32 = undefined;
        for (&columns, world.columns) |*column, source| column.* = .{ source.x, source.y, source.z };
        return columns;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "the instance, surface and triangle records have the shader's layout, and a transform packs by columns" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(InstanceDescriptor));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(InstanceDescriptor, "options"));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(AccelerationStructureSizes));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(HitInstance));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(HitInstance, "first_triangle"));
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(HitTriangle));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(HitTriangle, "uvs"));
    try std.testing.expectEqual(@as(usize, 72), @offsetOf(HitInstance, "texture"));
    const moved = scenes.Mat4.translation(scenes.Vec3.init(1, 2, 3));
    const columns = MetalSceneRayTracer.packedTransform(moved);
    try std.testing.expectEqualSlices(f32, &.{ 1, 2, 3 }, &columns[3]);
    try std.testing.expectEqualSlices(f32, &.{ 1, 0, 0 }, &columns[0]);
}
