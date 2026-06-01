// C-ABI bridge over the Vulkan Memory Allocator (header-only C++).
//
// This is the *only* C++↔Zig boundary in the library. Every function is
// `extern "C"` + `noexcept` and catches before crossing the ABI (design rule).
// Handles cross as plain integers / opaque pointers so the Zig side
// (vulkan-zig's enum handles) matches: dispatchable handles as opaque pointers,
// non-dispatchable ones as `uint64_t` (bridged through `uintptr_t` here).
#ifndef VMA_BRIDGE_H
#define VMA_BRIDGE_H

#include <vulkan/vulkan.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque wrappers around VmaAllocator / VmaAllocation (also opaque pointers).
typedef struct VmaBridgeAllocator_T* VmaBridgeAllocator;
typedef struct VmaBridgeAllocation_T* VmaBridgeAllocation;

// Mirrors the Zig `vma.Usage` enum.
typedef enum {
    VMA_BRIDGE_USAGE_AUTO = 0,
    VMA_BRIDGE_USAGE_GPU_ONLY = 1,
    VMA_BRIDGE_USAGE_CPU_TO_GPU = 2,
    VMA_BRIDGE_USAGE_GPU_TO_CPU = 3,
} VmaBridgeUsage;

// Bridge functions return the raw `VkResult` (on a caught C++ exception:
// `VK_ERROR_UNKNOWN`). The VkResult→`vma.Error` translation lives on the Zig
// side (using vulkan-zig's `vk.Result`), so no bridge-specific error type is
// exposed.
//
// `gipa` is the bootstrap vkGetInstanceProcAddr (from our pure-Zig volk loader);
// VMA loads the rest of the entry points from it (no static libvulkan link).
VkResult vma_bridge_create_allocator(VkInstance instance,
                                     VkPhysicalDevice physical,
                                     VkDevice device,
                                     uint32_t api_version,
                                     PFN_vkGetInstanceProcAddr gipa,
                                     VmaBridgeAllocator* out) noexcept;
void vma_bridge_destroy_allocator(VmaBridgeAllocator a) noexcept;

VkResult vma_bridge_create_buffer(VmaBridgeAllocator a,
                                  const VkBufferCreateInfo* info,
                                  VmaBridgeUsage usage,
                                  uint64_t* out_buffer,
                                  VmaBridgeAllocation* out_alloc) noexcept;
void vma_bridge_destroy_buffer(VmaBridgeAllocator a, uint64_t buffer, VmaBridgeAllocation alloc) noexcept;

VkResult vma_bridge_create_image(VmaBridgeAllocator a,
                                 const VkImageCreateInfo* info,
                                 VmaBridgeUsage usage,
                                 uint64_t* out_image,
                                 VmaBridgeAllocation* out_alloc) noexcept;
void vma_bridge_destroy_image(VmaBridgeAllocator a, uint64_t image, VmaBridgeAllocation alloc) noexcept;

VkResult vma_bridge_map_memory(VmaBridgeAllocator a, VmaBridgeAllocation alloc, void** out_ptr) noexcept;
void vma_bridge_unmap_memory(VmaBridgeAllocator a, VmaBridgeAllocation alloc) noexcept;

#ifdef __cplusplus
}
#endif

#endif // VMA_BRIDGE_H
