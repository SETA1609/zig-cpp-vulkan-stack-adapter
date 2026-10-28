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

// WHEN calling volk.loadBase · GIVEN a Vulkan loader (libvulkan) is present · THEN it returns without error.
test "loadBase: succeeds when a Vulkan loader is present" {
    try gate(done.loadBase);
    try volk.loadBase();
}

// WHEN calling volk.loadBase twice in a row · GIVEN a Vulkan loader is present · THEN both calls succeed (the call is idempotent).
test "loadBase: is idempotent (callable twice)" {
    try gate(done.loadBase);
    try volk.loadBase();
    try volk.loadBase();
}

// WHEN calling getInstanceProcAddr after loadBase · GIVEN loadBase succeeded · THEN a getInstanceProcAddr function is obtainable.
test "loadBase: enables getInstanceProcAddr" {
    try gate(done.loadBase and done.getInstanceProcAddr);
    try volk.loadBase();
    _ = volk.getInstanceProcAddr();
}

// --- getInstanceProcAddr ---------------------------------------------------

// WHEN resolving "vkCreateInstance" via getInstanceProcAddr with a null handle · GIVEN loadBase succeeded · THEN a non-null function pointer is returned.
test "getInstanceProcAddr: resolves a core command (vkCreateInstance)" {
    try gate(done.loadBase and done.getInstanceProcAddr);
    try volk.loadBase();
    const gipa = volk.getInstanceProcAddr();
    try std.testing.expect(gipa(null, "vkCreateInstance") != null);
}

// WHEN resolving "vkEnumerateInstanceVersion" via getInstanceProcAddr with a null handle · GIVEN loadBase succeeded · THEN a non-null function pointer is returned.
test "getInstanceProcAddr: resolves a global command (vkEnumerateInstanceVersion)" {
    try gate(done.loadBase and done.getInstanceProcAddr);
    try volk.loadBase();
    const gipa = volk.getInstanceProcAddr();
    try std.testing.expect(gipa(null, "vkEnumerateInstanceVersion") != null);
}

// WHEN resolving the bogus name "vkNotARealFunction" via getInstanceProcAddr · GIVEN loadBase succeeded · THEN null is returned.
test "getInstanceProcAddr: an unknown symbol resolves to null" {
    try gate(done.loadBase and done.getInstanceProcAddr);
    try volk.loadBase();
    const gipa = volk.getInstanceProcAddr();
    try std.testing.expect(gipa(null, "vkNotARealFunction") == null);
}

// --- loadInstance (exercised by standing up a context) ---------------------

// WHEN building a headless VkCtx (which calls loadInstance) · GIVEN volk base+instance loading works · THEN ctx.instance is a non-null handle.
test "loadInstance: a context builds and exposes a non-null instance" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    try std.testing.expect(@intFromPtr(ctx.instance) != 0);
}

// WHEN calling the instance-level enumeratePhysicalDevices on a built VkCtx · GIVEN loadInstance wired the instance dispatch · THEN it succeeds and reports at least one physical device.
test "loadInstance: instance-level commands resolve (enumeratePhysicalDevices)" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    var count: u32 = 0;
    _ = try ctx.vki.enumeratePhysicalDevices(ctx.instance, &count, null);
    try std.testing.expect(count > 0);
}

// WHEN inspecting a built VkCtx · GIVEN loadInstance ran and a GPU was picked · THEN ctx.physical is a non-null handle.
test "loadInstance: a physical device was selected" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    try std.testing.expect(@intFromPtr(ctx.physical) != 0);
}

// --- loadDevice ------------------------------------------------------------

// WHEN inspecting a built VkCtx · GIVEN loadDevice ran on the created logical device · THEN ctx.device is a non-null handle.
test "loadDevice: the logical device is non-null" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance and done.loadDevice);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    try std.testing.expect(@intFromPtr(ctx.device) != 0);
}

// WHEN calling the device-level deviceWaitIdle on a built VkCtx · GIVEN loadDevice wired the device dispatch · THEN it resolves and returns without error.
test "loadDevice: a device-level command resolves and runs (deviceWaitIdle)" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance and done.loadDevice);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    try ctx.vkd.deviceWaitIdle(ctx.device);
}

// WHEN calling deviceWaitIdle twice on a built VkCtx · GIVEN loadDevice wired the device dispatch · THEN both calls succeed (the dispatch stays valid).
test "loadDevice: device dispatch survives a second wait" {
    try gate(done.loadBase and done.getInstanceProcAddr and done.loadInstance and done.loadDevice);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    try ctx.vkd.deviceWaitIdle(ctx.device);
    try ctx.vkd.deviceWaitIdle(ctx.device);
}
