//! Ladder — **volk** (`loadBase` / `getInstanceProcAddr` / `loadInstance` /
//! `loadDevice`). *(v0.2.0)* Gated; needs a Vulkan loader (`libvulkan`) at
//! runtime, and for loadInstance/loadDevice a headless instance+device built
//! by `VkCtx`. See `CONTRIBUTING.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const h = @import("harness.zig");
const gate = h.gate;
const volk = vk_stack.volk;

const done = .{
    .loadBase = true,
    .getInstanceProcAddr = true,
    .loadInstance = true,
    .loadDevice = true,
};

// --- loadBase --------------------------------------------------------------

test "loadBase: succeeds when a Vulkan loader is present" {
    try gate(done.loadBase);
    try volk.loadBase();
}

test "loadBase: is idempotent (callable twice)" {
    try gate(done.loadBase);
    try volk.loadBase();
    try volk.loadBase();
}

test "loadBase: enables getInstanceProcAddr" {
    try gate(done.loadBase and done.getInstanceProcAddr);
    try volk.loadBase();
    _ = volk.getInstanceProcAddr();
}

// --- getInstanceProcAddr ---------------------------------------------------

test "getInstanceProcAddr: resolves a core command (vkCreateInstance)" {
    try gate(done.loadBase and done.getInstanceProcAddr);
    try volk.loadBase();
    const gipa = volk.getInstanceProcAddr();
    try std.testing.expect(gipa(.null_handle, "vkCreateInstance") != null);
}

test "getInstanceProcAddr: resolves a global command (vkEnumerateInstanceVersion)" {
    try gate(done.loadBase and done.getInstanceProcAddr);
    try volk.loadBase();
    const gipa = volk.getInstanceProcAddr();
    try std.testing.expect(gipa(.null_handle, "vkEnumerateInstanceVersion") != null);
}

test "getInstanceProcAddr: an unknown symbol resolves to null" {
    try gate(done.loadBase and done.getInstanceProcAddr);
    try volk.loadBase();
    const gipa = volk.getInstanceProcAddr();
    try std.testing.expect(gipa(.null_handle, "vkNotARealFunction") == null);
}

// --- loadInstance (exercised by standing up a context) ---------------------

test "loadInstance: a context builds and exposes a non-null instance" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    try std.testing.expect(@intFromEnum(ctx.instance) != 0);
}

test "loadInstance: instance-level commands resolve (enumeratePhysicalDevices)" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    var count: u32 = 0;
    _ = try ctx.vki.enumeratePhysicalDevices(ctx.instance, &count, null);
    try std.testing.expect(count > 0);
}

test "loadInstance: a physical device was selected" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    try std.testing.expect(@intFromEnum(ctx.physical) != 0);
}

// --- loadDevice ------------------------------------------------------------

test "loadDevice: the logical device is non-null" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance and done.loadDevice);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    try std.testing.expect(@intFromEnum(ctx.device) != 0);
}

test "loadDevice: a device-level command resolves and runs (deviceWaitIdle)" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance and done.loadDevice);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    try ctx.vkd.deviceWaitIdle(ctx.device);
}

test "loadDevice: device dispatch survives a second wait" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance and done.loadDevice);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    try ctx.vkd.deviceWaitIdle(ctx.device);
    try ctx.vkd.deviceWaitIdle(ctx.device);
}
