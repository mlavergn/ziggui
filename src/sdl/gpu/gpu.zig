//! SDL_GPU backend: renders a `DisplayList` command list on the GPU (Metal on
//! macOS, Direct3D 12 or Vulkan on Windows, Vulkan on Linux) through
//! SDL3's GPU API, with no dependencies beyond the SDL3 the runtime already links.
//!
//! All the interesting decisions are made headlessly in
//! `renderer.GpuScene.translate` (instances, atlas packing, blur splits); this
//! file is the thin C shell that owns the device/pipelines/textures and
//! replays a translated `GpuScene`:
//!
//!   * one *unified* instanced pipeline draws every primitive kind (rounded
//!     rects, strokes, gradients, lines, glyph/image quads) in a single draw
//!     call per `Step.draw`, evaluating the same SDFs as `rasterizer.zig` in the
//!     fragment shader, with the clip stack folded into per-instance data;
//!   * `Step.blur` breaks the pass: a horizontal box-blur of the scene into a
//!     scratch texture, then a vertical-blur-plus-tint composite back: the
//!     GPU equivalent of the software `blurRect`;
//!   * glyph coverage and images live in one shelf-packed RGBA atlas texture,
//!     uploaded incrementally each frame.
//!
//! The frame is rendered into an offscreen scene texture (so blur can sample
//! it) and blitted to the swapchain. Shaders ship as committed SPIR-V blobs
//! (see shaders/compile.sh) plus MSL sources Metal compiles at runtime and
//! HLSL sources compiled at runtime to DXBC for Direct3D 12 (Windows only,
//! via the system's d3dcompiler_47.dll).
//!
//! Output matches the software rasterizer to within 1 LSB per channel, with
//! one caveat: GPU rasterizers snap vertex edges to a fixed subpixel grid
//! (typically 1/256 px), so a glyph whose origin lands within ~1/512 px of a
//! pixel-center boundary can round to the neighboring column/row where the
//! CPU's exact float compare picked the other side (<0.01% of pixels in the
//! showcase; the glyph itself stays crisp).
//!
//! Like the rest of the `sdl` module, this file is part of the SDL-linking
//! runtime and is never compiled into the core library or its test suite.

const std = @import("std");
const log = std.log.scoped(.ziggui_gpu);
const mod = @import("../module.zig");
const renderer = @import("renderer");
const scenes = @import("scenes");
const views = @import("views");
const sdl_c = @import("sdl_c");

const primitive_vertex_spirv = @embedFile("shaders/prim.vert.spv");
const primitive_fragment_spirv = @embedFile("shaders/prim.frag.spv");
const quad_vertex_spirv = @embedFile("shaders/quad.vert.spv");
const blur_horizontal_fragment_spirv = @embedFile("shaders/blur_h.frag.spv");
const blur_vertical_fragment_spirv = @embedFile("shaders/blur_v.frag.spv");
const primitive_msl = @embedFile("shaders/prim.metal");
const blur_msl = @embedFile("shaders/blur.metal");
const primitive_hlsl = @embedFile("shaders/prim.hlsl");
const blur_hlsl = @embedFile("shaders/blur.hlsl");
const scene_vertex_spirv = @embedFile("shaders/scene.vert.spv");
const scene_fragment_spirv = @embedFile("shaders/scene.frag.spv");
const scene_shadow_vertex_spirv = @embedFile("shaders/scene_shadow.vert.spv");
const scene_shadow_fragment_spirv = @embedFile("shaders/scene_shadow.frag.spv");
/// The traced fragment shader for Vulkan devices that trace rays (SPIR-V 1.5).
const scene_traced_fragment_spirv = @embedFile("shaders/scene_traced.frag.spv");
const scene_msl = @embedFile("shaders/scene.metal");
/// The lit fragment with ray-traced shadows and reflections: Metal's alone, compiled with
/// `scene.metal` before it (its `shade`), as SDL_GPU takes one source.
const scene_traced_msl = scene_msl ++ @embedFile("shaders/scene_traced.metal");
const scene_hlsl = @embedFile("shaders/scene.hlsl");
const scene_shadow_hlsl = @embedFile("shaders/scene_shadow.hlsl");

const is_windows = mod.os_tag == .windows;

/// The shader formats we can supply. SDL picks the first backend (Metal,
/// then D3D12, then Vulkan) that accepts one of them, so on Windows D3D12 is
/// preferred and Vulkan is the fallback.
const shader_formats: sdl_c.SDL_GPUShaderFormat = sdl_c.SDL_GPU_SHADERFORMAT_SPIRV |
    sdl_c.SDL_GPU_SHADERFORMAT_MSL |
    (if (is_windows) sdl_c.SDL_GPU_SHADERFORMAT_DXBC else 0);

/// ID3DBlob's vtable: only the IUnknown + buffer accessors we call. The COM
/// entry points here and in `D3DCompileFn` use the Win32 calling convention;
/// plain C elsewhere, so the (Windows-only) D3DCompile types still compile on
/// every target.
const HlslBlobVtable = extern struct {
    const Self = @This();

    QueryInterface: *const anyopaque,
    AddRef: *const fn (*HlslBlob) callconv(if (is_windows) .winapi else .c) u32,
    Release: *const fn (*HlslBlob) callconv(if (is_windows) .winapi else .c) u32,
    GetBufferPointer: *const fn (*HlslBlob) callconv(if (is_windows) .winapi else .c) [*]const u8,
    GetBufferSize: *const fn (*HlslBlob) callconv(if (is_windows) .winapi else .c) usize,
};

/// ID3DBlob: compiled shader code or compiler messages.
const HlslBlob = extern struct {
    const Self = @This();

    /// The COM vtable.
    vtbl: *const HlslBlobVtable,

    /// The blob's bytes.
    ///
    /// - `self`: the blob.
    /// - Returns: its bytes, valid while it is held.
    fn bytes(self: *Self) []const u8 {
        return self.vtbl.GetBufferPointer(self)[0..self.vtbl.GetBufferSize(self)];
    }

    /// Drops this reference.
    ///
    /// - `self`: the blob.
    fn release(self: *Self) void {
        _ = self.vtbl.Release(self);
    }
};

/// d3dcompiler_47's `D3DCompile`.
const D3DCompileFn = *const fn (
    source: [*]const u8,
    source_length: usize,
    source_name: ?[*:0]const u8,
    defines: ?*const anyopaque,
    include: ?*anyopaque,
    entry: [*:0]const u8,
    target: [*:0]const u8,
    flags1: u32,
    flags2: u32,
    code: *?*HlslBlob,
    errors: *?*HlslBlob,
) callconv(if (is_windows) .winapi else .c) i32;

/// Runtime HLSL → DXBC (shader model 5.1) compiler for SDL's Direct3D 12
/// backend: `D3DCompile` from d3dcompiler_47.dll, which ships with Windows 10+,
/// the D3D12 equivalent of Metal compiling the .metal sources at runtime.
/// Loaded dynamically so there is no import-library dependency.
const HlslCompiler = struct {
    const Self = @This();

    /// `D3DCOMPILE_OPTIMIZATION_LEVEL3`.
    const optimization_level3: u32 = 1 << 15;

    /// The loaded DLL.
    library: *sdl_c.SDL_SharedObject,

    /// Its `D3DCompile`.
    compile: D3DCompileFn,

    /// Loads d3dcompiler_47.dll.
    ///
    /// - Returns: the compiler, or null when the DLL or its entry point is missing.
    fn load() ?Self {
        const library = sdl_c.SDL_LoadObject("d3dcompiler_47.dll") orelse {
            std.log.info("ziggui: d3dcompiler_47.dll not found ({s})", .{sdl_c.SDL_GetError()});
            return null;
        };
        const function = sdl_c.SDL_LoadFunction(library, "D3DCompile") orelse {
            sdl_c.SDL_UnloadObject(library);
            return null;
        };
        return .{ .library = library, .compile = @ptrCast(@alignCast(function)) };
    }

    /// Unloads the DLL.
    ///
    /// - `self`: the compiler.
    fn unload(self: *const Self) void {
        sdl_c.SDL_UnloadObject(self.library);
    }

    /// Compiles one entry point; the caller releases the returned blob after
    /// handing its bytes to SDL (which copies them).
    ///
    /// - `self`: the compiler.
    /// - `source`: the HLSL source.
    /// - `entry`: the entry point's name.
    /// - `stage`: the shader stage it compiles for.
    /// - Returns: the compiled blob, or null when compiling failed (logged).
    fn compileEntry(self: *const Self, source: []const u8, entry: [:0]const u8, stage: sdl_c.SDL_GPUShaderStage) ?*HlslBlob {
        const target: [*:0]const u8 = if (stage == sdl_c.SDL_GPU_SHADERSTAGE_VERTEX) "vs_5_1" else "ps_5_1";
        var code: ?*HlslBlob = null;
        var errors: ?*HlslBlob = null;
        const result = self.compile(source.ptr, source.len, entry.ptr, null, null, entry.ptr, target, Self.optimization_level3, 0, &code, &errors);
        if (errors) |messages| {
            if (result < 0) std.log.err("ziggui: HLSL {s}: {s}", .{ entry, messages.bytes() });
            messages.release();
        }
        if (result < 0) {
            if (code) |blob| blob.release();
            return null;
        }
        return code;
    }
};

/// Uniform block for both blur fragment shaders; layout must match the `Blur`
/// block in blur_h.frag / blur_v.frag / blur.metal (seven float4s, std140).
const BlurUniform = extern struct {
    const Self = @This();

    region: [4]f32,
    texel_br: [4]f32,
    shape: [4]f32,
    tint: [4]f32,
    clip: [4]f32,
    clip_rounded_rect: [4]f32,
    radii: [4]f32,
};

/// Uniform block for quad.vert (blur passes).
const QuadUniform = extern struct {
    const Self = @This();

    viewport: [4]f32,
    rect: [4]f32,
};

/// One shader's sources in every format, and its resource counts.
const ShaderDescription = struct {
    const Self = @This();

    /// The SPIR-V blob.
    spirv: []const u8,
    /// The MSL source.
    msl: []const u8,
    /// The HLSL source.
    hlsl: []const u8,
    /// The entry point name, shared by the MSL and HLSL sources (SPIR-V
    /// always uses "main").
    entry: [:0]const u8,
    /// The pipeline stage.
    stage: sdl_c.SDL_GPUShaderStage,
    /// Samplers it binds.
    num_samplers: u32 = 0,
    /// Uniform buffers it binds.
    num_uniform_buffers: u32 = 0,
};

/// Encodes one frame's steps into a command buffer, opening and reusing
/// render passes on the scene texture.
const GpuEncoder = struct {
    const Self = @This();

    gpu: *Gpu,
    command_buffer: *sdl_c.SDL_GPUCommandBuffer,
    width: u32,
    height: u32,
    clear: renderer.Color,
    pass: ?*sdl_c.SDL_GPURenderPass = null,
    cleared: bool = false,

    /// The scene texture as a color target.
    ///
    /// - `self`: the encoder.
    /// - `load`: what the pass does with the texture's contents first.
    /// - Returns: the target.
    fn sceneTarget(self: *Self, load: sdl_c.SDL_GPULoadOp) sdl_c.SDL_GPUColorTargetInfo {
        return .{
            .texture = self.gpu.scene_texture,
            .clear_color = .{ .r = self.clear.r, .g = self.clear.g, .b = self.clear.b, .a = self.clear.a },
            .load_op = load,
            .store_op = sdl_c.SDL_GPU_STOREOP_STORE,
            .cycle = load == sdl_c.SDL_GPU_LOADOP_CLEAR,
        };
    }

    /// Open (or reuse) a render pass on the scene texture with the primitive
    /// pipeline fully bound. The first pass of the frame clears.
    ///
    /// - `self`: the encoder.
    /// - Returns: the pass, or null when SDL could not begin one.
    fn beginPrimitivePass(self: *Self) ?*sdl_c.SDL_GPURenderPass {
        if (self.pass) |pass| return pass;
        const load: sdl_c.SDL_GPULoadOp = if (self.cleared) sdl_c.SDL_GPU_LOADOP_LOAD else sdl_c.SDL_GPU_LOADOP_CLEAR;
        const target = self.sceneTarget(load);
        const pass = sdl_c.SDL_BeginGPURenderPass(self.command_buffer, &target, 1, null) orelse return null;
        self.cleared = true;
        self.pass = pass;
        self.bindInstanced(pass, self.gpu.primitive_pipeline);
        return pass;
    }

    /// Binds an instanced pipeline (the primitive or the erase one) with the
    /// instance buffer, the atlas and the viewport, all of which every draw
    /// of either reads.
    ///
    /// - `self`: the encoder.
    /// - `pass`: the open render pass.
    /// - `pipeline`: the pipeline to bind.
    fn bindInstanced(self: *Self, pass: *sdl_c.SDL_GPURenderPass, pipeline: *sdl_c.SDL_GPUGraphicsPipeline) void {
        sdl_c.SDL_BindGPUGraphicsPipeline(pass, pipeline);
        sdl_c.SDL_BindGPUVertexBuffers(pass, 0, &.{ .buffer = self.gpu.instance_buffer, .offset = 0 }, 1);
        sdl_c.SDL_BindGPUFragmentSamplers(pass, 0, &.{ .texture = self.gpu.atlas_texture, .sampler = self.gpu.sampler }, 1);
        const viewport = [4]f32{ @floatFromInt(self.width), @floatFromInt(self.height), 0, 0 };
        sdl_c.SDL_PushGPUVertexUniformData(self.command_buffer, 0, &viewport, @sizeOf(@TypeOf(viewport)));
    }

    /// Ends the open render pass, if any.
    ///
    /// - `self`: the encoder.
    fn endPass(self: *Self) void {
        if (self.pass) |pass| sdl_c.SDL_EndGPURenderPass(pass);
        self.pass = null;
    }

    /// Make sure the scene texture has defined contents (a frame whose
    /// first command is a blur must not sample garbage).
    ///
    /// - `self`: the encoder.
    fn ensureCleared(self: *Self) void {
        if (self.cleared) return;
        const target = self.sceneTarget(sdl_c.SDL_GPU_LOADOP_CLEAR);
        if (sdl_c.SDL_BeginGPURenderPass(self.command_buffer, &target, 1, null)) |pass| {
            sdl_c.SDL_EndGPURenderPass(pass);
            self.cleared = true;
        }
    }

    /// Draws a run of instances.
    ///
    /// - `self`: the encoder.
    /// - `first`: the run's first instance.
    /// - `count`: how many instances it holds.
    fn drawStep(self: *Self, first: u32, count: u32) void {
        const pass = self.beginPrimitivePass() orelse return;
        sdl_c.SDL_DrawGPUPrimitives(pass, 4, count, 0, first);
    }

    /// Draws a run of erase instances with the destination-out blend, then
    /// puts the primitive pipeline back for the runs after it.
    ///
    /// - `self`: the encoder.
    /// - `first`: the run's first instance.
    /// - `count`: how many instances it holds.
    fn eraseStep(self: *Self, first: u32, count: u32) void {
        const pass = self.beginPrimitivePass() orelse return;
        self.bindInstanced(pass, self.gpu.erase_pipeline);
        sdl_c.SDL_DrawGPUPrimitives(pass, 4, count, 0, first);
        self.bindInstanced(pass, self.gpu.primitive_pipeline);
    }

    /// Draws one video frame's instance from its own texture with the linear
    /// sampler, then binds the atlas again for the runs after it.
    ///
    /// - `self`: the encoder.
    /// - `first`: the frame's instance.
    /// - `texture`: the texture its picture was uploaded to.
    fn frameStep(self: *Self, first: u32, texture: ?*sdl_c.SDL_GPUTexture) void {
        const pass = self.beginPrimitivePass() orelse return;
        const sampler = self.gpu.linear_sampler orelse self.gpu.sampler;
        sdl_c.SDL_BindGPUFragmentSamplers(pass, 0, &.{ .texture = texture, .sampler = sampler }, 1);
        sdl_c.SDL_DrawGPUPrimitives(pass, 4, 1, 0, first);
        sdl_c.SDL_BindGPUFragmentSamplers(pass, 0, &.{ .texture = self.gpu.atlas_texture, .sampler = self.gpu.sampler }, 1);
    }

    /// Draws a 3D scene: the UI's pass ends, the scene renderer draws the
    /// scene into the scene texture, and the next draw opens a pass again;
    /// where the scene cannot be drawn, its placeholder is.
    ///
    /// - `self`: the encoder.
    /// - `arena`: the frame's arena.
    /// - `step`: the scene step.
    fn sceneStep(self: *Self, arena: std.mem.Allocator, step: renderer.SceneStep) void {
        self.endPass();
        self.ensureCleared();
        if (self.gpu.sceneRenderer()) |scene_renderer| if (self.gpu.scene_texture) |target| {
            if (scene_renderer.draw(arena, self.command_buffer, step, target, self.width, self.height)) return;
        };
        self.drawStep(step.placeholder.first, step.placeholder.count);
    }

    /// Blurs a region: a horizontal pass into scratch, then a vertical pass
    /// with the tint back into the scene.
    ///
    /// - `self`: the encoder.
    /// - `blur`: the step's region, radius and tint (`renderer.BlurStep`).
    fn blurStep(self: *Self, blur: anytype) void {
        self.endPass();
        self.ensureCleared();
        const float_width: f32 = @floatFromInt(self.width);
        const float_height: f32 = @floatFromInt(self.height);
        // Snapshot region: the blur rect's pixel bounds expanded by the
        // box radius, clamped to the framebuffer (rasterizer.zig's `expanded_left..expanded_bottom`).
        const box_radius = @max(1.0, @round(blur.sigma));
        const left = @max(0, @floor(blur.rect[0]) - box_radius);
        const top = @max(0, @floor(blur.rect[1]) - box_radius);
        const right = @min(float_width, @ceil(blur.rect[0] + blur.rect[2]) + box_radius);
        const bottom = @min(float_height, @ceil(blur.rect[1] + blur.rect[3]) + box_radius);
        if (right <= left or bottom <= top) return;
        var blur_uniform = BlurUniform{
            .region = .{ left, top, right, bottom },
            .texel_br = .{ 1.0 / float_width, 1.0 / float_height, box_radius, 0 },
            .shape = blur.rect,
            .tint = blur.tint,
            .clip = blur.clip,
            .clip_rounded_rect = blur.clip_rounded_rect,
            .radii = .{ blur.radius, blur.clip_radius, 0, 0 },
        };
        var quad = QuadUniform{
            .viewport = .{ float_width, float_height, 0, 0 },
            .rect = .{ left, top, right - left, bottom - top },
        };

        // Horizontal pass: scene -> scratch over the whole snapshot region.
        const scratch_target = sdl_c.SDL_GPUColorTargetInfo{
            .texture = self.gpu.scratch_texture,
            .load_op = sdl_c.SDL_GPU_LOADOP_DONT_CARE,
            .store_op = sdl_c.SDL_GPU_STOREOP_STORE,
            .cycle = true,
        };
        const horizontal_pass = sdl_c.SDL_BeginGPURenderPass(self.command_buffer, &scratch_target, 1, null) orelse return;
        sdl_c.SDL_BindGPUGraphicsPipeline(horizontal_pass, self.gpu.blur_horizontal_pipeline);
        sdl_c.SDL_BindGPUFragmentSamplers(horizontal_pass, 0, &.{ .texture = self.gpu.scene_texture, .sampler = self.gpu.sampler }, 1);
        sdl_c.SDL_PushGPUVertexUniformData(self.command_buffer, 0, &quad, @sizeOf(QuadUniform));
        sdl_c.SDL_PushGPUFragmentUniformData(self.command_buffer, 0, &blur_uniform, @sizeOf(BlurUniform));
        sdl_c.SDL_DrawGPUPrimitives(horizontal_pass, 4, 1, 0, 0);
        sdl_c.SDL_EndGPURenderPass(horizontal_pass);

        // Vertical pass + tint composite back into the scene, masked by
        // the (rounded) blur rect; pad 1px for the SDF's AA fringe.
        const vertical_target = self.sceneTarget(sdl_c.SDL_GPU_LOADOP_LOAD);
        const vertical_pass = sdl_c.SDL_BeginGPURenderPass(self.command_buffer, &vertical_target, 1, null) orelse return;
        sdl_c.SDL_BindGPUGraphicsPipeline(vertical_pass, self.gpu.blur_vertical_pipeline);
        sdl_c.SDL_BindGPUFragmentSamplers(vertical_pass, 0, &.{ .texture = self.gpu.scratch_texture, .sampler = self.gpu.sampler }, 1);
        quad.rect = .{ blur.rect[0] - 1, blur.rect[1] - 1, blur.rect[2] + 2, blur.rect[3] + 2 };
        sdl_c.SDL_PushGPUVertexUniformData(self.command_buffer, 0, &quad, @sizeOf(QuadUniform));
        sdl_c.SDL_PushGPUFragmentUniformData(self.command_buffer, 0, &blur_uniform, @sizeOf(BlurUniform));
        sdl_c.SDL_DrawGPUPrimitives(vertical_pass, 4, 1, 0, 0);
        sdl_c.SDL_EndGPURenderPass(vertical_pass);
    }
};

/// How many video frames (`DrawCommand.videoFrame`) one frame draws at most.
const max_frame_textures = 8;

/// A video frame's texture, kept while its key (its player) keeps drawing,
/// and uploaded again only for a new picture.
const FrameTexture = struct {
    const Self = @This();

    /// The pictures' key (`VideoFrameCommand.key`); 0 for a free slot.
    key: usize = 0,
    /// The texture, or null before the first picture in this slot.
    texture: ?*sdl_c.SDL_GPUTexture = null,
    /// Its width, in pixels.
    width: u32 = 0,
    /// Its height, in pixels.
    height: u32 = 0,
    /// The picture it holds (`VideoFrameCommand.generation`), while `filled`.
    generation: u64 = 0,
    /// It holds a picture: false until the first upload into this texture.
    filled: bool = false,
    /// The `Gpu.frame_counter` it was last drawn in, to free a slot no
    /// longer used.
    drawn_in_frame: u64 = 0,
    /// This frame's picture, to upload, or null when the texture holds it.
    pending: ?renderer.Image = null,
    /// `pending`'s generation, which `generation` takes once it is uploaded.
    pending_generation: u64 = 0,
};

/// A video underlay's texture, kept while its key (its player) keeps
/// drawing, and uploaded again only for a new frame.
const VideoTexture = struct {
    const Self = @This();

    /// The underlay's key; 0 for a free slot.
    key: usize = 0,
    /// The texture, sized to the frames.
    texture: ?*sdl_c.SDL_GPUTexture = null,
    /// Its width, in pixels.
    width: u32 = 0,
    /// Its height, in pixels.
    height: u32 = 0,
    /// The frame it holds (`VideoUnderlay.generation`).
    generation: u64 = 0,
    /// The frame number it was last drawn in, to free a slot no longer used.
    drawn_in_frame: u64 = 0,
};

/// The SDL_GPU device, its pipelines, and the textures and buffers a frame
/// reuses.
pub const Gpu = struct {
    const Self = @This();

    /// Straight-alpha `over`: factors chosen so dst alpha stays saturated
    /// (the scene starts from an opaque clear, like the software framebuffer).
    const over_blend = sdl_c.SDL_GPUColorTargetBlendState{
        .src_color_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
        .dst_color_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = sdl_c.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE,
        .dst_alpha_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .alpha_blend_op = sdl_c.SDL_GPU_BLENDOP_ADD,
        .color_write_mask = 0,
        .enable_blend = true,
        .enable_color_write_mask = false,
    };

    /// Destination-out: the source's alpha (a fill's coverage) cuts the scene
    /// back toward transparent, color and alpha alike, so a hole stays
    /// premultiplied for the window compositor (`DrawCommand.eraseRect`).
    const erase_blend = sdl_c.SDL_GPUColorTargetBlendState{
        .src_color_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ZERO,
        .dst_color_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .color_blend_op = sdl_c.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ZERO,
        .dst_alpha_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        .alpha_blend_op = sdl_c.SDL_GPU_BLENDOP_ADD,
        .color_write_mask = 0,
        .enable_blend = true,
        .enable_color_write_mask = false,
    };

    /// Destination-under: the source fills only what the scene left
    /// transparent (a hole a `VideoPlayer` erased), so a video frame drawn after
    /// the scene shows under its controls (`VideoUnderlay`).
    const under_blend = sdl_c.SDL_GPUColorTargetBlendState{
        .src_color_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
        .dst_color_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE,
        .color_blend_op = sdl_c.SDL_GPU_BLENDOP_ADD,
        .src_alpha_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
        .dst_alpha_blendfactor = sdl_c.SDL_GPU_BLENDFACTOR_ONE,
        .alpha_blend_op = sdl_c.SDL_GPU_BLENDOP_ADD,
        .color_write_mask = 0,
        .enable_blend = true,
        .enable_color_write_mask = false,
    };

    /// How many video frames one frame draws under the scene.
    const max_underlays = 8;

    /// Frames a video texture (a frame's or an underlay's) outlives its last
    /// draw (about two seconds at 60 frames a second) before it is freed.
    const idle_video_frames = 120;

    /// Owns the atlas and read-back buffers.
    allocator: std.mem.Allocator,

    /// The GPU device.
    device: *sdl_c.SDL_GPUDevice,

    /// Null for offscreen (screenshot) rendering.
    window: ?*sdl_c.SDL_Window,

    /// The format of every render target (swapchain format when windowed,
    /// RGBA8 offscreen); pipelines are created against it.
    target_format: sdl_c.SDL_GPUTextureFormat,

    /// The unified instanced pipeline.
    primitive_pipeline: *sdl_c.SDL_GPUGraphicsPipeline,

    /// The instanced pipeline with the erase blend.
    erase_pipeline: *sdl_c.SDL_GPUGraphicsPipeline,

    /// The horizontal blur pass.
    blur_horizontal_pipeline: *sdl_c.SDL_GPUGraphicsPipeline,

    /// The vertical blur and tint pass.
    blur_vertical_pipeline: *sdl_c.SDL_GPUGraphicsPipeline,

    /// The nearest-neighbor sampler every pass uses.
    sampler: *sdl_c.SDL_GPUSampler,

    /// The glyph and image atlas's bookkeeping.
    atlas: renderer.TextureAtlas,

    /// The atlas texture.
    atlas_texture: ?*sdl_c.SDL_GPUTexture = null,

    /// The atlas texture's size, in pixels per side.
    atlas_texture_size: u32 = 0,

    /// The offscreen scene texture.
    scene_texture: ?*sdl_c.SDL_GPUTexture = null,

    /// The blur's scratch texture.
    scratch_texture: ?*sdl_c.SDL_GPUTexture = null,

    /// The scene and scratch textures' width.
    texture_width: u32 = 0,

    /// The scene and scratch textures' height.
    texture_height: u32 = 0,

    /// The per-instance vertex buffer.
    instance_buffer: ?*sdl_c.SDL_GPUBuffer = null,

    /// The instance buffer's size, in bytes.
    instance_capacity: u32 = 0,

    /// The textures `DrawCommand.videoFrame` pictures are uploaded to, one
    /// per key (player), each kept while its key draws.
    frame_textures: [max_frame_textures]FrameTexture = @splat(.{}),

    /// This frame's `Step.frame`s' slots in `frame_textures`, in paint order;
    /// null for a picture that could not be had (it is skipped, leaving the
    /// black its `VideoPlayer` painted under it), and none past the first
    /// `max_frame_textures`.
    frame_slots: [max_frame_textures]?u8 = @splat(null),

    /// Counts uploads, for `FrameTexture.drawn_in_frame`.
    frame_counter: u64 = 0,

    /// The linear sampler video pictures are drawn with, in the surface or
    /// under it (scaled pictures look blocky with the nearest one), made on
    /// first need (`linearSampler`).
    linear_sampler: ?*sdl_c.SDL_GPUSampler = null,

    /// The upload buffer.
    transfer: ?*sdl_c.SDL_GPUTransferBuffer = null,

    /// The upload buffer's size, in bytes.
    transfer_capacity: u32 = 0,

    /// The instanced pipeline with the under blend, for video frames; null
    /// when it could not be made (the holes then stay black).
    under_pipeline: ?*sdl_c.SDL_GPUGraphicsPipeline = null,

    /// One texture per video underlay, by its key.
    video_textures: [max_underlays]VideoTexture = @splat(.{}),

    /// The underlays' instances.
    underlay_buffer: ?*sdl_c.SDL_GPUBuffer = null,

    /// The underlays' upload buffer.
    underlay_transfer: ?*sdl_c.SDL_GPUTransferBuffer = null,

    /// The underlays' upload buffer's size, in bytes.
    underlay_transfer_capacity: u32 = 0,

    /// Counts frames that drew underlays, for `VideoTexture.drawn_in_frame`.
    underlay_frame: u64 = 0,

    /// Draws 3D scenes, made on the first scene step (`sceneRenderer`).
    scene_renderer: ?mod.SceneRenderer = null,

    /// Whether the scene renderer could not be made, so it is not tried
    /// again and scene steps draw their placeholders.
    scene_renderer_failed: bool = false,

    /// Creates the device and pipelines, claiming `window`'s swapchain when
    /// given. On Windows, `ZIGGUI_D3D12_WARP` set puts Direct3D 12 on WARP, the
    /// renderer Windows runs on the CPU (`D3d12Interop`), first: a GPU device
    /// on a machine SDL_GPU cannot use the GPU of (a driver with no DXIL and
    /// no Vulkan), which draws what the software rasterizer cannot (3D
    /// scenes), and a way to try Direct3D 12 anywhere. It is never chosen on
    /// its own: on a 2015 dual-core laptop it drew the gallery's frame in
    /// 77 ms, the software rasterizer in 4.
    ///
    /// - `allocator`: owns the atlas and read-back buffers.
    /// - `window`: the window to present to, or null for offscreen rendering.
    /// - Returns: the backend, or null when no suitable GPU backend exists;
    ///   the caller falls back to the software rasterizer.
    pub fn init(allocator: std.mem.Allocator, window: ?*sdl_c.SDL_Window) ?Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
        const warp_first = mod.D3d12Interop.available and sdl_c.SDL_getenv("ZIGGUI_D3D12_WARP") != null;
        if (warp_first) if (Self.initOnWarp(allocator, window)) |gpu| return gpu;
        if (Self.initWith(allocator, window, shader_formats)) |gpu| return gpu;
        // If D3D12 was chosen but couldn't build its pipelines (say, HLSL
        // failed to compile on this machine), try again without DXBC so a
        // working Vulkan driver still gets used before the software fallback.
        if (is_windows) {
            std.log.info("ziggui: retrying the GPU backend without Direct3D 12", .{});
            return Self.initWith(allocator, window, shader_formats & ~@as(sdl_c.SDL_GPUShaderFormat, sdl_c.SDL_GPU_SHADERFORMAT_DXBC));
        }
        return null;
    }

    /// Creates the device on WARP, Direct3D 12 on the CPU, where the build
    /// can put it there (`D3d12Interop`): `ZIGGUI_D3D12_WARP`, and an app's
    /// `AppConfig.warp_fallback` once `init` found no GPU device.
    ///
    /// - `allocator`: owns the atlas and read-back buffers.
    /// - `window`: the window to present to, or null for offscreen rendering.
    /// - Returns: the backend, or null where WARP is not to be had (never
    ///   another device: only Direct3D 12 is asked for).
    pub fn initOnWarp(allocator: std.mem.Allocator, window: ?*sdl_c.SDL_Window) ?Self {
        if (!mod.D3d12Interop.available) return null;
        std.log.info("ziggui: trying Direct3D 12 on WARP (the CPU)", .{});
        mod.D3d12Interop.useWarp(true);
        defer mod.D3d12Interop.useWarp(false);
        // Direct3D's shaders only: offered SPIR-V too, SDL would fall through
        // to Vulkan on the real GPU when Direct3D 12 fails on WARP.
        return Self.initWith(allocator, window, sdl_c.SDL_GPU_SHADERFORMAT_DXBC);
    }

    /// Releases every GPU resource and the device.
    ///
    /// - `self`: the backend.
    pub fn deinit(self: *Self) void {
        const device = self.device;
        if (self.scene_renderer) |*scene_renderer| scene_renderer.deinit();
        if (self.instance_buffer) |buffer| sdl_c.SDL_ReleaseGPUBuffer(device, buffer);
        if (self.transfer) |transfer| sdl_c.SDL_ReleaseGPUTransferBuffer(device, transfer);
        if (self.atlas_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(device, texture);
        for (self.frame_textures) |frame_texture| if (frame_texture.texture) |texture| sdl_c.SDL_ReleaseGPUTexture(device, texture);
        if (self.linear_sampler) |sampler| sdl_c.SDL_ReleaseGPUSampler(device, sampler);
        if (self.scene_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(device, texture);
        if (self.scratch_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(device, texture);
        for (self.video_textures) |slot| if (slot.texture) |texture| sdl_c.SDL_ReleaseGPUTexture(device, texture);
        if (self.underlay_buffer) |buffer| sdl_c.SDL_ReleaseGPUBuffer(device, buffer);
        if (self.underlay_transfer) |transfer| sdl_c.SDL_ReleaseGPUTransferBuffer(device, transfer);
        if (self.under_pipeline) |pipeline| sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline);
        sdl_c.SDL_ReleaseGPUSampler(device, self.sampler);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.primitive_pipeline);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.erase_pipeline);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blur_horizontal_pipeline);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blur_vertical_pipeline);
        if (self.window) |window| sdl_c.SDL_ReleaseWindowFromGPUDevice(device, window);
        sdl_c.SDL_DestroyGPUDevice(device);
        self.atlas.deinit();
    }

    /// Notes this device for system reports (`views.SystemInfo`): its driver,
    /// and the GPU's name and driver version as SDL reports them.
    ///
    /// - `self`: the backend.
    pub fn noteSystem(self: *const Self) void {
        const properties = sdl_c.SDL_GetGPUDeviceProperties(self.device);
        const name = std.mem.span(sdl_c.SDL_GetStringProperty(properties, sdl_c.SDL_PROP_GPU_DEVICE_NAME_STRING, ""));
        const driver_version = std.mem.span(sdl_c.SDL_GetStringProperty(properties, sdl_c.SDL_PROP_GPU_DEVICE_DRIVER_VERSION_STRING, ""));
        views.SystemInfo.shared().noteGraphics(.gpu, self.driverName(), name, driver_version);
        self.noteRayTracing();
    }

    /// Notes for system reports (`views.SystemInfo.ray_tracing`) whether
    /// this device ray traces a scene's shadows and reflections.
    ///
    /// - `self`: the backend.
    pub fn noteRayTracing(self: *const Self) void {
        views.SystemInfo.shared().noteRayTracing(mod.SceneRayTracer.supported(self.device));
    }

    /// The name of the driver SDL chose ("metal", "vulkan", "direct3d12").
    ///
    /// - `self`: the backend.
    /// - Returns: the driver's name, "?" when SDL reports none.
    pub fn driverName(self: *const Self) []const u8 {
        const name = sdl_c.SDL_GetGPUDeviceDriver(self.device);
        return if (name != null) std.mem.span(name) else "?";
    }

    /// Renders one frame and presents it to the window swapchain.
    ///
    /// - `self`: the backend.
    /// - `arena`: the frame's arena, for the translated scene.
    /// - `commands`: the frame's draw commands, already scaled.
    /// - `clear`: the background color.
    /// - `oversample`: the supersampling factor (1 = off).
    /// - `underlays`: video frames to draw under the scene's holes.
    /// - `scale`: device pixels per point, for the underlays' rects.
    /// - Returns: false when nothing was presented (minimized swapchain, lost
    ///   device, OOM); the caller just skips the frame.
    pub fn frame(
        self: *Self,
        arena: std.mem.Allocator,
        commands: []const renderer.DrawCommand,
        clear: renderer.Color,
        oversample: f32,
        underlays: []const mod.VideoUnderlay,
        scale: f32,
    ) bool {
        const window = self.window orelse return false;
        const command_buffer = sdl_c.SDL_AcquireGPUCommandBuffer(self.device) orelse return false;
        var swapchain_texture: ?*sdl_c.SDL_GPUTexture = null;
        var swapchain_width: u32 = 0;
        var swapchain_height: u32 = 0;
        // NON-blocking acquire: when the swapchain has no image ready (all
        // frames in flight, e.g. the GPU is saturated by an AI worker's
        // compute kernels), skip this frame instead of stalling the UI thread
        // in a fence wait (SDL's Metal fence wait is a busy-spin, so the old
        // SDL_WaitAndAcquireGPUSwapchainTexture both froze input for the
        // duration of the longest kernel AND burned a core).
        if (!sdl_c.SDL_AcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, &swapchain_width, &swapchain_height) or swapchain_texture == null) {
            _ = sdl_c.SDL_CancelGPUCommandBuffer(command_buffer);
            return false;
        }
        // Supersampling: render the scene into an oversampled texture
        // (`scene_width`×`scene_height`) matching the already-scaled command
        // list, then downscale it onto the swapchain in the final blit
        // (LINEAR). `oversample` == 1 keeps the old 1:1 path exactly (NEAREST
        // blit).
        const supersample = @max(1, oversample);
        const scene_width: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(swapchain_width)) * supersample));
        const scene_height: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(swapchain_height)) * supersample));
        const scene = self.translateScene(arena, commands, @floatFromInt(scene_width), @floatFromInt(scene_height)) orelse {
            _ = sdl_c.SDL_SubmitGPUCommandBuffer(command_buffer);
            return false;
        };
        if (!self.ensureAtlasTexture() or !self.ensureFrameTextures(scene_width, scene_height) or !self.upload(command_buffer, scene)) {
            self.abandonUploads();
            _ = sdl_c.SDL_SubmitGPUCommandBuffer(command_buffer);
            return false;
        }

        self.encode(arena, command_buffer, scene, clear, scene_width, scene_height);
        if (underlays.len > 0) self.drawUnderlays(command_buffer, underlays, scale, scene_width, scene_height);

        sdl_c.SDL_BlitGPUTexture(command_buffer, &.{
            .source = .{ .texture = self.scene_texture, .w = scene_width, .h = scene_height },
            .destination = .{ .texture = swapchain_texture, .w = swapchain_width, .h = swapchain_height },
            .load_op = sdl_c.SDL_GPU_LOADOP_DONT_CARE,
            .filter = if (scene_width != swapchain_width) sdl_c.SDL_GPU_FILTER_LINEAR else sdl_c.SDL_GPU_FILTER_NEAREST,
        });
        return sdl_c.SDL_SubmitGPUCommandBuffer(command_buffer);
    }

    /// Renders `commands` offscreen and reads the pixels back. Headless
    /// verification path: lets a `--screenshot --gpu` run exercise the real
    /// GPU pipeline without a window.
    ///
    /// - `self`: the backend.
    /// - `arena`: the frame's arena, for the translated scene.
    /// - `commands`: the draw commands.
    /// - `clear`: the background color.
    /// - `width`: the image's width, in pixels.
    /// - `height`: the image's height, in pixels.
    /// - Returns: tightly-packed RGBA8 the backend's allocator owns, or null on
    ///   any GPU failure.
    pub fn renderToRgba(
        self: *Self,
        arena: std.mem.Allocator,
        commands: []const renderer.DrawCommand,
        clear: renderer.Color,
        width: u32,
        height: u32,
    ) ?[]u8 {
        self.texture_width = 0; // force texture (re)creation at the requested size
        if (!self.ensureFrameTextures(width, height)) return null;
        const scene = self.translateScene(arena, commands, @floatFromInt(width), @floatFromInt(height)) orelse return null;
        if (!self.ensureAtlasTexture()) {
            self.abandonUploads();
            return null;
        }

        const command_buffer = sdl_c.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            self.abandonUploads();
            return null;
        };
        if (!self.upload(command_buffer, scene)) {
            self.abandonUploads();
            _ = sdl_c.SDL_SubmitGPUCommandBuffer(command_buffer);
            return null;
        }
        self.encode(arena, command_buffer, scene, clear, width, height);

        const byte_count: u32 = width * height * 4;
        const download = sdl_c.SDL_CreateGPUTransferBuffer(self.device, &.{
            .usage = sdl_c.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
            .size = byte_count,
        }) orelse {
            _ = sdl_c.SDL_SubmitGPUCommandBuffer(command_buffer);
            return null;
        };
        defer sdl_c.SDL_ReleaseGPUTransferBuffer(self.device, download);
        const copy = sdl_c.SDL_BeginGPUCopyPass(command_buffer) orelse {
            _ = sdl_c.SDL_SubmitGPUCommandBuffer(command_buffer);
            return null;
        };
        sdl_c.SDL_DownloadFromGPUTexture(
            copy,
            &.{ .texture = self.scene_texture, .w = width, .h = height, .d = 1 },
            &.{ .transfer_buffer = download, .offset = 0, .pixels_per_row = width, .rows_per_layer = height },
        );
        sdl_c.SDL_EndGPUCopyPass(copy);

        const fence = sdl_c.SDL_SubmitGPUCommandBufferAndAcquireFence(command_buffer) orelse return null;
        defer sdl_c.SDL_ReleaseGPUFence(self.device, fence);
        if (!sdl_c.SDL_WaitForGPUFences(self.device, true, &fence, 1)) return null;

        const mapped: [*]const u8 = @ptrCast(sdl_c.SDL_MapGPUTransferBuffer(self.device, download, false) orelse return null);
        defer sdl_c.SDL_UnmapGPUTransferBuffer(self.device, download);
        const out = self.allocator.alloc(u8, byte_count) catch return null;
        @memcpy(out, mapped[0..byte_count]);
        return out;
    }

    /// Whether SDL's blits cannot run on `device`: a Direct3D 12 device whose
    /// driver takes no DXIL, the format SDL's own blit shaders are in.
    ///
    /// - `device`: the device.
    /// - Returns: true when `SDL_BlitGPUTexture` would find no pipeline.
    fn lacksBlits(device: *sdl_c.SDL_GPUDevice) bool {
        const driver = sdl_c.SDL_GetGPUDeviceDriver(device) orelse return false;
        if (!std.mem.eql(u8, std.mem.span(driver), "direct3d12")) return false;
        return sdl_c.SDL_GetGPUShaderFormats(device) & sdl_c.SDL_GPU_SHADERFORMAT_DXIL == 0;
    }

    /// Creates the device for `formats` and builds the pipelines.
    ///
    /// - `allocator`: allocator for the device's buffers.
    /// - `window`: the window to claim, or null offscreen.
    /// - `formats`: the shader formats the device may take.
    /// - Returns: the device, or null when SDL_GPU cannot make one (logged).
    fn initWith(allocator: std.mem.Allocator, window: ?*sdl_c.SDL_Window, formats: sdl_c.SDL_GPUShaderFormat) ?Self {
        const device = sdl_c.SDL_CreateGPUDevice(formats, false, null) orelse {
            std.log.info("ziggui: no GPU backend ({s}); using the software rasterizer", .{sdl_c.SDL_GetError()});
            return null;
        };
        // SDL's Direct3D 12 blits (the swapchain's, every frame) are DXIL
        // shaders it makes whatever the driver takes, so a driver without
        // Shader Model 6 (DXBC only: a 2015 AMD one) has no blit, and the first
        // frame fails an SDL assertion (crashes in a release build). Such a
        // device is refused, and the caller tries the next backend.
        if (is_windows and Self.lacksBlits(device)) {
            std.log.info("ziggui: Direct3D 12 here takes no DXIL, which SDL's blits need; trying another GPU backend", .{});
            sdl_c.SDL_DestroyGPUDevice(device);
            return null;
        }
        var target_format: sdl_c.SDL_GPUTextureFormat = sdl_c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
        if (window) |claimed| {
            if (!sdl_c.SDL_ClaimWindowForGPUDevice(device, claimed)) {
                std.log.info("ziggui: GPU swapchain unavailable ({s}); using the software rasterizer", .{sdl_c.SDL_GetError()});
                sdl_c.SDL_DestroyGPUDevice(device);
                return null;
            }
            target_format = sdl_c.SDL_GetGPUSwapchainTextureFormat(device, claimed);
        }

        var self = Self{
            .allocator = allocator,
            .device = device,
            .window = window,
            .target_format = target_format,
            .primitive_pipeline = undefined,
            .erase_pipeline = undefined,
            .blur_horizontal_pipeline = undefined,
            .blur_vertical_pipeline = undefined,
            .sampler = undefined,
            .atlas = renderer.TextureAtlas.init(allocator, 1024),
        };
        if (!self.createPipelines()) {
            if (window) |claimed| sdl_c.SDL_ReleaseWindowFromGPUDevice(device, claimed);
            sdl_c.SDL_DestroyGPUDevice(device);
            self.atlas.deinit();
            return null;
        }
        return self;
    }

    /// The scene renderer, made with its shaders on first need. A device
    /// that takes SPIR-V needs the scene shaders compiled (`compile.sh`);
    /// until they are, and wherever it cannot be made, scenes draw their
    /// placeholders.
    ///
    /// - `self`: the device.
    /// - Returns: the renderer, or null when it cannot be made (logged once).
    fn sceneRenderer(self: *Self) ?*mod.SceneRenderer {
        if (self.scene_renderer) |*scene_renderer| return scene_renderer;
        if (self.scene_renderer_failed) return null;
        self.scene_renderer_failed = true;
        const formats = sdl_c.SDL_GetGPUShaderFormats(self.device);
        if (formats & sdl_c.SDL_GPU_SHADERFORMAT_SPIRV != 0 and (scene_vertex_spirv.len == 0 or scene_fragment_spirv.len == 0 or scene_shadow_vertex_spirv.len == 0 or scene_shadow_fragment_spirv.len == 0)) {
            log.warn("3D scenes draw as placeholders: the scene shaders' SPIR-V is not compiled (src/sdl/gpu/shaders/compile.sh)", .{});
            return null;
        }
        const hlsl: ?HlslCompiler = if (is_windows and formats & sdl_c.SDL_GPU_SHADERFORMAT_DXBC != 0) HlslCompiler.load() else null;
        defer if (hlsl) |compiler| compiler.unload();
        const lit_vertex = self.createShader(.{ .spirv = scene_vertex_spirv, .msl = scene_msl, .hlsl = scene_hlsl, .entry = "scene_vertex", .stage = sdl_c.SDL_GPU_SHADERSTAGE_VERTEX, .num_uniform_buffers = 1 }, hlsl) orelse return Self.noSceneShader("lit vertex");
        defer sdl_c.SDL_ReleaseGPUShader(self.device, lit_vertex);
        const lit_fragment = self.createShader(.{ .spirv = scene_fragment_spirv, .msl = scene_msl, .hlsl = scene_hlsl, .entry = "scene_fragment", .stage = sdl_c.SDL_GPU_SHADERSTAGE_FRAGMENT, .num_samplers = 1 + scenes.SceneFrame.max_directional_lights, .num_uniform_buffers = 2 }, hlsl) orelse return Self.noSceneShader("lit fragment");
        defer sdl_c.SDL_ReleaseGPUShader(self.device, lit_fragment);
        const shadow_vertex = self.createShader(.{ .spirv = scene_shadow_vertex_spirv, .msl = scene_msl, .hlsl = scene_shadow_hlsl, .entry = "scene_shadow_vertex", .stage = sdl_c.SDL_GPU_SHADERSTAGE_VERTEX, .num_uniform_buffers = 1 }, hlsl) orelse return Self.noSceneShader("shadow vertex");
        defer sdl_c.SDL_ReleaseGPUShader(self.device, shadow_vertex);
        const shadow_fragment = self.createShader(.{ .spirv = scene_shadow_fragment_spirv, .msl = scene_msl, .hlsl = scene_shadow_hlsl, .entry = "scene_shadow_fragment", .stage = sdl_c.SDL_GPU_SHADERSTAGE_FRAGMENT }, hlsl) orelse return Self.noSceneShader("shadow fragment");
        defer sdl_c.SDL_ReleaseGPUShader(self.device, shadow_fragment);
        // Only where rays can be traced: Metal binds what it traces with on
        // its encoder; Vulkan hands it over in a third uniform block, with the
        // textures reflections sample in eight more sampler slots.
        const ray_tracing = mod.SceneRayTracer.supported(self.device);
        const spirv = formats & sdl_c.SDL_GPU_SHADERFORMAT_SPIRV != 0;
        const traced_fragment = if (ray_tracing) self.createShader(.{
            .spirv = scene_traced_fragment_spirv,
            .msl = scene_traced_msl,
            .hlsl = &.{},
            .entry = "scene_traced_fragment",
            .stage = sdl_c.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = if (spirv) 9 else 1,
            .num_uniform_buffers = if (spirv) 3 else 2,
        }, hlsl) else null;
        if (ray_tracing and traced_fragment == null) log.warn("scenes draw rasterized: no traced fragment shader [{s}]", .{sdl_c.SDL_GetError()});
        defer if (traced_fragment) |shader| sdl_c.SDL_ReleaseGPUShader(self.device, shader);
        self.scene_renderer = mod.SceneRenderer.init(self.allocator, self.device, self.target_format, .{
            .lit_vertex = lit_vertex,
            .lit_fragment = lit_fragment,
            .shadow_vertex = shadow_vertex,
            .shadow_fragment = shadow_fragment,
            .traced_fragment = traced_fragment,
        }) orelse return null;
        // The device traces rays, but this renderer cannot: say so, so a
        // toggle offering it greys out.
        if (ray_tracing and !self.scene_renderer.?.tracesRays()) views.SystemInfo.shared().noteRayTracing(false);
        self.scene_renderer_failed = false;
        return &self.scene_renderer.?;
    }

    /// Logs a scene shader that could not be made.
    ///
    /// - `which`: the shader.
    /// - Returns: null, for the caller to return.
    fn noSceneShader(which: []const u8) ?*mod.SceneRenderer {
        log.warn("3D scenes draw as placeholders: no {s} shader [{s}]", .{ which, sdl_c.SDL_GetError() });
        return null;
    }

    /// Creates one shader from the format the device takes.
    ///
    /// - `self`: the device.
    /// - `description`: the shader's stages, sources and resources.
    /// - `hlsl`: the HLSL compiler on Direct3D 12, else null.
    /// - Returns: the shader, or null when it could not be made (logged).
    fn createShader(self: *Self, description: ShaderDescription, hlsl: ?HlslCompiler) ?*sdl_c.SDL_GPUShader {
        const formats = sdl_c.SDL_GetGPUShaderFormats(self.device);
        var create_info = sdl_c.SDL_GPUShaderCreateInfo{
            .stage = description.stage,
            .num_samplers = description.num_samplers,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = description.num_uniform_buffers,
            .props = 0,
        };
        if (formats & sdl_c.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
            create_info.format = sdl_c.SDL_GPU_SHADERFORMAT_SPIRV;
            create_info.code = description.spirv.ptr;
            create_info.code_size = description.spirv.len;
            create_info.entrypoint = "main";
        } else if (formats & sdl_c.SDL_GPU_SHADERFORMAT_DXBC != 0) {
            const compiler = hlsl orelse return null;
            const blob = compiler.compileEntry(description.hlsl, description.entry, description.stage) orelse return null;
            defer blob.release();
            const code = blob.bytes();
            create_info.format = sdl_c.SDL_GPU_SHADERFORMAT_DXBC;
            create_info.code = code.ptr;
            create_info.code_size = code.len;
            create_info.entrypoint = description.entry.ptr;
            return sdl_c.SDL_CreateGPUShader(self.device, &create_info);
        } else {
            create_info.format = sdl_c.SDL_GPU_SHADERFORMAT_MSL;
            create_info.code = description.msl.ptr;
            create_info.code_size = description.msl.len;
            create_info.entrypoint = description.entry.ptr;
        }
        return sdl_c.SDL_CreateGPUShader(self.device, &create_info);
    }

    /// Builds the primitive and blur pipelines and the sampler.
    ///
    /// - `self`: the device.
    /// - Returns: false when any of them could not be made (logged).
    fn createPipelines(self: *Self) bool {
        const device = self.device;
        // D3D12 only: load the HLSL compiler for the duration of shader setup.
        const hlsl: ?HlslCompiler = if (is_windows and
            sdl_c.SDL_GetGPUShaderFormats(device) & sdl_c.SDL_GPU_SHADERFORMAT_DXBC != 0) HlslCompiler.load() else null;
        defer if (hlsl) |compiler| compiler.unload();
        const primitive_vertex = self.createShader(.{
            .spirv = primitive_vertex_spirv,
            .msl = primitive_msl,
            .hlsl = primitive_hlsl,
            .entry = "prim_vertex",
            .stage = sdl_c.SDL_GPU_SHADERSTAGE_VERTEX,
            .num_uniform_buffers = 1,
        }, hlsl) orelse return false;
        defer sdl_c.SDL_ReleaseGPUShader(device, primitive_vertex);
        const primitive_fragment = self.createShader(.{
            .spirv = primitive_fragment_spirv,
            .msl = primitive_msl,
            .hlsl = primitive_hlsl,
            .entry = "prim_fragment",
            .stage = sdl_c.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 1,
        }, hlsl) orelse return false;
        defer sdl_c.SDL_ReleaseGPUShader(device, primitive_fragment);
        const quad_vertex = self.createShader(.{
            .spirv = quad_vertex_spirv,
            .msl = blur_msl,
            .hlsl = blur_hlsl,
            .entry = "quad_vertex",
            .stage = sdl_c.SDL_GPU_SHADERSTAGE_VERTEX,
            .num_uniform_buffers = 1,
        }, hlsl) orelse return false;
        defer sdl_c.SDL_ReleaseGPUShader(device, quad_vertex);
        const blur_horizontal_fragment = self.createShader(.{
            .spirv = blur_horizontal_fragment_spirv,
            .msl = blur_msl,
            .hlsl = blur_hlsl,
            .entry = "blur_h_fragment",
            .stage = sdl_c.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 1,
            .num_uniform_buffers = 1,
        }, hlsl) orelse return false;
        defer sdl_c.SDL_ReleaseGPUShader(device, blur_horizontal_fragment);
        const blur_vertical_fragment = self.createShader(.{
            .spirv = blur_vertical_fragment_spirv,
            .msl = blur_msl,
            .hlsl = blur_hlsl,
            .entry = "blur_v_fragment",
            .stage = sdl_c.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 1,
            .num_uniform_buffers = 1,
        }, hlsl) orelse return false;
        defer sdl_c.SDL_ReleaseGPUShader(device, blur_vertical_fragment);

        // Nine float4 per-instance attributes; one buffer at instance rate.
        var attributes: [9]sdl_c.SDL_GPUVertexAttribute = undefined;
        for (&attributes, 0..) |*attribute, index| {
            attribute.* = .{
                .location = @intCast(index),
                .buffer_slot = 0,
                .format = sdl_c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
                .offset = @intCast(index * 16),
            };
        }
        std.debug.assert(@sizeOf(renderer.Instance) == 9 * 16);
        const vertex_buffer_description = sdl_c.SDL_GPUVertexBufferDescription{
            .slot = 0,
            .pitch = @sizeOf(renderer.Instance),
            .input_rate = sdl_c.SDL_GPU_VERTEXINPUTRATE_INSTANCE,
            .instance_step_rate = 0,
        };
        const color_target = sdl_c.SDL_GPUColorTargetDescription{
            .format = self.target_format,
            .blend_state = Self.over_blend,
        };

        var create_info = sdl_c.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = primitive_vertex,
            .fragment_shader = primitive_fragment,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &vertex_buffer_description,
                .num_vertex_buffers = 1,
                .vertex_attributes = &attributes,
                .num_vertex_attributes = attributes.len,
            },
            .primitive_type = sdl_c.SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP,
            .rasterizer_state = .{},
            .multisample_state = .{},
            .depth_stencil_state = .{},
            .target_info = .{
                .color_target_descriptions = &color_target,
                .num_color_targets = 1,
            },
            .props = 0,
        };
        self.primitive_pipeline = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse return false;
        var erase_target = color_target;
        erase_target.blend_state = Self.erase_blend;
        create_info.target_info.color_target_descriptions = &erase_target;
        self.erase_pipeline = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse {
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.primitive_pipeline);
            return false;
        };
        // Video frames draw under the scene with the same shaders (an image
        // instance sampling the frame's texture); without it the holes stay black.
        var under_target = color_target;
        under_target.blend_state = Self.under_blend;
        create_info.target_info.color_target_descriptions = &under_target;
        self.under_pipeline = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info);
        if (self.under_pipeline == null) log.warn("no underlay pipeline: video holes stay black [{s}]", .{sdl_c.SDL_GetError()});

        // Blur pipelines share the bare quad vertex shader and have no vertex
        // buffer. The horizontal pass overwrites scratch (no blending); the
        // vertical pass composites into the scene with the same `over`.
        create_info.vertex_shader = quad_vertex;
        create_info.vertex_input_state = .{};
        create_info.fragment_shader = blur_horizontal_fragment;
        var no_blend_target = color_target;
        no_blend_target.blend_state = .{};
        create_info.target_info.color_target_descriptions = &no_blend_target;
        self.blur_horizontal_pipeline = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse {
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.primitive_pipeline);
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.erase_pipeline);
            if (self.under_pipeline) |pipeline| sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline);
            self.under_pipeline = null;
            return false;
        };
        create_info.fragment_shader = blur_vertical_fragment;
        create_info.target_info.color_target_descriptions = &color_target;
        self.blur_vertical_pipeline = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse {
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.primitive_pipeline);
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.erase_pipeline);
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blur_horizontal_pipeline);
            if (self.under_pipeline) |pipeline| sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline);
            self.under_pipeline = null;
            return false;
        };

        // Nearest sampling matches the software rasterizer's glyph/image path
        // (and keeps atlas entries from bleeding).
        self.sampler = sdl_c.SDL_CreateGPUSampler(self.device, &.{
            .min_filter = sdl_c.SDL_GPU_FILTER_NEAREST,
            .mag_filter = sdl_c.SDL_GPU_FILTER_NEAREST,
            .mipmap_mode = sdl_c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
            .address_mode_u = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        }) orelse {
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.primitive_pipeline);
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.erase_pipeline);
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blur_horizontal_pipeline);
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blur_vertical_pipeline);
            if (self.under_pipeline) |pipeline| sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, pipeline);
            self.under_pipeline = null;
            return false;
        };
        return true;
    }

    /// A color-target texture the shaders can also sample.
    ///
    /// - `self`: the device.
    /// - `width`: its width, in pixels.
    /// - `height`: its height, in pixels.
    /// - `format`: its pixel format.
    /// - Returns: the texture, or null when SDL could not make it.
    fn makeTexture(self: *Self, width: u32, height: u32, format: sdl_c.SDL_GPUTextureFormat) ?*sdl_c.SDL_GPUTexture {
        return sdl_c.SDL_CreateGPUTexture(self.device, &.{
            .type = sdl_c.SDL_GPU_TEXTURETYPE_2D,
            .format = format,
            .usage = sdl_c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl_c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
        });
    }

    /// (Re)creates the scene and scratch textures at the frame's size.
    ///
    /// - `self`: the device.
    /// - `width`: the frame's width, in pixels.
    /// - `height`: the frame's height, in pixels.
    /// - Returns: false when a texture could not be made.
    fn ensureFrameTextures(self: *Self, width: u32, height: u32) bool {
        if (self.scene_texture != null and self.texture_width == width and self.texture_height == height) return true;
        if (self.scene_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(self.device, texture);
        if (self.scratch_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(self.device, texture);
        self.scene_texture = self.makeTexture(width, height, self.target_format);
        self.scratch_texture = self.makeTexture(width, height, self.target_format);
        // The size is recorded only when both exist, so a failed one is retried.
        const created = self.scene_texture != null and self.scratch_texture != null;
        self.texture_width = if (created) width else 0;
        self.texture_height = if (created) height else 0;
        return created;
    }

    /// (Re)creates the atlas texture at the atlas's size.
    ///
    /// - `self`: the device.
    /// - Returns: false when the texture could not be made.
    fn ensureAtlasTexture(self: *Self) bool {
        if (self.atlas_texture != null and self.atlas_texture_size == self.atlas.size) return true;
        if (self.atlas_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(self.device, texture);
        self.atlas_texture = sdl_c.SDL_CreateGPUTexture(self.device, &.{
            .type = sdl_c.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl_c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
            .usage = sdl_c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            .width = self.atlas.size,
            .height = self.atlas.size,
            .layer_count_or_depth = 1,
            .num_levels = 1,
        });
        self.atlas_texture_size = self.atlas.size;
        return self.atlas_texture != null;
    }

    /// Translate with atlas-full recovery: grow (or, at max size, evict) and
    /// retry; a reset invalidates the entries staged so far, so the whole
    /// command list is re-translated against the fresh atlas.
    ///
    /// - `self`: the device.
    /// - `arena`: the frame's arena, which holds the scene.
    /// - `commands`: the frame's draw commands.
    /// - `width`: the frame's width, in pixels.
    /// - `height`: the frame's height, in pixels.
    /// - Returns: the scene, or null when it could not be translated (logged).
    fn translateScene(
        self: *Self,
        arena: std.mem.Allocator,
        commands: []const renderer.DrawCommand,
        width: f32,
        height: f32,
    ) ?renderer.GpuScene {
        var attempts: u2 = 0;
        while (attempts < 3) : (attempts += 1) {
            return renderer.GpuScene.translate(arena, commands, &self.atlas, width, height) catch |err| switch (err) {
                error.AtlasFull => {
                    if (!self.atlas.grow()) self.atlas.reset();
                    continue;
                },
                error.OutOfMemory => {
                    self.abandonUploads();
                    return null;
                },
            };
        }
        return null;
    }

    /// Reset the atlas after a frame failed between translating and uploading:
    /// its staged uploads' pixels live in the frame's arena, which the next
    /// frame reuses, so every entry is placed and uploaded again.
    ///
    /// - `self`: the backend.
    fn abandonUploads(self: *Self) void {
        self.atlas.reset();
    }

    /// An atlas entry with its 1px border (`TextureAtlas.padding`), RGBA8.
    ///
    /// - `pending`: the entry.
    /// - Returns: its size in bytes, border included.
    fn paddedBytes(pending: renderer.AtlasUpload) u32 {
        return (pending.width + 2) * (pending.height + 2) * 4;
    }

    /// A video frame's pixels, RGBA8 with no row padding.
    ///
    /// - `image`: the frame.
    /// - Returns: its size in bytes, or null past what one upload can hold.
    fn frameBytes(image: renderer.Image) ?u32 {
        const bytes = image.byteLength();
        return if (bytes > std.math.maxInt(u32)) null else @intCast(bytes);
    }

    /// The slot a picture is drawn from this frame: its key's, remade when
    /// the size changed, else a free one or the one drawn longest ago, and
    /// the linear sampler made on first need. The picture is marked to upload
    /// when the slot does not hold its generation yet.
    ///
    /// - `self`: the device.
    /// - `step`: the step's picture, key and generation.
    /// - Returns: the slot's index, or null when every slot is drawn this
    ///   frame, SDL could not make the texture or the sampler, or the picture
    ///   holds fewer bytes than its size says.
    fn frameSlot(self: *Self, step: renderer.FrameStep) ?u8 {
        if (Self.frameBytes(step.image) == null or !step.image.isWhole()) return null;
        _ = self.linearSampler() orelse return null;
        var found: ?u8 = null;
        for (&self.frame_textures, 0..) |*slot, index| {
            if (slot.key == step.key) found = @intCast(index);
        }
        if (found == null) {
            // A free slot, else the one drawn longest ago, never one drawn
            // this frame.
            var oldest: u64 = std.math.maxInt(u64);
            for (&self.frame_textures, 0..) |*slot, index| {
                if (slot.drawn_in_frame == self.frame_counter and slot.key != 0) continue;
                const age = if (slot.key == 0) 0 else slot.drawn_in_frame;
                if (age < oldest) {
                    oldest = age;
                    found = @intCast(index);
                }
            }
            const chosen = found orelse return null;
            const slot = &self.frame_textures[chosen];
            slot.key = step.key;
            slot.filled = false;
        }
        const index = found.?;
        const slot = &self.frame_textures[index];
        // A second view of the same player this frame draws what the first
        // one's picture put there.
        if (slot.drawn_in_frame == self.frame_counter and slot.texture != null) return index;
        if (slot.texture == null or slot.width != step.image.width or slot.height != step.image.height) {
            if (slot.texture) |texture| sdl_c.SDL_ReleaseGPUTexture(self.device, texture);
            slot.texture = self.makeTexture(step.image.width, step.image.height, sdl_c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM);
            slot.width = step.image.width;
            slot.height = step.image.height;
            slot.filled = false;
            if (slot.texture == null) {
                slot.* = .{};
                return null;
            }
        }
        slot.drawn_in_frame = self.frame_counter;
        if (slot.pending == null and !(slot.filled and slot.generation == step.generation)) {
            slot.pending = step.image;
            slot.pending_generation = step.generation;
        }
        return index;
    }

    /// The linear, clamped sampler video pictures are drawn with, made on
    /// first need.
    ///
    /// - `self`: the device.
    /// - Returns: the sampler, or null when SDL could not make it.
    fn linearSampler(self: *Self) ?*sdl_c.SDL_GPUSampler {
        if (self.linear_sampler == null) self.linear_sampler = sdl_c.SDL_CreateGPUSampler(self.device, &.{
            .min_filter = sdl_c.SDL_GPU_FILTER_LINEAR,
            .mag_filter = sdl_c.SDL_GPU_FILTER_LINEAR,
            .mipmap_mode = sdl_c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
            .address_mode_u = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = sdl_c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        });
        return self.linear_sampler;
    }

    /// Frees the textures of video frames no longer drawn, a couple of
    /// seconds on.
    ///
    /// - `self`: the device.
    fn freeIdleFrameTextures(self: *Self) void {
        for (&self.frame_textures) |*slot| {
            if (slot.key == 0 or slot.drawn_in_frame + idle_video_frames > self.frame_counter) continue;
            if (slot.texture) |texture| sdl_c.SDL_ReleaseGPUTexture(self.device, texture);
            slot.* = .{};
        }
    }

    /// Stage instance data and pending atlas uploads through the (grown as
    /// needed) transfer buffer, recording the copy commands on `command_buffer`.
    ///
    /// - `self`: the device.
    /// - `command_buffer`: the frame's command buffer.
    /// - `scene`: the translated scene.
    /// - Returns: false when the transfer buffer could not be made or mapped.
    fn upload(self: *Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer, scene: renderer.GpuScene) bool {
        const uploads = self.atlas.pendingUploads();
        const instance_bytes: u32 = @intCast(scene.instances.len * @sizeOf(renderer.Instance));
        // Each entry goes up with its 1px border zeroed: the atlas texture's
        // contents are undefined after a reset or regrow, and glyph quads
        // sample that border, so stale pixels there drew stray lines.
        var total: u32 = instance_bytes;
        for (uploads) |pending| total += Self.paddedBytes(pending);
        // Each new video picture goes up whole, into its key's texture; one
        // its texture already holds is not uploaded again.
        self.frame_counter += 1;
        for (&self.frame_textures) |*slot| slot.pending = null;
        // A picture that cannot be had (one too many, a texture SDL refused,
        // short pixels) is skipped: the rest of the window still draws.
        var frame_count: usize = 0;
        for (scene.steps) |step| if (step == .frame) {
            if (frame_count < max_frame_textures) {
                self.frame_slots[frame_count] = self.frameSlot(step.frame);
                if (self.frame_slots[frame_count] == null) log.debug("video frame {d} skipped", .{frame_count});
            }
            frame_count += 1;
        };
        self.freeIdleFrameTextures();
        for (&self.frame_textures) |*slot| if (slot.pending) |image| {
            total = std.math.add(u32, total, Self.frameBytes(image).?) catch return false;
        };
        if (total == 0) return true;

        if (self.transfer == null or self.transfer_capacity < total) {
            if (self.transfer) |transfer| sdl_c.SDL_ReleaseGPUTransferBuffer(self.device, transfer);
            self.transfer_capacity = @max(total, @max(self.transfer_capacity * 2, 1 << 20));
            self.transfer = sdl_c.SDL_CreateGPUTransferBuffer(self.device, &.{
                .usage = sdl_c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                .size = self.transfer_capacity,
            });
            if (self.transfer == null) return false;
        }
        if (instance_bytes > 0 and (self.instance_buffer == null or self.instance_capacity < instance_bytes)) {
            if (self.instance_buffer) |buffer| sdl_c.SDL_ReleaseGPUBuffer(self.device, buffer);
            self.instance_capacity = @max(instance_bytes, @max(self.instance_capacity * 2, 1 << 19));
            self.instance_buffer = sdl_c.SDL_CreateGPUBuffer(self.device, &.{
                .usage = sdl_c.SDL_GPU_BUFFERUSAGE_VERTEX,
                .size = self.instance_capacity,
            });
            if (self.instance_buffer == null) return false;
        }

        const mapped: [*]u8 = @ptrCast(sdl_c.SDL_MapGPUTransferBuffer(self.device, self.transfer, true) orelse return false);
        if (instance_bytes > 0) @memcpy(mapped[0..instance_bytes], std.mem.sliceAsBytes(scene.instances));
        var offset: u32 = instance_bytes;
        for (uploads) |pending| {
            const size = Self.paddedBytes(pending);
            const destination = mapped[offset..][0..size];
            @memset(destination, 0);
            const row = (pending.width + 2) * 4;
            for (0..pending.height) |y| @memcpy(destination[(y + 1) * row + 4 ..][0 .. pending.width * 4], pending.pixels[y * pending.width * 4 ..][0 .. pending.width * 4]);
            offset += size;
        }
        const frames_offset = offset;
        for (&self.frame_textures) |*slot| if (slot.pending) |image| {
            const size = Self.frameBytes(image).?;
            @memcpy(mapped[offset..][0..size], image.pixels[0..size]);
            offset += size;
        };
        sdl_c.SDL_UnmapGPUTransferBuffer(self.device, self.transfer);

        const copy = sdl_c.SDL_BeginGPUCopyPass(command_buffer) orelse return false;
        if (instance_bytes > 0) {
            sdl_c.SDL_UploadToGPUBuffer(
                copy,
                &.{ .transfer_buffer = self.transfer, .offset = 0 },
                &.{ .buffer = self.instance_buffer, .offset = 0, .size = instance_bytes },
                true,
            );
        }
        offset = instance_bytes;
        for (uploads) |pending| {
            sdl_c.SDL_UploadToGPUTexture(
                copy,
                &.{ .transfer_buffer = self.transfer, .offset = offset, .pixels_per_row = pending.width + 2, .rows_per_layer = pending.height + 2 },
                &.{ .texture = self.atlas_texture, .x = pending.x - 1, .y = pending.y - 1, .w = pending.width + 2, .h = pending.height + 2, .d = 1 },
                false, // preserve the rest of the atlas
            );
            offset += Self.paddedBytes(pending);
        }
        offset = frames_offset;
        for (&self.frame_textures) |*slot| if (slot.pending) |image| {
            sdl_c.SDL_UploadToGPUTexture(
                copy,
                &.{ .transfer_buffer = self.transfer, .offset = offset, .pixels_per_row = image.width, .rows_per_layer = image.height },
                &.{ .texture = slot.texture, .w = image.width, .h = image.height, .d = 1 },
                true,
            );
            offset += Self.frameBytes(image).?;
            slot.generation = slot.pending_generation;
            slot.filled = true;
            slot.pending = null;
        };
        sdl_c.SDL_EndGPUCopyPass(copy);
        self.atlas.clearPending();
        return true;
    }

    /// Draws video frames under what the scene left transparent: each frame's
    /// picture, then black over the rest of its view's frame, with the under
    /// blend, so the controls painted over a `VideoPlayer` stay on top. A
    /// frame's texture is uploaded only when its generation changed.
    ///
    /// - `self`: the device.
    /// - `command_buffer`: the frame's command buffer, after the scene's passes.
    /// - `underlays`: the frames and where they go, in points.
    /// - `scale`: device pixels per point.
    /// - `width`: the scene's width, in pixels.
    /// - `height`: the scene's height, in pixels.
    fn drawUnderlays(self: *Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer, underlays: []const mod.VideoUnderlay, scale: f32, width: u32, height: u32) void {
        const pipeline = self.under_pipeline orelse return;
        const video_sampler = self.linearSampler() orelse return;
        const count: usize = @min(underlays.len, max_underlays);
        self.underlay_frame += 1;

        // Two instances per frame (its picture, then black), and the slots
        // whose texture takes a new frame.
        var instances: [max_underlays * 2]renderer.Instance = undefined;
        var slots: [max_underlays]?*VideoTexture = @splat(null);
        var uploads: [max_underlays]bool = @splat(false);
        const viewport = [4]f32{ 0, 0, @floatFromInt(width), @floatFromInt(height) };
        var upload_bytes: u32 = 0;
        for (underlays[0..count], 0..) |underlay, index| {
            const has_frame = underlay.hasPicture();
            if (has_frame) slots[index] = self.videoTexture(underlay.key, underlay.width, underlay.height);
            if (slots[index]) |slot| {
                slot.drawn_in_frame = self.underlay_frame;
                if (slot.generation != underlay.generation) {
                    uploads[index] = true;
                    upload_bytes += underlay.width * underlay.height * 4;
                }
            }
            instances[index * 2] = Self.underlayInstance(.image, Self.scaledRect(underlay.picture, scale), .{ 1, 1, 1, 1 }, viewport);
            instances[index * 2 + 1] = Self.underlayInstance(.fill, Self.scaledRect(underlay.frame, scale), .{ 0, 0, 0, 1 }, viewport);
        }
        self.freeIdleVideoTextures();

        const instance_bytes: u32 = @intCast(count * 2 * @sizeOf(renderer.Instance));
        const total = instance_bytes + upload_bytes;
        if (self.underlay_buffer == null) {
            self.underlay_buffer = sdl_c.SDL_CreateGPUBuffer(self.device, &.{
                .usage = sdl_c.SDL_GPU_BUFFERUSAGE_VERTEX,
                .size = max_underlays * 2 * @sizeOf(renderer.Instance),
            });
        }
        if (self.underlay_transfer == null or self.underlay_transfer_capacity < total) {
            if (self.underlay_transfer) |transfer| sdl_c.SDL_ReleaseGPUTransferBuffer(self.device, transfer);
            self.underlay_transfer_capacity = @max(total, self.underlay_transfer_capacity * 2);
            self.underlay_transfer = sdl_c.SDL_CreateGPUTransferBuffer(self.device, &.{
                .usage = sdl_c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                .size = self.underlay_transfer_capacity,
            });
        }
        const buffer = self.underlay_buffer orelse return;
        const transfer = self.underlay_transfer orelse {
            self.underlay_transfer_capacity = 0;
            return;
        };
        const mapped: [*]u8 = @ptrCast(sdl_c.SDL_MapGPUTransferBuffer(self.device, transfer, true) orelse return);
        @memcpy(mapped[0..instance_bytes], std.mem.sliceAsBytes(instances[0 .. count * 2]));
        var offset: u32 = instance_bytes;
        for (underlays[0..count], 0..) |underlay, index| {
            if (!uploads[index]) continue;
            const size = underlay.width * underlay.height * 4;
            @memcpy(mapped[offset..][0..size], underlay.pixels[0..size]);
            offset += size;
        }
        sdl_c.SDL_UnmapGPUTransferBuffer(self.device, transfer);

        const copy = sdl_c.SDL_BeginGPUCopyPass(command_buffer) orelse return;
        sdl_c.SDL_UploadToGPUBuffer(copy, &.{ .transfer_buffer = transfer, .offset = 0 }, &.{ .buffer = buffer, .offset = 0, .size = instance_bytes }, true);
        offset = instance_bytes;
        for (underlays[0..count], 0..) |underlay, index| {
            if (!uploads[index]) continue;
            const slot = slots[index].?;
            sdl_c.SDL_UploadToGPUTexture(
                copy,
                &.{ .transfer_buffer = transfer, .offset = offset, .pixels_per_row = underlay.width, .rows_per_layer = underlay.height },
                &.{ .texture = slot.texture, .w = underlay.width, .h = underlay.height, .d = 1 },
                true,
            );
            slot.generation = underlay.generation;
            offset += underlay.width * underlay.height * 4;
        }
        sdl_c.SDL_EndGPUCopyPass(copy);

        const target = sdl_c.SDL_GPUColorTargetInfo{
            .texture = self.scene_texture,
            .load_op = sdl_c.SDL_GPU_LOADOP_LOAD,
            .store_op = sdl_c.SDL_GPU_STOREOP_STORE,
        };
        const pass = sdl_c.SDL_BeginGPURenderPass(command_buffer, &target, 1, null) orelse return;
        defer sdl_c.SDL_EndGPURenderPass(pass);
        sdl_c.SDL_BindGPUGraphicsPipeline(pass, pipeline);
        sdl_c.SDL_BindGPUVertexBuffers(pass, 0, &.{ .buffer = buffer, .offset = 0 }, 1);
        const size = [4]f32{ @floatFromInt(width), @floatFromInt(height), 0, 0 };
        sdl_c.SDL_PushGPUVertexUniformData(command_buffer, 0, &size, @sizeOf(@TypeOf(size)));
        for (0..count) |index| {
            const first: u32 = @intCast(index * 2);
            if (slots[index]) |slot| {
                sdl_c.SDL_BindGPUFragmentSamplers(pass, 0, &.{ .texture = slot.texture, .sampler = video_sampler }, 1);
                sdl_c.SDL_DrawGPUPrimitives(pass, 4, 1, 0, first);
            }
            // The black fill samples nothing, but a texture must be bound.
            sdl_c.SDL_BindGPUFragmentSamplers(pass, 0, &.{ .texture = self.atlas_texture, .sampler = self.sampler }, 1);
            sdl_c.SDL_DrawGPUPrimitives(pass, 4, 1, 0, first + 1);
        }
    }

    /// The texture slot for a video underlay's key at a frame size: its own,
    /// remade when the size changed, or a free one.
    ///
    /// - `self`: the device.
    /// - `key`: the underlay's key.
    /// - `width`: the frame's width, in pixels.
    /// - `height`: the frame's height.
    /// - Returns: the slot, or null when every slot is taken or SDL refused.
    fn videoTexture(self: *Self, key: usize, width: u32, height: u32) ?*VideoTexture {
        var found: ?*VideoTexture = null;
        for (&self.video_textures) |*slot| {
            if (slot.key == key) found = slot;
        }
        if (found == null) for (&self.video_textures) |*slot| {
            if (slot.key == 0) {
                found = slot;
                break;
            }
        };
        const slot = found orelse return null;
        if (slot.texture != null and slot.key == key and slot.width == width and slot.height == height) return slot;
        if (slot.texture) |texture| sdl_c.SDL_ReleaseGPUTexture(self.device, texture);
        slot.* = .{ .key = key, .width = width, .height = height };
        // BGRA, as the decoders hand frames over: no pass swaps the bytes. The
        // under blend weighs the picture by the scene's alpha, never its own,
        // so the fourth byte is ignored.
        slot.texture = sdl_c.SDL_CreateGPUTexture(self.device, &.{
            .type = sdl_c.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl_c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
            .usage = sdl_c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            .width = width,
            .height = height,
            .layer_count_or_depth = 1,
            .num_levels = 1,
        });
        if (slot.texture == null) {
            slot.* = .{};
            return null;
        }
        return slot;
    }

    /// Frees the textures of underlays no longer drawn, a couple of seconds on.
    ///
    /// - `self`: the device.
    fn freeIdleVideoTextures(self: *Self) void {
        for (&self.video_textures) |*slot| {
            if (slot.key == 0 or slot.drawn_in_frame + idle_video_frames > self.underlay_frame) continue;
            if (slot.texture) |texture| sdl_c.SDL_ReleaseGPUTexture(self.device, texture);
            slot.* = .{};
        }
    }

    /// An instance the primitive shaders draw unclipped: an image (the whole
    /// bound texture) or a plain fill.
    ///
    /// - `kind`: what the instance draws.
    /// - `rect`: where, in pixels.
    /// - `color`: the fill's color (an image ignores it).
    /// - `viewport`: the whole scene, as the clip.
    /// - Returns: the instance.
    fn underlayInstance(kind: renderer.InstanceKind, rect: renderer.Rect, color: [4]f32, viewport: [4]f32) renderer.Instance {
        const box = [4]f32{ rect.x, rect.y, rect.width, rect.height };
        return .{
            .quad = box,
            .shape = box,
            .color0 = color,
            .color1 = color,
            .points = @splat(0),
            .atlas_rect = .{ 0, 0, 1, 1 },
            .clip = viewport,
            .clip_rounded_rect = @splat(0),
            .parameters = .{ @floatFromInt(@backingInt(kind)), 0, 0, 0 },
        };
    }

    /// A rect in points, in device pixels.
    ///
    /// - `rect`: the rect, in points.
    /// - `scale`: device pixels per point.
    /// - Returns: the rect, in pixels.
    fn scaledRect(rect: renderer.Rect, scale: f32) renderer.Rect {
        return .{ .x = rect.x * scale, .y = rect.y * scale, .width = rect.width * scale, .height = rect.height * scale };
    }

    /// Encode a translated scene into `command_buffer`, rendering into the
    /// scene texture (cleared to `clear` on first use).
    ///
    /// - `self`: the device.
    /// - `arena`: the frame's arena, for the 3D scenes it draws.
    /// - `command_buffer`: the frame's command buffer.
    /// - `scene`: the translated scene.
    /// - `clear`: the color the scene texture starts as.
    /// - `width`: the frame's width, in pixels.
    /// - `height`: the frame's height, in pixels.
    fn encode(
        self: *Self,
        arena: std.mem.Allocator,
        command_buffer: *sdl_c.SDL_GPUCommandBuffer,
        scene: renderer.GpuScene,
        clear: renderer.Color,
        width: u32,
        height: u32,
    ) void {
        var encoder = GpuEncoder{ .gpu = self, .command_buffer = command_buffer, .width = width, .height = height, .clear = clear };
        if (self.scene_renderer) |*scene_renderer| scene_renderer.nextFrame();
        var frame_index: usize = 0;
        for (scene.steps) |step| {
            switch (step) {
                .draw => |draw| encoder.drawStep(draw.first, draw.count),
                .blur => |blur| encoder.blurStep(blur),
                .erase => |erase| encoder.eraseStep(erase.first, erase.count),
                .frame => |picture| {
                    if (frame_index < max_frame_textures) if (self.frame_slots[frame_index]) |slot| {
                        encoder.frameStep(picture.first, self.frame_textures[slot].texture);
                    };
                    frame_index += 1;
                },
                .scene => |scene_step| encoder.sceneStep(arena, scene_step),
            }
        }
        encoder.endPass();
        encoder.ensureCleared(); // empty command list still presents the bg color
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "gpu: an erase cuts a premultiplied transparent hole, and a later fill composites over it" {
    if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
    defer sdl_c.SDL_Quit();
    var gpu = Gpu.init(std.testing.allocator, null) orelse return error.SkipZigTest;
    defer gpu.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const commands = [_]renderer.DrawCommand{
        .{ .eraseRect = .{ .rect = .{ .x = 8, .y = 8, .width = 16, .height = 16 } } },
        .{ .fillRoundedRect = .{ .rect = .{ .x = 8, .y = 20, .width = 16, .height = 4 }, .color = renderer.Color.black.withAlpha(0.5) } },
    };
    const pixels = gpu.renderToRgba(arena.allocator(), &commands, renderer.Color.white, 32, 32) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(pixels);
    const hole = pixels[(12 * 32 + 12) * 4 ..][0..4];
    const scrim = pixels[(22 * 32 + 12) * 4 ..][0..4];
    const outside = pixels[(2 * 32 + 2) * 4 ..][0..4];
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, hole);
    try std.testing.expect(scrim[3] >= 126 and scrim[3] <= 129 and scrim[0] <= 1); // premultiplied black at half alpha
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, outside);
}

test "gpu: a video frame draws from its key's texture, uploaded again only for a new generation" {
    if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
    defer sdl_c.SDL_Quit();
    var gpu = Gpu.init(std.testing.allocator, null) orelse return error.SkipZigTest;
    defer gpu.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // One buffer, as a player keeps: each new frame rewrites it in place.
    var pixels = [_]u8{ 255, 0, 0, 255, 0, 255, 0, 255 };
    const image = renderer.Image{ .width = 2, .height = 1, .pixels = &pixels };
    const rect = renderer.Rect{ .x = 0, .y = 0, .width = 32, .height = 32 };
    const first_commands = [_]renderer.DrawCommand{.{ .videoFrame = .{ .rect = rect, .image = image, .key = 1, .generation = 1 } }};
    const first = gpu.renderToRgba(arena.allocator(), &first_commands, renderer.Color.white, 32, 32) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(first);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, first[(16 * 32 + 2) * 4 ..][0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, first[(16 * 32 + 29) * 4 ..][0..4]);
    // A new generation goes up.
    pixels = .{ 0, 0, 255, 255, 0, 0, 255, 255 };
    const second_commands = [_]renderer.DrawCommand{.{ .videoFrame = .{ .rect = rect, .image = image, .key = 1, .generation = 2 } }};
    const second = gpu.renderToRgba(arena.allocator(), &second_commands, renderer.Color.white, 32, 32) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, second[(16 * 32 + 2) * 4 ..][0..4]);
    // The same generation is not uploaded again: the texture keeps its picture.
    pixels = .{ 255, 255, 255, 255, 255, 255, 255, 255 };
    const third = gpu.renderToRgba(arena.allocator(), &second_commands, renderer.Color.white, 32, 32) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(third);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, third[(16 * 32 + 2) * 4 ..][0..4]);
}

test "gpu: past the textures a frame can hold, a video frame is skipped, not the window" {
    if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
    defer sdl_c.SDL_Quit();
    var gpu = Gpu.init(std.testing.allocator, null) orelse return error.SkipZigTest;
    defer gpu.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const red = [4]u8{ 255, 0, 0, 255 };
    const image = renderer.Image{ .width = 1, .height = 1, .pixels = &red };
    // One more player than there are textures, each 4 px wide, side by side.
    var commands: [max_frame_textures + 1]renderer.DrawCommand = undefined;
    for (&commands, 0..) |*command, index| {
        const x: f32 = @floatFromInt(index * 4);
        command.* = .{ .videoFrame = .{ .rect = .{ .x = x, .y = 0, .width = 4, .height = 4 }, .image = image, .key = index + 1, .generation = 1 } };
    }
    const width: u32 = (max_frame_textures + 1) * 4;
    const pixels = gpu.renderToRgba(arena.allocator(), &commands, renderer.Color.white, width, 4) orelse return error.SkipZigTest;
    defer std.testing.allocator.free(pixels);
    // The first eight draw; the ninth leaves the background.
    try std.testing.expectEqualSlices(u8, &red, pixels[(2 * width + 2) * 4 ..][0..4]);
    try std.testing.expectEqualSlices(u8, &red, pixels[(2 * width + (max_frame_textures - 1) * 4 + 2) * 4 ..][0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, pixels[(2 * width + max_frame_textures * 4 + 2) * 4 ..][0..4]);
}
