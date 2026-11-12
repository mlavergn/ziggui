//! SDL_GPU backend: renders a `Canvas` command list on the GPU (Metal on
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
    fn bytes(self: *Self) []const u8 {
        return self.vtbl.GetBufferPointer(self)[0..self.vtbl.GetBufferSize(self)];
    }

    /// Drops this reference.
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
    fn unload(self: *const Self) void {
        sdl_c.SDL_UnloadObject(self.library);
    }

    /// Compiles one entry point; the caller releases the returned blob after
    /// handing its bytes to SDL (which copies them).
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
    fn beginPrimitivePass(self: *Self) ?*sdl_c.SDL_GPURenderPass {
        if (self.pass) |pass| return pass;
        const load: sdl_c.SDL_GPULoadOp = if (self.cleared) sdl_c.SDL_GPU_LOADOP_LOAD else sdl_c.SDL_GPU_LOADOP_CLEAR;
        const target = self.sceneTarget(load);
        const pass = sdl_c.SDL_BeginGPURenderPass(self.command_buffer, &target, 1, null) orelse return null;
        self.cleared = true;
        self.pass = pass;
        sdl_c.SDL_BindGPUGraphicsPipeline(pass, self.gpu.primitive_pipeline);
        sdl_c.SDL_BindGPUVertexBuffers(pass, 0, &.{ .buffer = self.gpu.instance_buffer, .offset = 0 }, 1);
        sdl_c.SDL_BindGPUFragmentSamplers(pass, 0, &.{ .texture = self.gpu.atlas_texture, .sampler = self.gpu.sampler }, 1);
        const viewport = [4]f32{ @floatFromInt(self.width), @floatFromInt(self.height), 0, 0 };
        sdl_c.SDL_PushGPUVertexUniformData(self.command_buffer, 0, &viewport, @sizeOf(@TypeOf(viewport)));
        return pass;
    }

    /// Ends the open render pass, if any.
    fn endPass(self: *Self) void {
        if (self.pass) |pass| sdl_c.SDL_EndGPURenderPass(pass);
        self.pass = null;
    }

    /// Make sure the scene texture has defined contents (a frame whose
    /// first command is a blur must not sample garbage).
    fn ensureCleared(self: *Self) void {
        if (self.cleared) return;
        const target = self.sceneTarget(sdl_c.SDL_GPU_LOADOP_CLEAR);
        if (sdl_c.SDL_BeginGPURenderPass(self.command_buffer, &target, 1, null)) |pass| {
            sdl_c.SDL_EndGPURenderPass(pass);
            self.cleared = true;
        }
    }

    /// Draws a run of instances.
    fn drawStep(self: *Self, first: u32, count: u32) void {
        const pass = self.beginPrimitivePass() orelse return;
        sdl_c.SDL_DrawGPUPrimitives(pass, 4, count, 0, first);
    }

    /// Blurs a region: a horizontal pass into scratch, then a vertical pass
    /// with the tint back into the scene.
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

    /// The upload buffer.
    transfer: ?*sdl_c.SDL_GPUTransferBuffer = null,

    /// The upload buffer's size, in bytes.
    transfer_capacity: u32 = 0,

    /// Creates the device and pipelines, claiming `window`'s swapchain when
    /// given.
    ///
    /// - `allocator`: owns the atlas and read-back buffers.
    /// - `window`: the window to present to, or null for offscreen rendering.
    /// - Returns: the backend, or null when no suitable GPU backend exists;
    ///   the caller falls back to the software rasterizer.
    pub fn init(allocator: std.mem.Allocator, window: ?*sdl_c.SDL_Window) ?Self {
        log.debug("{s}:{d} :: {s}", .{ @src().file, @src().line, @src().fn_name });
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

    /// Releases every GPU resource and the device.
    ///
    /// - `self`: the backend.
    pub fn deinit(self: *Self) void {
        const device = self.device;
        if (self.instance_buffer) |buffer| sdl_c.SDL_ReleaseGPUBuffer(device, buffer);
        if (self.transfer) |transfer| sdl_c.SDL_ReleaseGPUTransferBuffer(device, transfer);
        if (self.atlas_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(device, texture);
        if (self.scene_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(device, texture);
        if (self.scratch_texture) |texture| sdl_c.SDL_ReleaseGPUTexture(device, texture);
        sdl_c.SDL_ReleaseGPUSampler(device, self.sampler);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.primitive_pipeline);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blur_horizontal_pipeline);
        sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blur_vertical_pipeline);
        if (self.window) |window| sdl_c.SDL_ReleaseWindowFromGPUDevice(device, window);
        sdl_c.SDL_DestroyGPUDevice(device);
        self.atlas.deinit();
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
    /// - Returns: false when nothing was presented (minimized swapchain, lost
    ///   device, OOM); the caller just skips the frame.
    pub fn frame(
        self: *Self,
        arena: std.mem.Allocator,
        commands: []const renderer.DrawCommand,
        clear: renderer.Color,
        oversample: f32,
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

        self.encode(command_buffer, scene, clear, scene_width, scene_height);

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
        self.encode(command_buffer, scene, clear, width, height);

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

    /// Creates the device for `formats` and builds the pipelines.
    fn initWith(allocator: std.mem.Allocator, window: ?*sdl_c.SDL_Window, formats: sdl_c.SDL_GPUShaderFormat) ?Self {
        const device = sdl_c.SDL_CreateGPUDevice(formats, false, null) orelse {
            std.log.info("ziggui: no GPU backend ({s}); using the software rasterizer", .{sdl_c.SDL_GetError()});
            return null;
        };
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

    /// Creates one shader from the format the device takes.
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
            return false;
        };
        create_info.fragment_shader = blur_vertical_fragment;
        create_info.target_info.color_target_descriptions = &color_target;
        self.blur_vertical_pipeline = sdl_c.SDL_CreateGPUGraphicsPipeline(device, &create_info) orelse {
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.primitive_pipeline);
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blur_horizontal_pipeline);
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
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blur_horizontal_pipeline);
            sdl_c.SDL_ReleaseGPUGraphicsPipeline(device, self.blur_vertical_pipeline);
            return false;
        };
        return true;
    }

    /// A color-target texture the shaders can also sample.
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
    fn paddedBytes(pending: renderer.AtlasUpload) u32 {
        return (pending.width + 2) * (pending.height + 2) * 4;
    }

    /// Stage instance data and pending atlas uploads through the (grown as
    /// needed) transfer buffer, recording the copy commands on `command_buffer`.
    fn upload(self: *Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer, scene: renderer.GpuScene) bool {
        const uploads = self.atlas.pendingUploads();
        const instance_bytes: u32 = @intCast(scene.instances.len * @sizeOf(renderer.Instance));
        // Each entry goes up with its 1px border zeroed: the atlas texture's
        // contents are undefined after a reset or regrow, and glyph quads
        // sample that border, so stale pixels there drew stray lines.
        var total: u32 = instance_bytes;
        for (uploads) |pending| total += Self.paddedBytes(pending);
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
        sdl_c.SDL_EndGPUCopyPass(copy);
        self.atlas.clearPending();
        return true;
    }

    /// Encode a translated scene into `command_buffer`, rendering into the
    /// scene texture (cleared to `clear` on first use).
    fn encode(
        self: *Self,
        command_buffer: *sdl_c.SDL_GPUCommandBuffer,
        scene: renderer.GpuScene,
        clear: renderer.Color,
        width: u32,
        height: u32,
    ) void {
        var encoder = GpuEncoder{ .gpu = self, .command_buffer = command_buffer, .width = width, .height = height, .clear = clear };
        for (scene.steps) |step| {
            switch (step) {
                .draw => |draw| encoder.drawStep(draw.first, draw.count),
                .blur => |blur| encoder.blurStep(blur),
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
