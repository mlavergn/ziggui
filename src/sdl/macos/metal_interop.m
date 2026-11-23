// SDL's Metal GPU backend, compiled with five functions that hand its Metal
// objects to ziggui (`MetalInterop`), so Metal work SDL_GPU has no API for
// (ray tracing) can run on SDL's own device and command buffers.
//
// build/sdl_build.zig compiles this file in place of the backend
// (`SdlOptions.metal_interop`). Including the backend's source, rather than
// copying its private struct layouts, keeps the accessors checked against the
// structs of the SDL release being built: a renamed field is a compile error.
//
// Every object returned is SDL's: borrowed, never retained or released here.

#include "gpu/metal/SDL_gpu_metal.m"

#ifdef SDL_GPU_METAL

// The `id<MTLDevice>` an SDL_GPU device made with the Metal driver runs on.
// The caller checks the driver first (`SDL_GetGPUDeviceDriver` is "metal").
void *ziggui_metal_device(SDL_GPUDevice *device)
{
    MetalRenderer *renderer = (MetalRenderer *)device->driverData;
    return (__bridge void *)renderer->device;
}

// The `id<MTLTexture>` behind an SDL_GPU texture of a Metal device, as it is
// now: SDL may cycle a texture onto another Metal texture when a pass begins,
// so ask again for each pass rather than keeping it.
void *ziggui_metal_texture(SDL_GPUTexture *texture)
{
    MetalTextureContainer *container = (MetalTextureContainer *)texture;
    return (__bridge void *)container->activeTexture->handle;
}

// The `id<MTLBuffer>` behind an SDL_GPU buffer of a Metal device, as it is
// now: SDL may cycle a buffer onto another Metal buffer as an upload or a
// pass begins, so ask again rather than keeping it.
void *ziggui_metal_buffer(SDL_GPUBuffer *buffer)
{
    MetalBufferContainer *container = (MetalBufferContainer *)buffer;
    return (__bridge void *)container->activeBuffer->handle;
}

// The `id<MTLRenderCommandEncoder>` of the render pass open on an SDL_GPU
// command buffer of a Metal device, or NULL when none is: to bind, between
// SDL's own calls, what its shaders read that SDL_GPU cannot bind (an
// acceleration structure at a buffer slot past SDL's).
void *ziggui_metal_render_encoder(SDL_GPUCommandBuffer *command_buffer)
{
    MetalCommandBuffer *metal = (MetalCommandBuffer *)command_buffer;
    return (__bridge void *)metal->renderEncoder;
}

// The `id<MTLCommandBuffer>` behind an SDL_GPU command buffer of a Metal
// device, or NULL while one of SDL's passes is open on it: Metal allows one
// encoder at a time, so ziggui encodes only between SDL's passes.
void *ziggui_metal_command_buffer(SDL_GPUCommandBuffer *command_buffer)
{
    MetalCommandBuffer *metal = (MetalCommandBuffer *)command_buffer;
    if (metal->renderEncoder != nil || metal->blitEncoder != nil || metal->computeEncoder != nil) {
        return NULL;
    }
    return (__bridge void *)metal->handle;
}

#endif // SDL_GPU_METAL
