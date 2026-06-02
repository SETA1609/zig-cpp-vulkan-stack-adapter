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

/// Allocation-create flags for `createBufferWithFlags`/`createImageWithFlags`.
/// With `Usage.auto`, VMA needs one of the `host_access_*` bits to hand back
/// host-visible (mappable) memory — set one when you intend to `mapMemory`.
/// A stable bit layout owned by this library (the bridge maps it to VMA's).
pub const Flags = packed struct(u32) {
    /// Give the allocation its own `VkDeviceMemory` block (no suballocation).
    dedicated_memory: bool = false,
    /// Keep it persistently mapped — `getAllocationInfo().mapped_data` is then
    /// valid for the allocation's lifetime (no `mapMemory`/`unmapMemory`).
    mapped: bool = false,
    /// CPU writes the memory sequentially (uploads). Picks an upload-friendly
    /// memory type under `Usage.auto`.
    host_access_sequential_write: bool = false,
    /// CPU reads/writes randomly (readback or scratch). Picks host-cached
    /// memory under `Usage.auto`.
    host_access_random: bool = false,
    _reserved: u28 = 0,
};

/// Where an allocation actually lives — from `getAllocationInfo`. `mapped_data`
/// is non-null only when the allocation was created with `Flags.mapped`.
pub const AllocationInfo = struct {
    /// Index into the device's memory types (`VkPhysicalDeviceMemoryProperties`).
    memory_type: u32,
    /// The `VkDeviceMemory` block backing it (allocations may suballocate it).
    device_memory: vk.DeviceMemory,
    /// Byte offset of this allocation within `device_memory`.
    offset: u64,
    /// Size of the allocation in bytes (≥ the requested size).
    size: u64,
    /// Persistent mapping pointer, or `null` if not `Flags.mapped`.
    mapped_data: ?[*]u8,
};

// -- C-ABI bridge (src/c/vma_bridge.cpp) -------------------------------------
// Dispatchable handles cross as opaque pointers; non-dispatchable as u64 (the
// bridge is built with VK_USE_64_BIT_PTR_DEFINES=0); create-infos are passed
// by pointer (vulkan-zig's extern structs match the C layout).

extern fn vma_bridge_create_allocator(instance: ?*anyopaque, physical: ?*anyopaque, device: ?*anyopaque, api_version: u32, gipa: vk.PfnGetInstanceProcAddr, out: *?*Allocator) i32;
extern fn vma_bridge_destroy_allocator(a: *Allocator) void;
extern fn vma_bridge_create_buffer(a: *Allocator, info: *const vk.BufferCreateInfo, usage: c_int, flags: u32, out_buffer: *u64, out_alloc: *?*Allocation) i32;
extern fn vma_bridge_destroy_buffer(a: *Allocator, buffer: u64, alloc: *Allocation) void;
extern fn vma_bridge_create_image(a: *Allocator, info: *const vk.ImageCreateInfo, usage: c_int, flags: u32, out_image: *u64, out_alloc: *?*Allocation) i32;
extern fn vma_bridge_destroy_image(a: *Allocator, image: u64, alloc: *Allocation) void;
extern fn vma_bridge_map_memory(a: *Allocator, alloc: *Allocation, out_ptr: *?*anyopaque) i32;
extern fn vma_bridge_unmap_memory(a: *Allocator, alloc: *Allocation) void;
extern fn vma_bridge_get_allocation_info(a: *Allocator, alloc: *Allocation, out_memory_type: *u32, out_device_memory: *u64, out_offset: *u64, out_size: *u64, out_mapped: *?*anyopaque) void;
extern fn vma_bridge_flush_allocation(a: *Allocator, alloc: *Allocation, offset: u64, size: u64) i32;
extern fn vma_bridge_invalidate_allocation(a: *Allocator, alloc: *Allocation, offset: u64, size: u64) i32;

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
inline fn handlePtr(handle: anytype) ?*anyopaque {
    return @ptrFromInt(@intFromEnum(handle));
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
    return createBufferWithFlags(allocator, info, usage, .{});
}

/// Like `createBuffer`, but with explicit allocation `flags` (host-access,
/// persistent `mapped`, dedicated memory). Needed to map `Usage.auto` memory.
/// *(since v0.5.0)*
pub fn createBufferWithFlags(allocator: *Allocator, info: *const vk.BufferCreateInfo, usage: Usage, flags: Flags) Error!BufferResult {
    var buffer: u64 = 0;
    var alloc: ?*Allocation = null;
    try check(vma_bridge_create_buffer(allocator, info, @intFromEnum(usage), @bitCast(flags), &buffer, &alloc));
    return .{ .buffer = @enumFromInt(buffer), .allocation = alloc.? };
}

/// Destroy a buffer and free its allocation (the pair from `createBuffer`).
pub fn destroyBuffer(allocator: *Allocator, buffer: vk.Buffer, allocation: *Allocation) void {
    vma_bridge_destroy_buffer(allocator, @intFromEnum(buffer), allocation);
}

/// Allocate memory and create a `vk.Image` in one call. *(since v0.3.0)*
pub fn createImage(allocator: *Allocator, info: *const vk.ImageCreateInfo, usage: Usage) Error!ImageResult {
    return createImageWithFlags(allocator, info, usage, .{});
}

/// Like `createImage`, but with explicit allocation `flags` (e.g.
/// `.dedicated_memory` for render targets). *(since v0.5.0)*
pub fn createImageWithFlags(allocator: *Allocator, info: *const vk.ImageCreateInfo, usage: Usage, flags: Flags) Error!ImageResult {
    var image: u64 = 0;
    var alloc: ?*Allocation = null;
    try check(vma_bridge_create_image(allocator, info, @intFromEnum(usage), @bitCast(flags), &image, &alloc));
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

/// Query where an allocation lives — its backing `VkDeviceMemory`, offset,
/// size, and (for `Flags.mapped` allocations) the persistent mapped pointer.
/// Cannot fail. *(since v0.5.0)*
pub fn getAllocationInfo(allocator: *Allocator, allocation: *Allocation) AllocationInfo {
    var memory_type: u32 = 0;
    var device_memory: u64 = 0;
    var offset: u64 = 0;
    var size: u64 = 0;
    var mapped: ?*anyopaque = null;
    vma_bridge_get_allocation_info(allocator, allocation, &memory_type, &device_memory, &offset, &size, &mapped);
    return .{
        .memory_type = memory_type,
        .device_memory = @enumFromInt(device_memory),
        .offset = offset,
        .size = size,
        .mapped_data = if (mapped) |p| @ptrCast(p) else null,
    };
}

/// Flush host writes to a range so the device sees them (no-op on
/// host-coherent memory). Pass `vk.WHOLE_SIZE` for `size` to cover offset→end.
/// *(since v0.5.0)*
pub fn flushAllocation(allocator: *Allocator, allocation: *Allocation, offset: u64, size: u64) Error!void {
    try check(vma_bridge_flush_allocation(allocator, allocation, offset, size));
}

/// Invalidate a range so the host sees device writes (no-op on host-coherent
/// memory). Pass `vk.WHOLE_SIZE` for `size` to cover offset→end. *(since v0.5.0)*
pub fn invalidateAllocation(allocator: *Allocator, allocation: *Allocation, offset: u64, size: u64) Error!void {
    try check(vma_bridge_invalidate_allocation(allocator, allocation, offset, size));
}

test {
    std.testing.refAllDecls(@This());
}
