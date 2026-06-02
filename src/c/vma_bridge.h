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

// Allocation-create flags — **our own stable bit layout** (mirrors Zig
// `vma.Flags`). The bridge maps these onto VMA's non-contiguous flag bits, so
// VMA's enum values never leak across the ABI. `0` = the default path.
enum {
    VMA_BRIDGE_ALLOC_DEDICATED_MEMORY = 1u << 0,
    VMA_BRIDGE_ALLOC_MAPPED = 1u << 1,
    VMA_BRIDGE_ALLOC_HOST_ACCESS_SEQUENTIAL_WRITE = 1u << 2,
    VMA_BRIDGE_ALLOC_HOST_ACCESS_RANDOM = 1u << 3,
};

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
                                  uint32_t flags,
                                  uint64_t* out_buffer,
                                  VmaBridgeAllocation* out_alloc) noexcept;
void vma_bridge_destroy_buffer(VmaBridgeAllocator a, uint64_t buffer, VmaBridgeAllocation alloc) noexcept;

VkResult vma_bridge_create_image(VmaBridgeAllocator a,
                                 const VkImageCreateInfo* info,
                                 VmaBridgeUsage usage,
                                 uint32_t flags,
                                 uint64_t* out_image,
                                 VmaBridgeAllocation* out_alloc) noexcept;
void vma_bridge_destroy_image(VmaBridgeAllocator a, uint64_t image, VmaBridgeAllocation alloc) noexcept;

VkResult vma_bridge_map_memory(VmaBridgeAllocator a, VmaBridgeAllocation alloc, void** out_ptr) noexcept;
void vma_bridge_unmap_memory(VmaBridgeAllocator a, VmaBridgeAllocation alloc) noexcept;

// Query an allocation's placement. `vmaGetAllocationInfo` cannot fail, so this
// returns void; `out_mapped` is non-null only for a MAPPED (persistently
// mapped) allocation. Out-params (not a struct) so there is no C-struct layout
// to keep in lockstep across the ABI.
void vma_bridge_get_allocation_info(VmaBridgeAllocator a,
                                    VmaBridgeAllocation alloc,
                                    uint32_t* out_memory_type,
                                    uint64_t* out_device_memory,
                                    uint64_t* out_offset,
                                    uint64_t* out_size,
                                    void** out_mapped) noexcept;

// Flush / invalidate a range of a non-coherent host-visible allocation. Pass
// `VK_WHOLE_SIZE` for `size` to cover offset→end. No-ops (return success) when
// the memory is host-coherent.
VkResult vma_bridge_flush_allocation(VmaBridgeAllocator a, VmaBridgeAllocation alloc, uint64_t offset, uint64_t size) noexcept;
VkResult vma_bridge_invalidate_allocation(VmaBridgeAllocator a, VmaBridgeAllocation alloc, uint64_t offset, uint64_t size) noexcept;

#ifdef __cplusplus
}
#endif

#endif // VMA_BRIDGE_H
