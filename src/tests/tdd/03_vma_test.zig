//! Ladder — **VMA** (`createAllocator`/`destroyAllocator`, `createBuffer`/
//! `destroyBuffer`, `createImage`/`destroyImage`, `mapMemory`/`unmapMemory`).
//! *(v0.3.0)* Gated; uses the headless `VkCtx` (so it assumes volk is already
//! implemented — flip these flags only after the volk step, per the ladder).
//! The `destroy*`/`unmapMemory` calls are covered via the `defer`s in the
//! create/map tests. See `CONTRIBUTING.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const vk = @import("vulkan");
const h = @import("harness.zig");
const gate = h.gate;
const vma = vk_stack.vma;

const done = .{
    .createAllocator = false,
    .destroyAllocator = false,
    .createBuffer = false,
    .destroyBuffer = false,
    .createImage = false,
    .destroyImage = false,
    .mapMemory = false,
    .unmapMemory = false,
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
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = .{ .sampled_bit = true, .transfer_dst_bit = true },
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };
}

// --- createAllocator / destroyAllocator ------------------------------------

test "createAllocator: returns a non-null allocator" {
    try gate(done.createAllocator and done.destroyAllocator);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    try std.testing.expect(@intFromPtr(a) != 0);
}

test "createAllocator: defaults to the Vulkan 1.3 api_version" {
    try gate(done.createAllocator and done.destroyAllocator);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const info = ctx.allocInfo();
    try std.testing.expectEqual(@as(u32, @bitCast(vk.API_VERSION_1_3)), info.api_version);
    const a = try vma.createAllocator(info);
    defer vma.destroyAllocator(a);
}

test "createAllocator: create→destroy→create again is clean" {
    try gate(done.createAllocator and done.destroyAllocator);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    vma.destroyAllocator(a);
    const b = try vma.createAllocator(ctx.allocInfo());
    vma.destroyAllocator(b);
}

// --- createBuffer / destroyBuffer ------------------------------------------

test "createBuffer: a cpu_to_gpu buffer is non-null with an allocation" {
    try gate(done.createAllocator and done.destroyAllocator and done.createBuffer and done.destroyBuffer);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(256, .{ .transfer_src_bit = true });
    const res = try vma.createBuffer(a, &info, .cpu_to_gpu);
    defer vma.destroyBuffer(a, res.buffer, res.allocation);
    try std.testing.expect(res.buffer != .null_handle);
    try std.testing.expect(@intFromPtr(res.allocation) != 0);
}

test "createBuffer: a gpu_only vertex buffer is created" {
    try gate(done.createAllocator and done.destroyAllocator and done.createBuffer and done.destroyBuffer);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(1024, .{ .vertex_buffer_bit = true, .transfer_dst_bit = true });
    const res = try vma.createBuffer(a, &info, .gpu_only);
    defer vma.destroyBuffer(a, res.buffer, res.allocation);
    try std.testing.expect(res.buffer != .null_handle);
}

test "createBuffer: two buffers get distinct handles" {
    try gate(done.createAllocator and done.destroyAllocator and done.createBuffer and done.destroyBuffer);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(128, .{ .uniform_buffer_bit = true });
    const x = try vma.createBuffer(a, &info, .cpu_to_gpu);
    defer vma.destroyBuffer(a, x.buffer, x.allocation);
    const y = try vma.createBuffer(a, &info, .cpu_to_gpu);
    defer vma.destroyBuffer(a, y.buffer, y.allocation);
    try std.testing.expect(x.buffer != y.buffer);
}

// --- createImage / destroyImage --------------------------------------------

test "createImage: a gpu_only 2D image is non-null with an allocation" {
    try gate(done.createAllocator and done.destroyAllocator and done.createImage and done.destroyImage);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = imageInfo();
    const res = try vma.createImage(a, &info, .gpu_only);
    defer vma.destroyImage(a, res.image, res.allocation);
    try std.testing.expect(res.image != .null_handle);
    try std.testing.expect(@intFromPtr(res.allocation) != 0);
}

test "createImage: two images get distinct handles" {
    try gate(done.createAllocator and done.destroyAllocator and done.createImage and done.destroyImage);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = imageInfo();
    const x = try vma.createImage(a, &info, .gpu_only);
    defer vma.destroyImage(a, x.image, x.allocation);
    const y = try vma.createImage(a, &info, .gpu_only);
    defer vma.destroyImage(a, y.image, y.allocation);
    try std.testing.expect(x.image != y.image);
}

test "createImage: a sampled+transfer-dst image is created" {
    try gate(done.createAllocator and done.destroyAllocator and done.createImage and done.destroyImage);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = imageInfo();
    const res = try vma.createImage(a, &info, .gpu_only);
    defer vma.destroyImage(a, res.image, res.allocation);
    try std.testing.expect(res.image != .null_handle);
}

// --- mapMemory / unmapMemory -----------------------------------------------

test "mapMemory: mapping a cpu_to_gpu allocation returns a non-null pointer" {
    try gate(done.createAllocator and done.destroyAllocator and done.createBuffer and done.destroyBuffer and done.mapMemory and done.unmapMemory);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(64, .{ .transfer_src_bit = true });
    const res = try vma.createBuffer(a, &info, .cpu_to_gpu);
    defer vma.destroyBuffer(a, res.buffer, res.allocation);
    const ptr = try vma.mapMemory(a, res.allocation);
    defer vma.unmapMemory(a, res.allocation);
    try std.testing.expect(@intFromPtr(ptr) != 0);
}

test "mapMemory: host-visible memory round-trips a byte pattern" {
    try gate(done.createAllocator and done.destroyAllocator and done.createBuffer and done.destroyBuffer and done.mapMemory and done.unmapMemory);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(4, .{ .transfer_src_bit = true });
    const res = try vma.createBuffer(a, &info, .cpu_to_gpu);
    defer vma.destroyBuffer(a, res.buffer, res.allocation);

    const w = try vma.mapMemory(a, res.allocation);
    w[0] = 0xAB;
    w[1] = 0xCD;
    vma.unmapMemory(a, res.allocation);

    const r = try vma.mapMemory(a, res.allocation);
    defer vma.unmapMemory(a, res.allocation);
    try std.testing.expectEqual(@as(u8, 0xAB), r[0]);
    try std.testing.expectEqual(@as(u8, 0xCD), r[1]);
}

test "mapMemory: a mapped allocation can be unmapped and remapped" {
    try gate(done.createAllocator and done.destroyAllocator and done.createBuffer and done.destroyBuffer and done.mapMemory and done.unmapMemory);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    const a = try vma.createAllocator(ctx.allocInfo());
    defer vma.destroyAllocator(a);
    const info = bufferInfo(32, .{ .transfer_src_bit = true });
    const res = try vma.createBuffer(a, &info, .cpu_to_gpu);
    defer vma.destroyBuffer(a, res.buffer, res.allocation);
    const p1 = try vma.mapMemory(a, res.allocation);
    try std.testing.expect(@intFromPtr(p1) != 0);
    vma.unmapMemory(a, res.allocation);
    const p2 = try vma.mapMemory(a, res.allocation);
    defer vma.unmapMemory(a, res.allocation);
    try std.testing.expect(@intFromPtr(p2) != 0);
}
