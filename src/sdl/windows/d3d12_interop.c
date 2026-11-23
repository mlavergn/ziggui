// SDL's Direct3D 12 GPU backend, compiled so ziggui can put it on WARP, the
// Direct3D 12 renderer Windows runs on the CPU (`D3d12Interop`): a machine
// whose GPU driver SDL_GPU cannot use (one with no DXIL, which SDL's blits
// need) still gets a GPU device, which draws what the software rasterizer
// cannot (3D scenes) and runs the same pipeline as a real GPU.
//
// SDL takes its adapter in two places, both through the first adapter DXGI
// lists (by GPU preference, or plainly on an older DXGI). While ziggui asks
// for WARP (`ziggui_d3d12_use_warp`), each gets WARP's adapter instead; else
// each gets what DXGI lists, as SDL asked.
//
// build/sdl_build.zig compiles this file in place of the backend
// (`SdlOptions.d3d12_interop`). Including the backend's source keeps it the
// release's own: only the three adapter calls are redirected.

#include "SDL_internal.h"

#ifdef SDL_GPU_D3D12

// The DXGI declarations the backend uses (COM's C macros included), declared
// first so the three macros below replace theirs.
#include "video/directx/SDL_d3d12.h"

static HRESULT ziggui_adapter_by_preference(IDXGIFactory6 *factory, UINT index, DXGI_GPU_PREFERENCE preference, REFIID interface_id, void **adapter);
static HRESULT ziggui_adapters1(IDXGIFactory1 *factory, UINT index, IDXGIAdapter1 **adapter);
#undef IDXGIFactory6_EnumAdapterByGpuPreference
#define IDXGIFactory6_EnumAdapterByGpuPreference(factory, index, preference, interface_id, adapter) ziggui_adapter_by_preference(factory, index, preference, interface_id, adapter)
#undef IDXGIFactory1_EnumAdapters1
#define IDXGIFactory1_EnumAdapters1(factory, index, adapter) ziggui_adapters1(factory, index, adapter)
#undef IDXGIFactory4_EnumAdapters1
#define IDXGIFactory4_EnumAdapters1(factory, index, adapter) ziggui_adapters1((IDXGIFactory1 *)(factory), index, adapter)

#endif // SDL_GPU_D3D12

#include "gpu/d3d12/SDL_gpu_d3d12.c"

#ifdef SDL_GPU_D3D12

// Whether SDL's next device goes on WARP.
static bool ziggui_d3d12_warp = false;

// WARP's adapter, as the interface asked for.
static HRESULT ziggui_warp_adapter(IUnknown *factory, REFIID interface_id, void **adapter)
{
    IDXGIFactory4 *factory4 = NULL;
    HRESULT result = factory->lpVtbl->QueryInterface(factory, D3D_GUID(D3D_IID_IDXGIFactory4), (void **)&factory4);
    if (FAILED(result)) {
        return result;
    }
    result = factory4->lpVtbl->EnumWarpAdapter(factory4, interface_id, adapter);
    factory4->lpVtbl->Release(factory4);
    return result;
}

// SDL's adapter by GPU preference: WARP's while asked for (it is the only one
// then), else DXGI's.
static HRESULT ziggui_adapter_by_preference(IDXGIFactory6 *factory, UINT index, DXGI_GPU_PREFERENCE preference, REFIID interface_id, void **adapter)
{
    if (ziggui_d3d12_warp) {
        return index == 0 ? ziggui_warp_adapter((IUnknown *)factory, interface_id, adapter) : DXGI_ERROR_NOT_FOUND;
    }
    return factory->lpVtbl->EnumAdapterByGpuPreference(factory, index, preference, interface_id, adapter);
}

// SDL's adapter on a DXGI older than 1.6: WARP's while asked for, else DXGI's.
static HRESULT ziggui_adapters1(IDXGIFactory1 *factory, UINT index, IDXGIAdapter1 **adapter)
{
    if (ziggui_d3d12_warp) {
        return index == 0 ? ziggui_warp_adapter((IUnknown *)factory, D3D_GUID(D3D_IID_IDXGIAdapter1), (void **)adapter) : DXGI_ERROR_NOT_FOUND;
    }
    return factory->lpVtbl->EnumAdapters1(factory, index, adapter);
}

// Puts SDL's next Direct3D 12 devices on WARP (true) or the GPU DXGI lists
// first (false, as SDL does alone). Read as SDL makes a device; a device
// already made keeps its adapter.
void ziggui_d3d12_use_warp(bool warp)
{
    ziggui_d3d12_warp = warp;
}

#endif // SDL_GPU_D3D12
