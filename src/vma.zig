//! GPU memory allocator — idiomatic Zig over the Vulkan Memory Allocator (VMA).
//!
//! VMA is header-only **C++**, so it is reached through a `noexcept`
//! `extern "C"` bridge (`src/c/vma_bridge.{h,cpp}`, landing at v0.3.0). That
//! bridge is the *only* C-ABI boundary; everything in this file is the
//! idiomatic Zig surface a consumer actually calls — Zig calling convention,
//! error unions, opaque handles. *(since v0.3.0)*

const std = @import("std");
const vk = @import("vulkan");

/// An opaque VMA allocator instance — the root object that owns device memory
/// pools. Create with `createAllocator`, release with `destroyAllocator`.
pub const Allocator = opaque {};

/// An opaque handle to one VMA allocation (a region of device memory backing a
/// buffer or image). Returned alongside the Vulkan handle from `createBuffer`/
/// `createImage`; pass it back to the matching `destroy*`.
pub const Allocation = opaque {};

/// Everything needed to stand up an `Allocator`. Mirror your instance/device.
pub const AllocatorCreateInfo = struct {
    /// The physical device the allocations target.
    physical_device: vk.PhysicalDevice,
    /// The logical device allocations are made on.
    device: vk.Device,
    /// The owning instance.
    instance: vk.Instance,
    /// The Vulkan API version in use — gates which VMA features are enabled.
    /// `vk.API_VERSION_1_3` is a packed `vk.Version`; `@bitCast` packs it to
    /// the `u32` the VMA bridge expects.
    api_version: u32 = @bitCast(vk.API_VERSION_1_3),
};

/// Errors the fallible VMA calls can return. Maps the relevant `VkResult`s
/// from the VMA bridge.
pub const Error = error{
    /// `vmaCreateAllocator` failed (bad device/instance, or out of memory).
    AllocatorCreationFailed,
    /// Host memory exhausted creating the resource or its allocation.
    OutOfHostMemory,
    /// Device memory exhausted backing the buffer/image.
    OutOfDeviceMemory,
    /// `mapMemory` on non-host-visible memory (e.g. `.gpu_only`), or a map failure.
    MappingFailed,
};

/// Create a VMA allocator. Caller owns it — release with `destroyAllocator`.
pub fn createAllocator(info: AllocatorCreateInfo) Error!*Allocator {
    _ = info;
    @panic("not implemented");
}

/// Destroy a VMA allocator. Destroy all buffers/images created from it first.
pub fn destroyAllocator(allocator: *Allocator) void {
    _ = allocator;
    @panic("not implemented");
}

/// Intended residency / access pattern for an allocation. `.auto` lets VMA
/// choose the memory type from the resource's usage flags (recommended);
/// the explicit variants pin a residency.
pub const Usage = enum(u8) {
    /// Let VMA pick the best memory type from the buffer/image usage flags.
    auto,
    /// Device-local memory, not host-visible (vertex/index/uniform on GPU).
    gpu_only,
    /// Host-visible, optimised for CPU→GPU uploads (staging, dynamic data).
    cpu_to_gpu,
    /// Host-visible, optimised for GPU→CPU readback.
    gpu_to_cpu,
};

/// A Vulkan buffer paired with its backing VMA allocation.
pub const BufferResult = struct {
    /// The created Vulkan buffer handle.
    buffer: vk.Buffer,
    /// The allocation backing it — pass to `destroyBuffer`.
    allocation: *Allocation,
};

/// Allocate memory and create a `vk.Buffer` in one call. `info` is a standard
/// `VkBufferCreateInfo`; `usage` selects the memory type. *(since v0.3.0)*
pub fn createBuffer(allocator: *Allocator, info: *const vk.BufferCreateInfo, usage: Usage) Error!BufferResult {
    _ = allocator;
    _ = info;
    _ = usage;
    @panic("not implemented");
}

/// Destroy a buffer and free its allocation (the pair from `createBuffer`).
pub fn destroyBuffer(allocator: *Allocator, buffer: vk.Buffer, allocation: *Allocation) void {
    _ = allocator;
    _ = buffer;
    _ = allocation;
    @panic("not implemented");
}

/// A Vulkan image paired with its backing VMA allocation.
pub const ImageResult = struct {
    /// The created Vulkan image handle.
    image: vk.Image,
    /// The allocation backing it — pass to `destroyImage`.
    allocation: *Allocation,
};

/// Allocate memory and create a `vk.Image` in one call. *(since v0.3.0)*
pub fn createImage(allocator: *Allocator, info: *const vk.ImageCreateInfo, usage: Usage) Error!ImageResult {
    _ = allocator;
    _ = info;
    _ = usage;
    @panic("not implemented");
}

/// Destroy an image and free its allocation (the pair from `createImage`).
pub fn destroyImage(allocator: *Allocator, image: vk.Image, allocation: *Allocation) void {
    _ = allocator;
    _ = image;
    _ = allocation;
    @panic("not implemented");
}

/// Map a host-visible allocation and return a pointer to its bytes. Pair with
/// `unmapMemory`. Mapping `gpu_only` memory fails. *(since v0.3.0)*
pub fn mapMemory(allocator: *Allocator, allocation: *Allocation) Error![*]u8 {
    _ = allocator;
    _ = allocation;
    @panic("not implemented");
}

/// Unmap a previously `mapMemory`'d allocation.
pub fn unmapMemory(allocator: *Allocator, allocation: *Allocation) void {
    _ = allocator;
    _ = allocation;
    @panic("not implemented");
}

test {
    std.testing.refAllDecls(@This());
}
