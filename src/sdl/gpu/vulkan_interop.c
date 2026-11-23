// SDL's Vulkan GPU backend, compiled so ziggui can trace rays on SDL's own
// device (`VulkanInterop`, `VulkanSceneRayTracer`), which SDL_GPU has no API
// for. It does two things:
//
// - It makes the devices that can trace rays able to: SDL is handed a
//   `vkGetInstanceProcAddr` of ours, which wraps two functions. Our
//   `vkCreateInstance` asks for Vulkan 1.2 where the loader has it (SDL asks
//   for 1.0, which hides what ray tracing needs). Our `vkCreateDevice`, on a
//   Vulkan 1.2 device with ray queries, acceleration structures and buffer
//   device addresses, adds their extensions and switches their features on.
//   A device without them, or one that refuses them, is created exactly as
//   SDL asked, so no GPU loses Vulkan for this.
// - It hands ziggui SDL's Vulkan objects (device, functions, the command
//   buffer between passes), all borrowed, never destroyed here.
//
// build/sdl_build.zig compiles this file in place of the backend
// (`SdlOptions.vulkan_interop`). Including the backend's source, rather than
// copying its private struct layouts, keeps the accessors checked against
// the structs of the SDL release being built: a renamed field is a compile
// error.

#include "SDL_internal.h"

#ifdef SDL_GPU_VULKAN

// The real function declared first, under the name SDL's dynamic API gives
// it (its include guard keeps the backend from declaring it again, renamed).
#include <SDL3/SDL_vulkan.h>

// The backend asks SDL for the loader's `vkGetInstanceProcAddr`; it gets ours.
// (With SDL's dynamic API the name is a macro for the `_REAL` function, which
// SDL_internal.h has defined by now.)
static SDL_FunctionPointer ziggui_vulkan_instance_loader(void);
#undef SDL_Vulkan_GetVkGetInstanceProcAddr
#define SDL_Vulkan_GetVkGetInstanceProcAddr ziggui_vulkan_instance_loader

#endif // SDL_GPU_VULKAN

#include "gpu/vulkan/SDL_gpu_vulkan.c"

#ifdef SDL_GPU_VULKAN

#undef SDL_Vulkan_GetVkGetInstanceProcAddr
#if SDL_DYNAMIC_API
#define SDL_Vulkan_GetVkGetInstanceProcAddr SDL_Vulkan_GetVkGetInstanceProcAddr_REAL
#endif

// The device extensions ray queries need on a Vulkan 1.2 device (the rest
// they depend on are core in 1.2).
static const char *const ziggui_ray_extensions[] = {
    VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME,
    VK_KHR_RAY_QUERY_EXTENSION_NAME,
    VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME,
};
#define ZIGGUI_RAY_EXTENSION_COUNT (sizeof(ziggui_ray_extensions) / sizeof(ziggui_ray_extensions[0]))

// The loader's `vkGetInstanceProcAddr`, which ours wraps.
static PFN_vkGetInstanceProcAddr ziggui_loader_instance_proc = NULL;
// The loader's `vkCreateInstance` and the instance's `vkCreateDevice`.
static PFN_vkCreateInstance ziggui_loader_create_instance = NULL;
static PFN_vkCreateDevice ziggui_loader_create_device = NULL;
// The last instance made, and the API version it was made for.
static VkInstance ziggui_last_instance = VK_NULL_HANDLE;
static Uint32 ziggui_last_instance_version = 0;
// The instance whose `vkCreateDevice` was asked for last (SDL's, as it
// makes its device).
static VkInstance ziggui_device_instance = VK_NULL_HANDLE;
// The last device made, when it was made able to trace rays.
static VkDevice ziggui_traced_device = VK_NULL_HANDLE;

// Our `vkCreateInstance`: SDL's request, for Vulkan 1.2 when the loader has
// it and SDL asked for less.
static VkResult VKAPI_CALL ziggui_create_instance(const VkInstanceCreateInfo *info, const VkAllocationCallbacks *allocator, VkInstance *instance)
{
    VkInstanceCreateInfo raised = *info;
    VkApplicationInfo application;
    Uint32 version = info->pApplicationInfo ? info->pApplicationInfo->apiVersion : VK_API_VERSION_1_0;
    Uint32 loader_version = VK_API_VERSION_1_0;
    PFN_vkEnumerateInstanceVersion enumerate = (PFN_vkEnumerateInstanceVersion)ziggui_loader_instance_proc(VK_NULL_HANDLE, "vkEnumerateInstanceVersion");
    VkResult result;
    if (enumerate != NULL && enumerate(&loader_version) != VK_SUCCESS) {
        loader_version = VK_API_VERSION_1_0;
    }
    if (info->pApplicationInfo != NULL && loader_version >= VK_API_VERSION_1_2 && version < VK_API_VERSION_1_2) {
        application = *info->pApplicationInfo;
        application.apiVersion = VK_API_VERSION_1_2;
        raised.pApplicationInfo = &application;
        result = ziggui_loader_create_instance(&raised, allocator, instance);
        if (result == VK_SUCCESS) {
            ziggui_last_instance = *instance;
            ziggui_last_instance_version = VK_API_VERSION_1_2;
            return result;
        }
    }
    result = ziggui_loader_create_instance(info, allocator, instance);
    if (result == VK_SUCCESS) {
        ziggui_last_instance = *instance;
        ziggui_last_instance_version = version;
    }
    return result;
}

// Whether `physical` can trace rays from a fragment shader with what our
// `vkCreateDevice` switches on: Vulkan 1.2 (instance and device), the ray
// extensions, and the acceleration structure, ray query and buffer device
// address features.
static bool ziggui_device_traces_rays(VkPhysicalDevice physical)
{
    VkInstance instance = ziggui_device_instance;
    PFN_vkGetPhysicalDeviceProperties properties_of;
    PFN_vkEnumerateDeviceExtensionProperties extensions_of;
    PFN_vkGetPhysicalDeviceFeatures2 features_of;
    VkPhysicalDeviceProperties properties;
    VkExtensionProperties *extensions;
    Uint32 extension_count = 0;
    Uint32 found = 0;
    VkPhysicalDeviceBufferDeviceAddressFeatures address = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES };
    VkPhysicalDeviceRayQueryFeaturesKHR query = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR };
    VkPhysicalDeviceAccelerationStructureFeaturesKHR structures = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR };
    VkPhysicalDeviceFeatures2 features = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2 };

    if (instance == VK_NULL_HANDLE || instance != ziggui_last_instance || ziggui_last_instance_version < VK_API_VERSION_1_2) {
        return false;
    }
    properties_of = (PFN_vkGetPhysicalDeviceProperties)ziggui_loader_instance_proc(instance, "vkGetPhysicalDeviceProperties");
    extensions_of = (PFN_vkEnumerateDeviceExtensionProperties)ziggui_loader_instance_proc(instance, "vkEnumerateDeviceExtensionProperties");
    features_of = (PFN_vkGetPhysicalDeviceFeatures2)ziggui_loader_instance_proc(instance, "vkGetPhysicalDeviceFeatures2");
    if (properties_of == NULL || extensions_of == NULL || features_of == NULL) {
        return false;
    }
    properties_of(physical, &properties);
    if (properties.apiVersion < VK_API_VERSION_1_2) {
        return false;
    }
    if (extensions_of(physical, NULL, &extension_count, NULL) != VK_SUCCESS || extension_count == 0) {
        return false;
    }
    extensions = SDL_malloc(sizeof(VkExtensionProperties) * extension_count);
    if (extensions == NULL) {
        return false;
    }
    if (extensions_of(physical, NULL, &extension_count, extensions) == VK_SUCCESS) {
        for (Uint32 wanted = 0; wanted < ZIGGUI_RAY_EXTENSION_COUNT; wanted++) {
            for (Uint32 index = 0; index < extension_count; index++) {
                if (SDL_strcmp(extensions[index].extensionName, ziggui_ray_extensions[wanted]) == 0) {
                    found++;
                    break;
                }
            }
        }
    }
    SDL_free(extensions);
    if (found != ZIGGUI_RAY_EXTENSION_COUNT) {
        return false;
    }
    features.pNext = &structures;
    structures.pNext = &query;
    query.pNext = &address;
    features_of(physical, &features);
    return structures.accelerationStructure && query.rayQuery && address.bufferDeviceAddress;
}

// Our `vkCreateDevice`: on a device that can trace rays, SDL's request with
// the ray extensions and features added; else (or when that fails) SDL's
// request as it is.
static VkResult VKAPI_CALL ziggui_create_device(VkPhysicalDevice physical, const VkDeviceCreateInfo *info, const VkAllocationCallbacks *allocator, VkDevice *device)
{
    const char *extensions[128];
    Uint32 extension_count = 0;
    VkDeviceCreateInfo extended = *info;
    VkPhysicalDeviceBufferDeviceAddressFeatures address = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES };
    VkPhysicalDeviceRayQueryFeaturesKHR query = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR };
    VkPhysicalDeviceAccelerationStructureFeaturesKHR structures = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR };
    bool address_chained = false;
    // SDL's own feature structures we switch buffer device addresses on in,
    // and what they held, put back once the device is made (or refused), so
    // the fallback is SDL's request exactly and SDL's structures stay its own.
    VkBool32 *switched[2] = { NULL, NULL };
    VkBool32 switched_from[2] = { VK_FALSE, VK_FALSE };
    Uint32 switched_count = 0;
    VkResult result;

    ziggui_traced_device = VK_NULL_HANDLE;
    if (!ziggui_device_traces_rays(physical) || info->enabledExtensionCount + ZIGGUI_RAY_EXTENSION_COUNT > SDL_arraysize(extensions)) {
        return ziggui_loader_create_device(physical, info, allocator, device);
    }

    // SDL's extensions, then those of ours it did not ask for.
    for (Uint32 index = 0; index < info->enabledExtensionCount; index++) {
        extensions[extension_count++] = info->ppEnabledExtensionNames[index];
    }
    for (Uint32 wanted = 0; wanted < ZIGGUI_RAY_EXTENSION_COUNT; wanted++) {
        bool asked = false;
        for (Uint32 index = 0; index < info->enabledExtensionCount; index++) {
            asked = asked || SDL_strcmp(info->ppEnabledExtensionNames[index], ziggui_ray_extensions[wanted]) == 0;
        }
        if (!asked) {
            extensions[extension_count++] = ziggui_ray_extensions[wanted];
        }
    }

    // Buffer device addresses on in whichever structure SDL's chain already
    // has for them (one may not appear twice), else in one of ours.
    for (VkBaseOutStructure *link = (VkBaseOutStructure *)info->pNext; link != NULL; link = link->pNext) {
        VkBool32 *flag = NULL;
        if (link->sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES) {
            flag = &((VkPhysicalDeviceVulkan12Features *)link)->bufferDeviceAddress;
        } else if (link->sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES) {
            flag = &((VkPhysicalDeviceBufferDeviceAddressFeatures *)link)->bufferDeviceAddress;
        }
        if (flag != NULL && switched_count < SDL_arraysize(switched)) {
            switched[switched_count] = flag;
            switched_from[switched_count] = *flag;
            switched_count++;
            *flag = VK_TRUE;
            address_chained = true;
        }
    }
    structures.accelerationStructure = VK_TRUE;
    query.rayQuery = VK_TRUE;
    address.bufferDeviceAddress = VK_TRUE;
    structures.pNext = &query;
    if (address_chained) {
        query.pNext = (void *)info->pNext;
    } else {
        query.pNext = &address;
        address.pNext = (void *)info->pNext;
    }
    extended.pNext = &structures;
    extended.enabledExtensionCount = extension_count;
    extended.ppEnabledExtensionNames = extensions;

    result = ziggui_loader_create_device(physical, &extended, allocator, device);
    for (Uint32 index = 0; index < switched_count; index++) {
        *switched[index] = switched_from[index];
    }
    if (result == VK_SUCCESS) {
        ziggui_traced_device = *device;
        return result;
    }
    SDL_LogWarn(SDL_LOG_CATEGORY_GPU, "ziggui: the Vulkan device refused ray tracing (%d); made without it", (int)result);
    return ziggui_loader_create_device(physical, info, allocator, device);
}

// Our `vkGetInstanceProcAddr`: the loader's, with our `vkCreateInstance`
// and `vkCreateDevice` in place of theirs.
static PFN_vkVoidFunction VKAPI_CALL ziggui_instance_proc(VkInstance instance, const char *name)
{
    PFN_vkVoidFunction function = ziggui_loader_instance_proc(instance, name);
    if (function == NULL || name == NULL) {
        return function;
    }
    if (instance == VK_NULL_HANDLE && SDL_strcmp(name, "vkCreateInstance") == 0) {
        ziggui_loader_create_instance = (PFN_vkCreateInstance)function;
        return (PFN_vkVoidFunction)ziggui_create_instance;
    }
    if (instance != VK_NULL_HANDLE && SDL_strcmp(name, "vkCreateDevice") == 0) {
        ziggui_loader_create_device = (PFN_vkCreateDevice)function;
        ziggui_device_instance = instance;
        return (PFN_vkVoidFunction)ziggui_create_device;
    }
    return function;
}

// What the backend gets for `SDL_Vulkan_GetVkGetInstanceProcAddr`: our
// `vkGetInstanceProcAddr`, the loader's kept to forward to.
static SDL_FunctionPointer ziggui_vulkan_instance_loader(void)
{
    ziggui_loader_instance_proc = (PFN_vkGetInstanceProcAddr)SDL_Vulkan_GetVkGetInstanceProcAddr();
    if (ziggui_loader_instance_proc == NULL) {
        return NULL;
    }
    return (SDL_FunctionPointer)ziggui_instance_proc;
}

// Whether an SDL_GPU device of the Vulkan driver was made able to trace rays
// (our `vkCreateDevice` switched ray queries on for it). The caller checks
// the driver first (`SDL_GetGPUDeviceDriver` is "vulkan").
bool ziggui_vulkan_traces_rays(SDL_GPUDevice *device)
{
    VulkanRenderer *renderer = (VulkanRenderer *)device->driverData;
    return ziggui_traced_device != VK_NULL_HANDLE && renderer->logicalDevice == ziggui_traced_device;
}

// The `VkDevice` an SDL_GPU device of the Vulkan driver runs on.
void *ziggui_vulkan_device(SDL_GPUDevice *device)
{
    VulkanRenderer *renderer = (VulkanRenderer *)device->driverData;
    return (void *)renderer->logicalDevice;
}

// The `VkPhysicalDevice` behind it.
void *ziggui_vulkan_physical_device(SDL_GPUDevice *device)
{
    VulkanRenderer *renderer = (VulkanRenderer *)device->driverData;
    return (void *)renderer->physicalDevice;
}

// A device-level Vulkan function of its device, by name, or NULL.
PFN_vkVoidFunction ziggui_vulkan_device_function(SDL_GPUDevice *device, const char *name)
{
    VulkanRenderer *renderer = (VulkanRenderer *)device->driverData;
    return renderer->vkGetDeviceProcAddr(renderer->logicalDevice, name);
}

// An instance-level Vulkan function of its instance, by name, or NULL.
PFN_vkVoidFunction ziggui_vulkan_instance_function(SDL_GPUDevice *device, const char *name)
{
    VulkanRenderer *renderer = (VulkanRenderer *)device->driverData;
    return vkGetInstanceProcAddr(renderer->instance, name);
}

// The `VkCommandBuffer` behind an SDL_GPU command buffer of a Vulkan device,
// or NULL while one of SDL's render passes is open on it: an acceleration
// structure build or a barrier of ziggui's may not go inside a render pass
// instance. (SDL's copy and compute passes open no Vulkan scope. The common
// header's `in_progress` flags are kept only in SDL's GPU debug mode, so the
// backend's own state says whether a render pass is open: it holds the
// pass's attachments from its begin to its end, and every pass has one.)
void *ziggui_vulkan_command_buffer(SDL_GPUCommandBuffer *command_buffer)
{
    VulkanCommandBuffer *vulkan = (VulkanCommandBuffer *)command_buffer;
    if (vulkan->colorAttachmentSubresourceCount > 0 || vulkan->depthStencilAttachmentSubresource != NULL) {
        return NULL;
    }
    return (void *)vulkan->commandBuffer;
}

#endif // SDL_GPU_VULKAN
