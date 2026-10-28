//! Ladder — **VMA depth** (`getAllocationInfo`, `flushAllocation`,
//! `invalidateAllocation`, and the flag-bearing `createBufferWithFlags`/
//! `createImageWithFlags`). *(v0.5.0)* Extends `03_vma_test.zig`; same headless
//! `VkCtx`. These cover the operations a real frame loop needs beyond create/
//! destroy: querying where an allocation lives, persistent mapping, and the
//! flush/invalidate dance for non-coherent host memory. See `CONTRIBUTING.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const vk = @import("vulkan");
const h = @import("harness.zig");
const gate = h.gate;
const vma = vk_stack.vma;

const done = .{
    .getAllocationInfo = true,
    .flushAllocation = true,
    .invalidateAllocation = true,
    .createBufferWithFlags = true,
    .createImageWithFlags = true,
};

fn bufferInfo(size: u64, usage: vk.BufferUsageFlags) vk.BufferCreateInfo {
    return .{ .size = size, .usage = usage, .sharing_mode = .exclusive };
}

fn imageInfo() vk.ImageCreateInfo {
    return .{
        .image_type = .@"2d",
        .format = .r8g8b8a8_unorm,
        .extent = .{ .width = 4, .height = 4, .depth = 1 },
        .mip_levels = 1,
        .array_layers = 1,
        .samples = .{ .@"1" = true },
        .tiling = .optimal,
        .usage = .{ .sampled = true, .transfer_dst = true },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };
}

// --- getAllocationInfo ------------------------------------------------------

// WHEN calling getAllocationInfo on a 256-byte buffer's allocation · GIVEN a live cpu_to_gpu allocation · THEN it reports a non-null backing device_memory and a size of at least 256.
test "getAllocationInfo: reports backing device memory and a size ≥ the request" {
    try gate(done.getAllocationInfo);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(256, .{ .transfer_src = true });
    const res = try vma.createBuffer(a, &info, .cpu_to_gpu);
    defer vma.destroyBuffer(a, res.buffer, res.allocation);

    const ai = vma.getAllocationInfo(a, res.allocation);
    try std.testing.expect(ai.device_memory != .null);
    try std.testing.expect(ai.size >= 256);
}

// WHEN calling getAllocationInfo on a buffer created without the MAPPED flag · GIVEN a live cpu_to_gpu allocation · THEN its mapped_data is null.
test "getAllocationInfo: a non-mapped allocation has null mapped_data" {
    try gate(done.getAllocationInfo);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(64, .{ .transfer_src = true });
    const res = try vma.createBuffer(a, &info, .cpu_to_gpu); // no MAPPED flag
    defer vma.destroyBuffer(a, res.buffer, res.allocation);

    const ai = vma.getAllocationInfo(a, res.allocation);
    try std.testing.expect(ai.mapped_data == null);
}

// WHEN comparing getAllocationInfo for two separate allocations · GIVEN two live cpu_to_gpu buffers · THEN they differ in either device_memory block or offset.
test "getAllocationInfo: two allocations report distinct (memory, offset) placement" {
    try gate(done.getAllocationInfo);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(128, .{ .uniform_buffer = true });
    const x = try vma.createBuffer(a, &info, .cpu_to_gpu);
    defer vma.destroyBuffer(a, x.buffer, x.allocation);
    const y = try vma.createBuffer(a, &info, .cpu_to_gpu);
    defer vma.destroyBuffer(a, y.buffer, y.allocation);

    const ax = vma.getAllocationInfo(a, x.allocation);
    const ay = vma.getAllocationInfo(a, y.allocation);
    // Either a different memory block, or the same block at a different offset.
    try std.testing.expect(ax.device_memory != ay.device_memory or ax.offset != ay.offset);
}

// --- createBufferWithFlags (persistent mapping) ----------------------------

// WHEN creating a buffer via createBufferWithFlags with .mapped and host_access_sequential_write · GIVEN .auto memory usage · THEN getAllocationInfo reports a non-null persistent mapped_data.
test "createBufferWithFlags: a MAPPED auto buffer exposes a persistent pointer" {
    try gate(done.createBufferWithFlags and done.getAllocationInfo);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(64, .{ .transfer_src = true });
    const res = try vma.createBufferWithFlags(a, &info, .auto, .{
        .mapped = true,
        .host_access_sequential_write = true,
    });
    defer vma.destroyBuffer(a, res.buffer, res.allocation);

    const ai = vma.getAllocationInfo(a, res.allocation);
    try std.testing.expect(ai.mapped_data != null);
}

// WHEN writing a byte through the persistent mapped_data of a MAPPED auto buffer · GIVEN .mapped + host_access_sequential_write flags · THEN the value reads back equal to what was written.
test "createBufferWithFlags: the persistent map is writable" {
    try gate(done.createBufferWithFlags and done.getAllocationInfo);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(4, .{ .transfer_src = true });
    const res = try vma.createBufferWithFlags(a, &info, .auto, .{
        .mapped = true,
        .host_access_sequential_write = true,
    });
    defer vma.destroyBuffer(a, res.buffer, res.allocation);

    const ptr = vma.getAllocationInfo(a, res.allocation).mapped_data.?;
    ptr[0] = 0x42;
    try std.testing.expectEqual(@as(u8, 0x42), ptr[0]);
}

// --- flushAllocation / invalidateAllocation --------------------------------

// WHEN flushing offset 0 through vk.WHOLE_SIZE of a mapped buffer · GIVEN a MAPPED auto allocation · THEN flushAllocation returns without error.
test "flushAllocation: flushing the whole range of a mapped buffer succeeds" {
    try gate(done.flushAllocation and done.createBufferWithFlags);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(256, .{ .transfer_src = true });
    const res = try vma.createBufferWithFlags(a, &info, .auto, .{
        .mapped = true,
        .host_access_sequential_write = true,
    });
    defer vma.destroyBuffer(a, res.buffer, res.allocation);
    try vma.flushAllocation(a, res.allocation, 0, vk.WHOLE_SIZE);
}

// WHEN flushing a 64-byte sub-range (offset 0) of a mapped buffer · GIVEN a MAPPED auto allocation · THEN flushAllocation returns without error.
test "flushAllocation: flushing a sub-range succeeds" {
    try gate(done.flushAllocation and done.createBufferWithFlags);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(256, .{ .transfer_src = true });
    const res = try vma.createBufferWithFlags(a, &info, .auto, .{
        .mapped = true,
        .host_access_sequential_write = true,
    });
    defer vma.destroyBuffer(a, res.buffer, res.allocation);
    try vma.flushAllocation(a, res.allocation, 0, 64);
}

// WHEN invalidating offset 0 through vk.WHOLE_SIZE of a mapped readback buffer · GIVEN a MAPPED auto allocation with host_access_random · THEN invalidateAllocation returns without error.
test "invalidateAllocation: invalidating a mapped readback buffer succeeds" {
    try gate(done.invalidateAllocation and done.createBufferWithFlags);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(256, .{ .transfer_dst = true });
    const res = try vma.createBufferWithFlags(a, &info, .auto, .{
        .mapped = true,
        .host_access_random = true,
    });
    defer vma.destroyBuffer(a, res.buffer, res.allocation);
    try vma.invalidateAllocation(a, res.allocation, 0, vk.WHOLE_SIZE);
}

// --- createImageWithFlags ---------------------------------------------------

// WHEN creating an image via createImageWithFlags with .dedicated_memory · GIVEN .gpu_only usage · THEN the image is non-null and getAllocationInfo reports offset 0 (its own block).
test "createImageWithFlags: a dedicated-memory image lives at offset 0 of its own block" {
    try gate(done.createImageWithFlags and done.getAllocationInfo);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = imageInfo();
    const res = try vma.createImageWithFlags(a, &info, .gpu_only, .{ .dedicated_memory = true });
    defer vma.destroyImage(a, res.image, res.allocation);

    try std.testing.expect(res.image != .null);
    const ai = vma.getAllocationInfo(a, res.allocation);
    try std.testing.expectEqual(@as(u64, 0), ai.offset); // own block ⇒ offset 0
}

// WHEN creating an image via createImageWithFlags with no flags set · GIVEN .gpu_only usage · THEN the image is non-null.
test "createImageWithFlags: a plain (no-flags) image still allocates" {
    try gate(done.createImageWithFlags);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = imageInfo();
    const res = try vma.createImageWithFlags(a, &info, .gpu_only, .{});
    defer vma.destroyImage(a, res.image, res.allocation);
    try std.testing.expect(res.image != .null);
}
