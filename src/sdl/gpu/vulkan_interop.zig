//! SDL_GPU's own Vulkan objects, for Vulkan work SDL_GPU has no API for (ray
//! tracing): the device, its functions, the command buffer between SDL's
//! passes, and buffers of ziggui's own made on that device. They come from
//! `vulkan_interop.c`, compiled into SDL in place of its Vulkan backend
//! (`has_vulkan_interop`: Windows and Linux, SDL built from the release),
//! which also makes a device that can trace rays able to.
//!
//! Every SDL object is borrowed: SDL owns and destroys it.

const std = @import("std");
const log = std.log.scoped(.ziggui_vulkan_interop);
const mod = @import("../module.zig");
const sdl_c = @import("sdl_c");
const vulkan_c = @import("vulkan_c");

/// The C side, `vulkan_interop.c`.
const Externs = struct {
    const Self = @This();

    /// `ziggui_vulkan_traces_rays`.
    extern fn ziggui_vulkan_traces_rays(device: *sdl_c.SDL_GPUDevice) bool;
    /// `ziggui_vulkan_device`.
    extern fn ziggui_vulkan_device(device: *sdl_c.SDL_GPUDevice) ?*anyopaque;
    /// `ziggui_vulkan_physical_device`.
    extern fn ziggui_vulkan_physical_device(device: *sdl_c.SDL_GPUDevice) ?*anyopaque;
    /// `ziggui_vulkan_device_function`.
    extern fn ziggui_vulkan_device_function(device: *sdl_c.SDL_GPUDevice, name: [*:0]const u8) vulkan_c.PFN_vkVoidFunction;
    /// `ziggui_vulkan_instance_function`.
    extern fn ziggui_vulkan_instance_function(device: *sdl_c.SDL_GPUDevice, name: [*:0]const u8) vulkan_c.PFN_vkVoidFunction;
    /// `ziggui_vulkan_command_buffer`.
    extern fn ziggui_vulkan_command_buffer(command_buffer: *sdl_c.SDL_GPUCommandBuffer) ?*anyopaque;
};

/// The Vulkan functions the ray tracer calls, loaded from SDL's device by
/// their C names (`VulkanInterop.init`); every one is there once loaded.
pub const VulkanFunctions = struct {
    const Self = @This();

    /// The functions loaded from the instance rather than the device.
    const instance_level = [_][]const u8{ "vkGetPhysicalDeviceMemoryProperties", "vkGetPhysicalDeviceProperties2" };

    /// `vkGetPhysicalDeviceMemoryProperties`
    vkGetPhysicalDeviceMemoryProperties: vulkan_c.PFN_vkGetPhysicalDeviceMemoryProperties = null,
    /// `vkGetPhysicalDeviceProperties2`
    vkGetPhysicalDeviceProperties2: vulkan_c.PFN_vkGetPhysicalDeviceProperties2 = null,
    /// `vkCreateBuffer`
    vkCreateBuffer: vulkan_c.PFN_vkCreateBuffer = null,
    /// `vkDestroyBuffer`
    vkDestroyBuffer: vulkan_c.PFN_vkDestroyBuffer = null,
    /// `vkGetBufferMemoryRequirements`
    vkGetBufferMemoryRequirements: vulkan_c.PFN_vkGetBufferMemoryRequirements = null,
    /// `vkAllocateMemory`
    vkAllocateMemory: vulkan_c.PFN_vkAllocateMemory = null,
    /// `vkFreeMemory`
    vkFreeMemory: vulkan_c.PFN_vkFreeMemory = null,
    /// `vkBindBufferMemory`
    vkBindBufferMemory: vulkan_c.PFN_vkBindBufferMemory = null,
    /// `vkMapMemory`
    vkMapMemory: vulkan_c.PFN_vkMapMemory = null,
    /// `vkGetBufferDeviceAddress`
    vkGetBufferDeviceAddress: vulkan_c.PFN_vkGetBufferDeviceAddress = null,
    /// `vkCreateAccelerationStructureKHR`
    vkCreateAccelerationStructureKHR: vulkan_c.PFN_vkCreateAccelerationStructureKHR = null,
    /// `vkDestroyAccelerationStructureKHR`
    vkDestroyAccelerationStructureKHR: vulkan_c.PFN_vkDestroyAccelerationStructureKHR = null,
    /// `vkGetAccelerationStructureBuildSizesKHR`
    vkGetAccelerationStructureBuildSizesKHR: vulkan_c.PFN_vkGetAccelerationStructureBuildSizesKHR = null,
    /// `vkGetAccelerationStructureDeviceAddressKHR`
    vkGetAccelerationStructureDeviceAddressKHR: vulkan_c.PFN_vkGetAccelerationStructureDeviceAddressKHR = null,
    /// `vkCmdBuildAccelerationStructuresKHR`
    vkCmdBuildAccelerationStructuresKHR: vulkan_c.PFN_vkCmdBuildAccelerationStructuresKHR = null,
    /// `vkCmdPipelineBarrier`
    vkCmdPipelineBarrier: vulkan_c.PFN_vkCmdPipelineBarrier = null,

    /// Loads every function from `device`.
    ///
    /// - `device`: an SDL_GPU device of the Vulkan driver.
    /// - Returns: the functions, or null (logged) when one is missing.
    fn load(device: *sdl_c.SDL_GPUDevice) ?Self {
        var self: Self = .{};
        inline for (@typeInfo(Self).@"struct".field_names) |name| {
            const instance = comptime Self.isInstanceLevel(name);
            const function = if (instance) Externs.ziggui_vulkan_instance_function(device, name) else Externs.ziggui_vulkan_device_function(device, name);
            if (function == null) {
                log.warn("Vulkan ray tracing off: no {s}", .{name});
                return null;
            }
            @field(self, name) = @ptrCast(function);
        }
        return self;
    }

    /// Whether a function is loaded from the instance.
    ///
    /// - `name`: the function's C name.
    /// - Returns: true for an instance-level function.
    fn isInstanceLevel(comptime name: []const u8) bool {
        for (Self.instance_level) |instance_name| if (std.mem.eql(u8, name, instance_name)) return true;
        return false;
    }
};

/// Where a `VulkanBuffer` lives: what reads and writes it.
pub const VulkanMemory = enum {
    const Self = @This();

    /// Written by the CPU through `VulkanBuffer.mapped`, read by the GPU
    /// (host-visible and coherent, on the device's own memory where it can be).
    shared,
    /// Used by the GPU alone (device-local).
    private,
};

/// A buffer of ziggui's own on SDL's device, its memory, and its GPU address.
pub const VulkanBuffer = struct {
    const Self = @This();

    /// The buffer.
    buffer: vulkan_c.VkBuffer,
    /// Its memory, one allocation of its own.
    memory: vulkan_c.VkDeviceMemory,
    /// Its length, in bytes.
    size: usize,
    /// Its address in the GPU's shaders and builds.
    address: u64,
    /// The CPU's view of a `shared` buffer, null for a `private` one.
    mapped: ?[*]u8,
};

/// SDL_GPU's Vulkan device, the functions ray tracing calls on it, and what
/// it needs to know of the GPU to make buffers.
pub const VulkanInterop = struct {
    const Self = @This();

    /// The SDL_GPU device, SDL's.
    device: *sdl_c.SDL_GPUDevice,
    /// Its `VkDevice`, SDL's.
    vulkan_device: vulkan_c.VkDevice,
    /// Its `VkPhysicalDevice`.
    physical_device: vulkan_c.VkPhysicalDevice,
    /// The functions.
    functions: VulkanFunctions,
    /// The GPU's memory types.
    memory_properties: vulkan_c.VkPhysicalDeviceMemoryProperties,
    /// How a build's scratch address must be aligned, in bytes.
    scratch_alignment: u64,

    /// The interop for a device that traces rays (`tracesRays`), its
    /// functions loaded.
    ///
    /// - `device`: an SDL_GPU device.
    /// - Returns: the interop, or null where it does not trace rays or a function is missing (logged).
    pub fn init(device: *sdl_c.SDL_GPUDevice) ?Self {
        if (comptime !mod.has_vulkan_interop) return null;
        if (!Self.tracesRays(device)) return null;
        const functions = VulkanFunctions.load(device) orelse return null;
        const physical_device: vulkan_c.VkPhysicalDevice = @ptrCast(Externs.ziggui_vulkan_physical_device(device));
        var memory_properties: vulkan_c.VkPhysicalDeviceMemoryProperties = undefined;
        functions.vkGetPhysicalDeviceMemoryProperties.?(physical_device, &memory_properties);
        var structure_properties: vulkan_c.VkPhysicalDeviceAccelerationStructurePropertiesKHR = .{ .sType = vulkan_c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_PROPERTIES_KHR };
        var properties: vulkan_c.VkPhysicalDeviceProperties2 = .{ .sType = vulkan_c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &structure_properties };
        functions.vkGetPhysicalDeviceProperties2.?(physical_device, &properties);
        const self = Self{
            .device = device,
            .vulkan_device = @ptrCast(Externs.ziggui_vulkan_device(device)),
            .physical_device = physical_device,
            .functions = functions,
            .memory_properties = memory_properties,
            .scratch_alignment = @max(structure_properties.minAccelerationStructureScratchOffsetAlignment, 1),
        };
        return self;
    }

    /// Whether a device can trace rays: SDL built with `vulkan_interop.c`,
    /// the Vulkan driver, and a device it made able to (Vulkan 1.2 with ray
    /// queries, acceleration structures and buffer device addresses).
    ///
    /// - `device`: an SDL_GPU device.
    /// - Returns: true when it traces rays.
    pub fn tracesRays(device: *sdl_c.SDL_GPUDevice) bool {
        if (comptime !mod.has_vulkan_interop) return false;
        const driver = sdl_c.SDL_GetGPUDeviceDriver(device) orelse return false;
        if (!std.mem.eql(u8, std.mem.span(driver), "vulkan")) return false;
        return Externs.ziggui_vulkan_traces_rays(device);
    }

    /// The `VkCommandBuffer` behind an SDL_GPU command buffer, while none of
    /// SDL's passes is open on it.
    ///
    /// - `self`: the interop.
    /// - `command_buffer`: an SDL_GPU command buffer of the device.
    /// - Returns: the command buffer, or null while a pass is open.
    pub fn commandBuffer(self: *const Self, command_buffer: *sdl_c.SDL_GPUCommandBuffer) vulkan_c.VkCommandBuffer {
        _ = self;
        if (comptime !mod.has_vulkan_interop) return null;
        return @ptrCast(Externs.ziggui_vulkan_command_buffer(command_buffer));
    }

    /// Makes a buffer of `size` bytes for `usage` (its device address usage
    /// added), in its own allocation of `memory`.
    ///
    /// - `self`: the interop.
    /// - `size`: its length, in bytes (at least 16 are made).
    /// - `usage`: its `VkBufferUsageFlags`.
    /// - `memory`: where it lives.
    /// - Returns: the buffer, or null (logged) when it could not be made.
    pub fn makeBuffer(self: *const Self, size: usize, usage: vulkan_c.VkBufferUsageFlags, memory: VulkanMemory) ?VulkanBuffer {
        const functions = &self.functions;
        const length = @max(size, 16);
        var buffer: vulkan_c.VkBuffer = null;
        const buffer_info: vulkan_c.VkBufferCreateInfo = .{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = length,
            .usage = usage | vulkan_c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            .sharingMode = vulkan_c.VK_SHARING_MODE_EXCLUSIVE,
        };
        if (functions.vkCreateBuffer.?(self.vulkan_device, &buffer_info, null, &buffer) != vulkan_c.VK_SUCCESS) {
            log.warn("no Vulkan buffer of {d} bytes", .{length});
            return null;
        }
        var requirements: vulkan_c.VkMemoryRequirements = undefined;
        functions.vkGetBufferMemoryRequirements.?(self.vulkan_device, buffer, &requirements);
        const device_memory = self.allocateMemory(requirements, memory) orelse {
            functions.vkDestroyBuffer.?(self.vulkan_device, buffer, null);
            return null;
        };
        var made: VulkanBuffer = .{ .buffer = buffer, .memory = device_memory, .size = length, .address = 0, .mapped = null };
        if (functions.vkBindBufferMemory.?(self.vulkan_device, buffer, device_memory, 0) != vulkan_c.VK_SUCCESS) {
            log.warn("Vulkan buffer memory not bound", .{});
            self.releaseBuffer(made);
            return null;
        }
        if (memory == .shared) {
            var mapped: ?*anyopaque = null;
            if (functions.vkMapMemory.?(self.vulkan_device, device_memory, 0, vulkan_c.VK_WHOLE_SIZE, 0, &mapped) != vulkan_c.VK_SUCCESS or mapped == null) {
                log.warn("Vulkan buffer memory not mapped", .{});
                self.releaseBuffer(made);
                return null;
            }
            made.mapped = @ptrCast(mapped);
        }
        const address_info: vulkan_c.VkBufferDeviceAddressInfo = .{ .sType = vulkan_c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = buffer };
        made.address = functions.vkGetBufferDeviceAddress.?(self.vulkan_device, &address_info);
        return made;
    }

    /// Destroys a buffer and frees its memory (mapped memory unmaps with it).
    /// The GPU must be done with it.
    ///
    /// - `self`: the interop.
    /// - `buffer`: the buffer.
    pub fn releaseBuffer(self: *const Self, buffer: VulkanBuffer) void {
        self.functions.vkDestroyBuffer.?(self.vulkan_device, buffer.buffer, null);
        self.functions.vkFreeMemory.?(self.vulkan_device, buffer.memory, null);
    }

    /// Memory for a buffer, from the first memory type that fits `memory`
    /// and has room: for `shared`, host-visible and coherent, device-local
    /// first where one is (on a GPU without resizable BAR, a 256 MB heap)
    /// and plain host memory once that is full; for `private`, device-local.
    /// Each type is tried once, in the device's order within a preference.
    ///
    /// - `self`: the interop.
    /// - `requirements`: the buffer's memory requirements.
    /// - `memory`: where it lives.
    /// - Returns: the memory, owned by the caller; null (logged) when no type has room.
    fn allocateMemory(self: *const Self, requirements: vulkan_c.VkMemoryRequirements, memory: VulkanMemory) ?vulkan_c.VkDeviceMemory {
        const host = vulkan_c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vulkan_c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        const local = vulkan_c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
        const choices: []const u32 = switch (memory) {
            .shared => &.{ host | local, host },
            .private => &.{local},
        };
        const flags: vulkan_c.VkMemoryAllocateFlagsInfo = .{
            .sType = vulkan_c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO,
            .flags = vulkan_c.VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT,
        };
        var tried: u32 = 0;
        var fitting = false;
        for (choices) |wanted| {
            for (0..self.memory_properties.memoryTypeCount) |index| {
                const bit = @as(u32, 1) << @intCast(index);
                if (requirements.memoryTypeBits & bit == 0 or tried & bit != 0) continue;
                if (self.memory_properties.memoryTypes[index].propertyFlags & wanted != wanted) continue;
                tried |= bit;
                fitting = true;
                const allocate_info: vulkan_c.VkMemoryAllocateInfo = .{
                    .sType = vulkan_c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                    .pNext = &flags,
                    .allocationSize = requirements.size,
                    .memoryTypeIndex = @intCast(index),
                };
                var device_memory: vulkan_c.VkDeviceMemory = null;
                const result = self.functions.vkAllocateMemory.?(self.vulkan_device, &allocate_info, null, &device_memory);
                if (result == vulkan_c.VK_SUCCESS) return device_memory;
                // Out of room in this type's heap: the next type may have it.
                if (result != vulkan_c.VK_ERROR_OUT_OF_DEVICE_MEMORY and result != vulkan_c.VK_ERROR_OUT_OF_HOST_MEMORY) {
                    log.warn("no Vulkan memory of {d} bytes (VkResult {d})", .{ requirements.size, result });
                    return null;
                }
            }
        }
        if (fitting) {
            log.warn("no Vulkan memory of {d} bytes: every {t} memory type is full", .{ requirements.size, memory });
        } else log.warn("no Vulkan memory type for a {t} buffer", .{memory});
        return null;
    }
};

// -----------------------------------------------------------------------------
// Unit Tests

test {
    std.testing.refAllDecls(@This());
}

test "a Vulkan device that can trace rays is made able to, and its functions load" {
    if (comptime !mod.has_vulkan_interop) return error.SkipZigTest;
    if (!sdl_c.SDL_Init(sdl_c.SDL_INIT_VIDEO)) return error.SkipZigTest;
    defer sdl_c.SDL_Quit();
    var gpu = mod.Gpu.init(std.testing.allocator, null) orelse return error.SkipZigTest;
    defer gpu.deinit();
    if (!std.mem.eql(u8, gpu.driverName(), "vulkan")) return error.SkipZigTest;
    if (!VulkanInterop.tracesRays(gpu.device)) {
        log.info("this Vulkan device traces no rays", .{});
        return error.SkipZigTest;
    }
    const interop = VulkanInterop.init(gpu.device) orelse return error.TestUnexpectedResult;
    try std.testing.expect(interop.vulkan_device != null);
    try std.testing.expect(interop.scratch_alignment >= 1);
    // A shared buffer is mapped and has an address; a private one only an address.
    const shared = interop.makeBuffer(64, vulkan_c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, .shared) orelse return error.TestUnexpectedResult;
    defer interop.releaseBuffer(shared);
    try std.testing.expect(shared.mapped != null and shared.address != 0);
    const private = interop.makeBuffer(64, vulkan_c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, .private) orelse return error.TestUnexpectedResult;
    defer interop.releaseBuffer(private);
    try std.testing.expect(private.mapped == null and private.address != 0);
}
