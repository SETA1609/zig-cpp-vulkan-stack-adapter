// VMA implementation + the C-ABI bridge. The only C++ translation unit.
//
// VMA is reached dynamically (no static libvulkan link): we hand it the
// bootstrap vkGetInstanceProcAddr and it loads the rest. Every bridge function
// is noexcept and catches all exceptions before returning across the C ABI.

#define VMA_STATIC_VULKAN_FUNCTIONS 0
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 1
#define VMA_IMPLEMENTATION
#include "vk_mem_alloc.h"

#include "vma_bridge.h"

static VmaMemoryUsage to_vma_usage(VmaBridgeUsage u) {
    switch (u) {
        case VMA_BRIDGE_USAGE_GPU_ONLY:   return VMA_MEMORY_USAGE_GPU_ONLY;
        case VMA_BRIDGE_USAGE_CPU_TO_GPU: return VMA_MEMORY_USAGE_CPU_TO_GPU;
        case VMA_BRIDGE_USAGE_GPU_TO_CPU: return VMA_MEMORY_USAGE_GPU_TO_CPU;
        case VMA_BRIDGE_USAGE_AUTO:       return VMA_MEMORY_USAGE_AUTO;
        default:                          return VMA_MEMORY_USAGE_AUTO;
    }
}

extern "C" VkResult vma_bridge_create_allocator(VkInstance instance,
                                                VkPhysicalDevice physical,
                                                VkDevice device,
                                                uint32_t api_version,
                                                PFN_vkGetInstanceProcAddr gipa,
                                                VmaBridgeAllocator* out) noexcept {
    try {
        VmaVulkanFunctions fns = {};
        fns.vkGetInstanceProcAddr = gipa;
        fns.vkGetDeviceProcAddr =
            reinterpret_cast<PFN_vkGetDeviceProcAddr>(gipa(instance, "vkGetDeviceProcAddr"));

        VmaAllocatorCreateInfo ci = {};
        ci.instance = instance;
        ci.physicalDevice = physical;
        ci.device = device;
        ci.vulkanApiVersion = api_version;
        ci.pVulkanFunctions = &fns;

        VmaAllocator alloc = nullptr;
        VkResult r = vmaCreateAllocator(&ci, &alloc);
        *out = reinterpret_cast<VmaBridgeAllocator>(alloc);
        return r;
    } catch (...) {
        return VK_ERROR_UNKNOWN;
    }
}

extern "C" void vma_bridge_destroy_allocator(VmaBridgeAllocator a) noexcept {
    vmaDestroyAllocator(reinterpret_cast<VmaAllocator>(a));
}

extern "C" VkResult vma_bridge_create_buffer(VmaBridgeAllocator a,
                                             const VkBufferCreateInfo* info,
                                             VmaBridgeUsage usage,
                                             uint64_t* out_buffer,
                                             VmaBridgeAllocation* out_alloc) noexcept {
    try {
        VmaAllocationCreateInfo aci = {};
        aci.usage = to_vma_usage(usage);
        VkBuffer buf = VK_NULL_HANDLE;
        VmaAllocation allocation = nullptr;
        VkResult r = vmaCreateBuffer(reinterpret_cast<VmaAllocator>(a), info, &aci, &buf, &allocation, nullptr);
        *out_buffer = (uint64_t)(uintptr_t)buf;
        *out_alloc = reinterpret_cast<VmaBridgeAllocation>(allocation);
        return r;
    } catch (...) {
        return VK_ERROR_UNKNOWN;
    }
}

extern "C" void vma_bridge_destroy_buffer(VmaBridgeAllocator a, uint64_t buffer, VmaBridgeAllocation alloc) noexcept {
    vmaDestroyBuffer(reinterpret_cast<VmaAllocator>(a), (VkBuffer)(uintptr_t)buffer, reinterpret_cast<VmaAllocation>(alloc));
}

extern "C" VkResult vma_bridge_create_image(VmaBridgeAllocator a,
                                            const VkImageCreateInfo* info,
                                            VmaBridgeUsage usage,
                                            uint64_t* out_image,
                                            VmaBridgeAllocation* out_alloc) noexcept {
    try {
        VmaAllocationCreateInfo aci = {};
        aci.usage = to_vma_usage(usage);
        VkImage img = VK_NULL_HANDLE;
        VmaAllocation allocation = nullptr;
        VkResult r = vmaCreateImage(reinterpret_cast<VmaAllocator>(a), info, &aci, &img, &allocation, nullptr);
        *out_image = (uint64_t)(uintptr_t)img;
        *out_alloc = reinterpret_cast<VmaBridgeAllocation>(allocation);
        return r;
    } catch (...) {
        return VK_ERROR_UNKNOWN;
    }
}

extern "C" void vma_bridge_destroy_image(VmaBridgeAllocator a, uint64_t image, VmaBridgeAllocation alloc) noexcept {
    vmaDestroyImage(reinterpret_cast<VmaAllocator>(a), (VkImage)(uintptr_t)image, reinterpret_cast<VmaAllocation>(alloc));
}

extern "C" VkResult vma_bridge_map_memory(VmaBridgeAllocator a, VmaBridgeAllocation alloc, void** out_ptr) noexcept {
    try {
        return vmaMapMemory(reinterpret_cast<VmaAllocator>(a), reinterpret_cast<VmaAllocation>(alloc), out_ptr);
    } catch (...) {
        return VK_ERROR_UNKNOWN;
    }
}

extern "C" void vma_bridge_unmap_memory(VmaBridgeAllocator a, VmaBridgeAllocation alloc) noexcept {
    vmaUnmapMemory(reinterpret_cast<VmaAllocator>(a), reinterpret_cast<VmaAllocation>(alloc));
}
