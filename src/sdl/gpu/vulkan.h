// The Vulkan API for `VulkanInterop` and `VulkanSceneRayTracer`, translated
// as the `vulkan_c` module: the headers SDL bundles, with no prototypes (every
// function is reached through SDL's device, `VulkanInterop.load`).
//
// build.zig defines ZIGGUI_VULKAN_HEADERS and adds the headers' folder only
// where SDL is built with `vulkan_interop.c` (Windows and Linux, from the
// release); elsewhere the module is empty and nothing reads it.

#ifdef ZIGGUI_VULKAN_HEADERS
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan_core.h>
#endif
