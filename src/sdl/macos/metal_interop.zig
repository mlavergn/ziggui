//! SDL_GPU's Metal objects, for Metal work SDL_GPU has no API for (ray
//! tracing): the `id<MTLDevice>` a device runs on, the `id<MTLTexture>` and
//! `id<MTLBuffer>` behind a texture and a buffer, the `id<MTLCommandBuffer>`
//! behind a command buffer and the render encoder of the pass open on it, so
//! that work runs on SDL's own device and is ordered with SDL's passes on
//! SDL's own command buffer. The functions come from `metal_interop.m`, which SDL's
//! build compiles in place of its Metal backend (`SdlOptions.metal_interop`);
//! a prebuilt SDL (`-Dsdl3-prefix`) lacks them, and `init` then returns null.
//! Every object is SDL's, borrowed: never retain one past the pass it is for,
//! nor release one. macOS only: other targets reach it only behind
//! `os_tag == .macos`.

const std = @import("std");
const log = std.log.scoped(.ziggui_metal_interop);
const mod = @import("module.zig");
const sdl_c = @import("sdl_c");

/// An SDL_GPU device on the Metal driver, whose Metal objects it hands out.
pub const MetalInterop = struct {
    const Self = @This();

    extern fn ziggui_metal_device(device: *sdl_c.SDL_GPUDevice) mod.Id;
    extern fn ziggui_metal_texture(texture: *sdl_c.SDL_GPUTexture) mod.Id;
    extern fn ziggui_metal_buffer(buffer: *sdl_c.SDL_GPUBuffer) mod.Id;
    extern fn ziggui_metal_render_encoder(command_buffer: *sdl_c.SDL_GPUCommandBuffer) mod.Id;
    extern fn ziggui_metal_command_buffer(command_buffer: *sdl_c.SDL_GPUCommandBuffer) mod.Id;

    /// The SDL_GPU device.
    device: *sdl_c.SDL_GPUDevice,

    /// The interop for `device`, or null when SDL was built without
    /// `metal_interop.m` or the device runs on another driver.
    ///
    /// - `device`: an SDL_GPU device.
    /// - Returns: the interop, or null.
    pub fn init(device: *sdl_c.SDL_GPUDevice) ?Self {
        if (comptime !mod.has_metal_interop) return null;
        const driver = sdl_c.SDL_GetGPUDeviceDriver(device) orelse return null;
        if (!std.mem.eql(u8, std.mem.span(driver), "metal")) return null;
        const self = Self{ .device = device };
        return self;
    }

    /// The `id<MTLDevice>` the device runs on.
    ///
    /// - `self`: the interop.
    /// - Returns: the Metal device, SDL's.
    pub fn metalDevice(self: *const Self) mod.Id {
        if (comptime !mod.has_metal_interop) return null;
        return ziggui_metal_device(self.device);
    }

    /// The `id<MTLTexture>` behind one of the device's textures, as it is
    /// now: SDL may cycle a texture onto another Metal texture as a pass
    /// begins, so ask again for each pass rather than keeping it.
    ///
    /// - `self`: the interop.
    /// - `sdl_texture`: a texture made on the device.
    /// - Returns: the Metal texture, SDL's.
    pub fn texture(self: *const Self, sdl_texture: *sdl_c.SDL_GPUTexture) mod.Id {
        _ = self;
        if (comptime !mod.has_metal_interop) return null;
        return ziggui_metal_texture(sdl_texture);
    }

    /// The `id<MTLBuffer>` behind one of the device's buffers, as it is now:
    /// SDL may cycle a buffer onto another Metal buffer as an upload or a pass
    /// begins, so ask again rather than keeping it.
    ///
    /// - `self`: the interop.
    /// - `sdl_buffer`: a buffer made on the device.
    /// - Returns: the Metal buffer, SDL's.
    pub fn buffer(self: *const Self, sdl_buffer: *sdl_c.SDL_GPUBuffer) mod.Id {
        _ = self;
        if (comptime !mod.has_metal_interop) return null;
        return ziggui_metal_buffer(sdl_buffer);
    }

    /// The `id<MTLRenderCommandEncoder>` of the render pass open on one of
    /// the device's command buffers, to bind what SDL_GPU cannot (an
    /// acceleration structure at a buffer slot past those SDL binds). SDL
    /// rebinds only the slots its shaders declare, so a binding at a slot past
    /// them holds for the pass.
    ///
    /// - `self`: the interop.
    /// - `command_buffer`: a command buffer acquired from the device.
    /// - Returns: the render encoder, SDL's; nil when no render pass is open.
    pub fn renderEncoder(self: *const Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer) mod.Id {
        _ = self;
        if (comptime !mod.has_metal_interop) return null;
        return ziggui_metal_render_encoder(command_buffer);
    }

    /// The `id<MTLCommandBuffer>` behind one of the device's command buffers,
    /// to encode on between SDL's passes (Metal allows one encoder at a time).
    /// End every encoder made on it before SDL begins its next pass.
    ///
    /// - `self`: the interop.
    /// - `command_buffer`: a command buffer acquired from the device.
    /// - Returns: the Metal command buffer, SDL's; nil while one of SDL's passes is open on it.
    pub fn commandBuffer(self: *const Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer) mod.Id {
        _ = self;
        if (comptime !mod.has_metal_interop) return null;
        return ziggui_metal_command_buffer(command_buffer);
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
    // Nothing here does I/O to trace.
    _ = log;
}

test "a Metal pass encoded on SDL's command buffer between SDL's passes is ordered with them" {
    // A Metal render pass that clears an SDL_GPU texture, encoded through
    // the Objective-C runtime on SDL's command buffer.
    const MetalClear = struct {
        const Self = @This();

        /// Metal's `MTLClearColor`.
        const ClearColor = extern struct {
            const Self = @This();

            /// `red`.
            red: f64,
            /// `green`.
            green: f64,
            /// `blue`.
            blue: f64,
            /// `alpha`.
            alpha: f64,
        };

        /// `MTLLoadActionClear`.
        const load_action_clear: usize = 2;
        /// `MTLStoreActionStore`.
        const store_action_store: usize = 1;

        /// Encodes a render pass on `command_buffer` that clears `target` to `color`.
        ///
        /// - `command_buffer`: an `id<MTLCommandBuffer>` with no encoder open.
        /// - `target`: the `id<MTLTexture>` to clear, a render target.
        /// - `color`: the color to clear it to.
        /// - Returns: false when Metal made no encoder.
        fn encode(command_buffer: mod.Id, target: mod.Id, color: ClearColor) bool {
            const pool = mod.ObjectiveC.pushPool();
            defer mod.ObjectiveC.popPool(pool);
            const descriptor = mod.ObjectiveC.send(mod.Id, mod.ObjectiveC.class("MTLRenderPassDescriptor"), "renderPassDescriptor", .{});
            const attachments = mod.ObjectiveC.send(mod.Id, descriptor, "colorAttachments", .{});
            const attachment = mod.ObjectiveC.send(mod.Id, attachments, "objectAtIndexedSubscript:", .{@as(usize, 0)});
            mod.ObjectiveC.send(void, attachment, "setTexture:", .{target});
            mod.ObjectiveC.send(void, attachment, "setLoadAction:", .{load_action_clear});
            mod.ObjectiveC.send(void, attachment, "setStoreAction:", .{store_action_store});
            mod.ObjectiveC.send(void, attachment, "setClearColor:", .{color});
            const encoder = mod.ObjectiveC.send(mod.Id, command_buffer, "renderCommandEncoderWithDescriptor:", .{descriptor});
            if (encoder == null) return false;
            mod.ObjectiveC.send(void, encoder, "endEncoding", .{});
            return true;
        }
    };

    if (!mod.has_metal_interop) return error.SkipZigTest;
    if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
    defer sdl_c.SDL_Quit();
    const device = sdl_c.SDL_CreateGPUDevice(sdl_c.SDL_GPU_SHADERFORMAT_MSL, false, null) orelse return error.SkipZigTest;
    defer sdl_c.SDL_DestroyGPUDevice(device);
    const interop = MetalInterop.init(device) orelse return error.TestUnexpectedResult;
    try std.testing.expect(interop.metalDevice() != null);

    const side = 4;
    const target = sdl_c.SDL_CreateGPUTexture(device, &.{
        .type = sdl_c.SDL_GPU_TEXTURETYPE_2D,
        .format = sdl_c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl_c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
        .width = side,
        .height = side,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    }) orelse return error.TestUnexpectedResult;
    defer sdl_c.SDL_ReleaseGPUTexture(device, target);
    const download = sdl_c.SDL_CreateGPUTransferBuffer(device, &.{
        .usage = sdl_c.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
        .size = side * side * 4,
    }) orelse return error.TestUnexpectedResult;
    defer sdl_c.SDL_ReleaseGPUTransferBuffer(device, download);

    const command_buffer = sdl_c.SDL_AcquireGPUCommandBuffer(device) orelse return error.TestUnexpectedResult;
    // SDL clears the texture red, and while its pass is open there is no
    // Metal command buffer to encode on.
    const red_pass = sdl_c.SDL_BeginGPURenderPass(command_buffer, &.{
        .texture = target,
        .clear_color = .{ .r = 1, .g = 0, .b = 0, .a = 1 },
        .load_op = sdl_c.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl_c.SDL_GPU_STOREOP_STORE,
    }, 1, null) orelse return error.TestUnexpectedResult;
    try std.testing.expect(interop.commandBuffer(command_buffer) == null);
    sdl_c.SDL_EndGPURenderPass(red_pass);
    // Metal clears it green on SDL's command buffer, after SDL's pass.
    const metal_command_buffer = interop.commandBuffer(command_buffer);
    try std.testing.expect(metal_command_buffer != null);
    try std.testing.expect(MetalClear.encode(metal_command_buffer, interop.texture(target), .{ .red = 0, .green = 1, .blue = 0, .alpha = 1 }));
    // SDL reads it back after Metal's pass.
    const copy = sdl_c.SDL_BeginGPUCopyPass(command_buffer) orelse return error.TestUnexpectedResult;
    sdl_c.SDL_DownloadFromGPUTexture(
        copy,
        &.{ .texture = target, .w = side, .h = side, .d = 1 },
        &.{ .transfer_buffer = download, .offset = 0, .pixels_per_row = side, .rows_per_layer = side },
    );
    sdl_c.SDL_EndGPUCopyPass(copy);
    const fence = sdl_c.SDL_SubmitGPUCommandBufferAndAcquireFence(command_buffer) orelse return error.TestUnexpectedResult;
    defer sdl_c.SDL_ReleaseGPUFence(device, fence);
    try std.testing.expect(sdl_c.SDL_WaitForGPUFences(device, true, &fence, 1));

    const mapped: [*]const u8 = @ptrCast(sdl_c.SDL_MapGPUTransferBuffer(device, download, false) orelse return error.TestUnexpectedResult);
    defer sdl_c.SDL_UnmapGPUTransferBuffer(device, download);
    for (0..side * side) |pixel| try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, mapped[pixel * 4 ..][0..4]);
}
