//! Ladder step 7 — **opt-in swapchain abstraction** (`Swapchain.create` /
//! `deinit` / `recreate` / `toRaw` / `buildCreateInfo`). *(v0.6.0)* The
//! create/recreate path needs a **real surface** (hence a window), so its live
//! behavior is a device e2e in `docs/manual-testing.md` — the headless `VkCtx`
//! has no surface. What's provable in-process and pinned here: the default
//! policy values, and the **raw-first invariant** — `buildCreateInfo`/`toRaw`
//! yield the *raw* `vk.SwapchainCreateInfoKHR`, never a wrapper type, so a
//! consumer can hand the result straight to `vkd.createSwapchainKHR`. See
//! `CONTRIBUTING.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const vk = @import("vulkan");
const h = @import("harness.zig");
const gate = h.gate;

const Swapchain = vk_stack.Swapchain;

const done = .{
    .create = false,
    .deinit = false,
    .recreate = false,
    .toRaw = false,
    .buildCreateInfo = false,
};

// --- Options policy --------------------------------------------------------

// WHEN reading a default Options · GIVEN the swapchain helper · THEN it prefers an sRGB BGRA format and mailbox present mode, with image count auto (0 → minImageCount+1).
test "Options: sane defaults (sRGB BGRA, mailbox, auto image count)" {
    try gate(done.create);
    const o: Swapchain.Options = .{};
    try std.testing.expectEqual(vk.Format.b8g8r8a8_srgb, o.preferred_format.format);
    try std.testing.expectEqual(vk.ColorSpaceKHR.srgb_nonlinear_khr, o.preferred_format.color_space);
    try std.testing.expectEqual(vk.PresentModeKHR.mailbox_khr, o.preferred_present_mode);
    try std.testing.expectEqual(@as(u32, 0), o.desired_image_count);
}

// --- create / deinit -------------------------------------------------------

// WHEN creating a swapchain on a surface · GIVEN a device + surface · THEN it yields one image view per image. *(e2e: needs a windowed surface)*
test "create: one image view per swapchain image" {
    try gate(done.create);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    var sc = try Swapchain.create(std.testing.allocator, ctx.vki, ctx.vkd, ctx.physical, ctx.device, .null_handle, .{});
    defer sc.deinit(std.testing.allocator, ctx.vkd, ctx.device);
    try std.testing.expectEqual(sc.images.len, sc.views.len);
    try std.testing.expect(sc.images.len > 0);
}

// WHEN deinit-ing then creating again · GIVEN a device + surface · THEN a fresh swapchain is obtainable (clean teardown). *(e2e: needs a windowed surface)*
test "deinit: a swapchain can be created again after teardown" {
    try gate(done.create and done.deinit);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    var first = try Swapchain.create(std.testing.allocator, ctx.vki, ctx.vkd, ctx.physical, ctx.device, .null_handle, .{});
    first.deinit(std.testing.allocator, ctx.vkd, ctx.device);
    var second = try Swapchain.create(std.testing.allocator, ctx.vki, ctx.vkd, ctx.physical, ctx.device, .null_handle, .{});
    defer second.deinit(std.testing.allocator, ctx.vkd, ctx.device);
}

// --- recreate --------------------------------------------------------------

// WHEN recreating after a resize · GIVEN an existing swapchain · THEN it succeeds and the handle is refreshed. *(e2e: needs a windowed surface)*
test "recreate: refreshes the swapchain in place" {
    try gate(done.create and done.recreate);
    var ctx = try h.VkCtx.init();
    defer ctx.deinit();
    var sc = try Swapchain.create(std.testing.allocator, ctx.vki, ctx.vkd, ctx.physical, ctx.device, .null_handle, .{});
    defer sc.deinit(std.testing.allocator, ctx.vkd, ctx.device);
    try sc.recreate(std.testing.allocator, ctx.vki, ctx.vkd, ctx.physical, ctx.device, .null_handle);
}

// --- toRaw (bridge) --------------------------------------------------------

// WHEN inspecting Raw.create_info · GIVEN the bridge type · THEN it is the raw `vk.SwapchainCreateInfoKHR`, not a wrapper (drop-to-raw invariant).
test "toRaw: exposes the raw vk.SwapchainCreateInfoKHR used" {
    try gate(done.toRaw);
    const CreateInfoField = @TypeOf(@as(Swapchain.Raw, undefined).create_info);
    try std.testing.expectEqual(vk.SwapchainCreateInfoKHR, CreateInfoField);
    const HandleField = @TypeOf(@as(Swapchain.Raw, undefined).handle);
    try std.testing.expectEqual(vk.SwapchainKHR, HandleField);
}

// --- buildCreateInfo (pro tier) --------------------------------------------

// WHEN inspecting buildCreateInfo's type · GIVEN the pro-tier API · THEN it returns a raw `SwapchainError!vk.SwapchainCreateInfoKHR` — feedable straight to `vkd.createSwapchainKHR`, creating nothing itself.
test "buildCreateInfo: returns a raw create-info (raw path never blocked)" {
    try gate(done.buildCreateInfo);
    // Coercion pins the contract: returns the raw create-info type, no wrapper.
    const expected: *const fn (vk.InstanceWrapper, vk.PhysicalDevice, vk.SurfaceKHR, Swapchain.Options) vk_stack.SwapchainError!vk.SwapchainCreateInfoKHR = Swapchain.buildCreateInfo;
    _ = expected;
}
