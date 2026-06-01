//! GPU memory allocator — idiomatic Zig over the Vulkan Memory Allocator (VMA).
//!
//! VMA is header-only **C++**, reached through a `noexcept` `extern "C"` bridge
//! (`src/c/vma_bridge.{h,cpp}`). That bridge is the *only* C-ABI boundary; this
//! file is the idiomatic Zig surface — Zig calling convention, error unions,
//! opaque handles. The bridge returns raw `VkResult`s; the translation to
//! `Error` lives here (using vulkan-zig's `vk.Result`), so no bridge type is
//! exposed. *(since v0.3.0)*

const std = @import("std");
const vk = @import("vulkan");
const volk = @import("volk.zig");

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

/// Errors the fallible VMA calls can return — translated from `VkResult` by
/// `check`. `Unknown` is the last resort (an unexpected `VkResult` or a caught
/// C++ exception in the bridge).
pub const Error = error{
    OutOfHostMemory,
    OutOfDeviceMemory,
    /// `mapMemory` on non-host-visible memory (e.g. `.gpu_only`), or a map failure.
    MappingFailed,
    /// The allocator (or VMA init) could not be created.
    InitializationFailed,
    Unknown,
};

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

/// A Vulkan image paired with its backing VMA allocation.
pub const ImageResult = struct {
    /// The created Vulkan image handle.
    image: vk.Image,
    /// The allocation backing it — pass to `destroyImage`.
    allocation: *Allocation,
};

// -- C-ABI bridge (src/c/vma_bridge.cpp) -------------------------------------
// Dispatchable handles cross as opaque pointers; non-dispatchable as u64 (the
// bridge is built with VK_USE_64_BIT_PTR_DEFINES=0); create-infos are passed
// by pointer (vulkan-zig's extern structs match the C layout).

extern fn vma_bridge_create_allocator(instance: ?*anyopaque, physical: ?*anyopaque, device: ?*anyopaque, api_version: u32, gipa: vk.PfnGetInstanceProcAddr, out: *?*Allocator) i32;
extern fn vma_bridge_destroy_allocator(a: *Allocator) void;
extern fn vma_bridge_create_buffer(a: *Allocator, info: *const vk.BufferCreateInfo, usage: c_int, out_buffer: *u64, out_alloc: *?*Allocation) i32;
extern fn vma_bridge_destroy_buffer(a: *Allocator, buffer: u64, alloc: *Allocation) void;
extern fn vma_bridge_create_image(a: *Allocator, info: *const vk.ImageCreateInfo, usage: c_int, out_image: *u64, out_alloc: *?*Allocation) i32;
extern fn vma_bridge_destroy_image(a: *Allocator, image: u64, alloc: *Allocation) void;
extern fn vma_bridge_map_memory(a: *Allocator, alloc: *Allocation, out_ptr: *?*anyopaque) i32;
extern fn vma_bridge_unmap_memory(a: *Allocator, alloc: *Allocation) void;

/// Translate the bridge's `VkResult` into `Error` (or success). Uses
/// vulkan-zig's `vk.Result` values, so there are no magic numbers.
fn check(result: i32) Error!void {
    return switch (result) {
        @intFromEnum(vk.Result.success) => {},
        @intFromEnum(vk.Result.error_out_of_host_memory) => Error.OutOfHostMemory,
        @intFromEnum(vk.Result.error_out_of_device_memory) => Error.OutOfDeviceMemory,
        @intFromEnum(vk.Result.error_memory_map_failed) => Error.MappingFailed,
        @intFromEnum(vk.Result.error_initialization_failed) => Error.InitializationFailed,
        else => Error.Unknown,
    };
}

/// Dispatchable Vulkan handle (`enum(usize)`) → the opaque pointer the C ABI wants.
inline fn handlePtr(h: anytype) ?*anyopaque {
    return @ptrFromInt(@intFromEnum(h));
}

/// Create a VMA allocator. Caller owns it — release with `destroyAllocator`.
/// Requires a prior `volk.loadBase()` (VMA loads its entry points dynamically).
pub fn createAllocator(info: AllocatorCreateInfo) Error!*Allocator {
    var out: ?*Allocator = null;
    try check(vma_bridge_create_allocator(
        handlePtr(info.instance),
        handlePtr(info.physical_device),
        handlePtr(info.device),
        info.api_version,
        volk.getInstanceProcAddr(),
        &out,
    ));
    return out.?;
}

/// Destroy a VMA allocator. Destroy all buffers/images created from it first.
pub fn destroyAllocator(allocator: *Allocator) void {
    vma_bridge_destroy_allocator(allocator);
}

/// Allocate memory and create a `vk.Buffer` in one call. `info` is a standard
/// `VkBufferCreateInfo`; `usage` selects the memory type. *(since v0.3.0)*
pub fn createBuffer(allocator: *Allocator, info: *const vk.BufferCreateInfo, usage: Usage) Error!BufferResult {
    var buffer: u64 = 0;
    var alloc: ?*Allocation = null;
    try check(vma_bridge_create_buffer(allocator, info, @intFromEnum(usage), &buffer, &alloc));
    return .{ .buffer = @enumFromInt(buffer), .allocation = alloc.? };
}

/// Destroy a buffer and free its allocation (the pair from `createBuffer`).
pub fn destroyBuffer(allocator: *Allocator, buffer: vk.Buffer, allocation: *Allocation) void {
    vma_bridge_destroy_buffer(allocator, @intFromEnum(buffer), allocation);
}

/// Allocate memory and create a `vk.Image` in one call. *(since v0.3.0)*
pub fn createImage(allocator: *Allocator, info: *const vk.ImageCreateInfo, usage: Usage) Error!ImageResult {
    var image: u64 = 0;
    var alloc: ?*Allocation = null;
    try check(vma_bridge_create_image(allocator, info, @intFromEnum(usage), &image, &alloc));
    return .{ .image = @enumFromInt(image), .allocation = alloc.? };
}

/// Destroy an image and free its allocation (the pair from `createImage`).
pub fn destroyImage(allocator: *Allocator, image: vk.Image, allocation: *Allocation) void {
    vma_bridge_destroy_image(allocator, @intFromEnum(image), allocation);
}

/// Map a host-visible allocation and return a pointer to its bytes. Pair with
/// `unmapMemory`. Mapping `gpu_only` memory fails with `Error.MappingFailed`.
/// *(since v0.3.0)*
pub fn mapMemory(allocator: *Allocator, allocation: *Allocation) Error![*]u8 {
    var ptr: ?*anyopaque = null;
    try check(vma_bridge_map_memory(allocator, allocation, &ptr));
    return @ptrCast(ptr.?);
}

/// Unmap a previously `mapMemory`'d allocation.
pub fn unmapMemory(allocator: *Allocator, allocation: *Allocation) void {
    vma_bridge_unmap_memory(allocator, allocation);
}

test {
    std.testing.refAllDecls(@This());
}
