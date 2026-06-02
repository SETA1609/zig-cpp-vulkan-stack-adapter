// VMA implementation + the C-ABI bridge. The only C++ translation unit.
//
// VMA is reached dynamically (no static libvulkan link): we hand it the
// bootstrap vkGetInstanceProcAddr and it loads the rest. Every bridge function
// is noexcept and catches all exceptions before returning across the C ABI.

#define VMA_STATIC_VULKAN_FUNCTIONS 0
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 1
#define VMA_IMPLEMENTATION
#include "vma_bridge.h"

#include "vk_mem_alloc.h"

static VmaMemoryUsage to_vma_usage(VmaBridgeUsage u) {
  switch (u) {
    case VMA_BRIDGE_USAGE_GPU_ONLY:
      return VMA_MEMORY_USAGE_GPU_ONLY;
    case VMA_BRIDGE_USAGE_CPU_TO_GPU:
      return VMA_MEMORY_USAGE_CPU_TO_GPU;
    case VMA_BRIDGE_USAGE_GPU_TO_CPU:
      return VMA_MEMORY_USAGE_GPU_TO_CPU;
    case VMA_BRIDGE_USAGE_AUTO:
      return VMA_MEMORY_USAGE_AUTO;
    default:
      return VMA_MEMORY_USAGE_AUTO;
  }
}

// Map our stable bridge flag bits onto VMA's (non-contiguous) flag bits.
static VmaAllocationCreateFlags to_vma_flags(uint32_t f) {
  VmaAllocationCreateFlags out = 0;
  if (f & VMA_BRIDGE_ALLOC_DEDICATED_MEMORY)
    out |= VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT;
  if (f & VMA_BRIDGE_ALLOC_MAPPED)
    out |= VMA_ALLOCATION_CREATE_MAPPED_BIT;
  if (f & VMA_BRIDGE_ALLOC_HOST_ACCESS_SEQUENTIAL_WRITE)
    out |= VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
  if (f & VMA_BRIDGE_ALLOC_HOST_ACCESS_RANDOM)
    out |= VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT;
  return out;
}

extern "C" VkResult vma_bridge_create_allocator(VkInstance instance, VkPhysicalDevice physical,
                                                VkDevice device, uint32_t api_version,
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

extern "C" VkResult vma_bridge_create_buffer(VmaBridgeAllocator a, const VkBufferCreateInfo* info,
                                             VmaBridgeUsage usage, uint32_t flags,
                                             uint64_t* out_buffer,
                                             VmaBridgeAllocation* out_alloc) noexcept {
  try {
    VmaAllocationCreateInfo aci = {};
    aci.usage = to_vma_usage(usage);
    aci.flags = to_vma_flags(flags);
    VkBuffer buf = VK_NULL_HANDLE;
    VmaAllocation allocation = nullptr;
    VkResult r =
        vmaCreateBuffer(reinterpret_cast<VmaAllocator>(a), info, &aci, &buf, &allocation, nullptr);
    *out_buffer = (uint64_t)(uintptr_t)buf;
    *out_alloc = reinterpret_cast<VmaBridgeAllocation>(allocation);
    return r;
  } catch (...) {
    return VK_ERROR_UNKNOWN;
  }
}

extern "C" void vma_bridge_destroy_buffer(VmaBridgeAllocator a, uint64_t buffer,
                                          VmaBridgeAllocation alloc) noexcept {
  vmaDestroyBuffer(reinterpret_cast<VmaAllocator>(a), (VkBuffer)(uintptr_t)buffer,
                   reinterpret_cast<VmaAllocation>(alloc));
}

extern "C" VkResult vma_bridge_create_image(VmaBridgeAllocator a, const VkImageCreateInfo* info,
                                            VmaBridgeUsage usage, uint32_t flags,
                                            uint64_t* out_image,
                                            VmaBridgeAllocation* out_alloc) noexcept {
  try {
    VmaAllocationCreateInfo aci = {};
    aci.usage = to_vma_usage(usage);
    aci.flags = to_vma_flags(flags);
    VkImage img = VK_NULL_HANDLE;
    VmaAllocation allocation = nullptr;
    VkResult r =
        vmaCreateImage(reinterpret_cast<VmaAllocator>(a), info, &aci, &img, &allocation, nullptr);
    *out_image = (uint64_t)(uintptr_t)img;
    *out_alloc = reinterpret_cast<VmaBridgeAllocation>(allocation);
    return r;
  } catch (...) {
    return VK_ERROR_UNKNOWN;
  }
}

extern "C" void vma_bridge_destroy_image(VmaBridgeAllocator a, uint64_t image,
                                         VmaBridgeAllocation alloc) noexcept {
  vmaDestroyImage(reinterpret_cast<VmaAllocator>(a), (VkImage)(uintptr_t)image,
                  reinterpret_cast<VmaAllocation>(alloc));
}

extern "C" VkResult vma_bridge_map_memory(VmaBridgeAllocator a, VmaBridgeAllocation alloc,
                                          void** out_ptr) noexcept {
  try {
    return vmaMapMemory(reinterpret_cast<VmaAllocator>(a), reinterpret_cast<VmaAllocation>(alloc),
                        out_ptr);
  } catch (...) {
    return VK_ERROR_UNKNOWN;
  }
}

extern "C" void vma_bridge_unmap_memory(VmaBridgeAllocator a, VmaBridgeAllocation alloc) noexcept {
  vmaUnmapMemory(reinterpret_cast<VmaAllocator>(a), reinterpret_cast<VmaAllocation>(alloc));
}

extern "C" void vma_bridge_get_allocation_info(VmaBridgeAllocator a, VmaBridgeAllocation alloc,
                                               uint32_t* out_memory_type,
                                               uint64_t* out_device_memory, uint64_t* out_offset,
                                               uint64_t* out_size, void** out_mapped) noexcept {
  VmaAllocationInfo info = {};
  vmaGetAllocationInfo(reinterpret_cast<VmaAllocator>(a), reinterpret_cast<VmaAllocation>(alloc),
                       &info);
  *out_memory_type = info.memoryType;
  *out_device_memory = (uint64_t)(uintptr_t)info.deviceMemory;
  *out_offset = info.offset;
  *out_size = info.size;
  *out_mapped = info.pMappedData;
}

extern "C" VkResult vma_bridge_flush_allocation(VmaBridgeAllocator a, VmaBridgeAllocation alloc,
                                                uint64_t offset, uint64_t size) noexcept {
  try {
    return vmaFlushAllocation(reinterpret_cast<VmaAllocator>(a),
                              reinterpret_cast<VmaAllocation>(alloc), offset, size);
  } catch (...) {
    return VK_ERROR_UNKNOWN;
  }
}

extern "C" VkResult vma_bridge_invalidate_allocation(VmaBridgeAllocator a,
                                                     VmaBridgeAllocation alloc, uint64_t offset,
                                                     uint64_t size) noexcept {
  try {
    return vmaInvalidateAllocation(reinterpret_cast<VmaAllocator>(a),
                                   reinterpret_cast<VmaAllocation>(alloc), offset, size);
  } catch (...) {
    return VK_ERROR_UNKNOWN;
  }
}
