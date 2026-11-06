//! Ladder step 7 — **opt-in swapchain abstraction** (`Swapchain.create` /
//! `deinit` / `recreate` / `toRaw` / `buildCreateInfo`, and the `select*` policy).
//! *(v0.6.0)* The policy is tested as pure functions. The create / recreate /
//! acquire path runs on a real `VkSurfaceKHR` from `VK_EXT_headless_surface`
//! (`harness.HeadlessSurfaceContext`, lavapipe in CI), so it needs no window; a
//! driver without that extension skips those tests. Presenting to a window stays
//! a device e2e in `docs/manual-testing.md`. The **raw-first invariant** is pinned
//! too: `buildCreateInfo`/`toRaw` yield the *raw* `vk.SwapchainCreateInfoKHR`,
//! never a wrapper type. See `CONTRIBUTING.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const vk = @import("vulkan");
const h = @import("harness.zig");
const gate = h.gate;

const Swapchain = vk_stack.Swapchain;

const done = .{
    .create = true,
    .deinit = true,
    .recreate = true,
    .toRaw = true,
    .buildCreateInfo = true,
    .select = true,
};

const test_extent: vk.Extent2D = .{ .width = 640, .height = 480 };

fn capabilitiesWith(current_extent: vk.Extent2D, min_image_count: u32, max_image_count: u32) vk.SurfaceCapabilitiesKHR {
    return .{
        .min_image_count = min_image_count,
        .max_image_count = max_image_count,
        .current_extent = current_extent,
        .min_image_extent = .{ .width = 16, .height = 16 },
        .max_image_extent = .{ .width = 4096, .height = 2048 },
        .max_image_array_layers = 1,
        .supported_transforms = .{ .identity_khr = true },
        .current_transform = .{ .identity_khr = true },
        .supported_composite_alpha = .{ .opaque_khr = true },
        .supported_usage_flags = .{ .color_attachment = true, .transfer_dst = true },
    };
}

/// Acquires one image with a fence and waits for it, proving the swapchain is usable.
fn acquireOneImage(context: *h.HeadlessSurfaceContext, swapchain: *const Swapchain) !u32 {
    const fence = try context.vkd.createFence(context.device, &.{}, null);
    defer context.vkd.destroyFence(context.device, fence, null);
    const acquired = try context.vkd.acquireNextImageKHR(context.device, swapchain.handle, std.time.ns_per_s, .null, fence);
    _ = try context.vkd.waitForFences(context.device, &.{fence}, .true, std.time.ns_per_s);
    try std.testing.expect(acquired.image_index < swapchain.images.len);
    return acquired.image_index;
}

// --- Options policy --------------------------------------------------------

// WHEN reading a default Options · GIVEN the swapchain helper · THEN it prefers an sRGB BGRA format and mailbox present mode, with image count auto (0 → minImageCount+1) and color-attachment + transfer-dst usage.
test "Options: sane defaults (sRGB BGRA, mailbox, auto image count)" {
    try gate(done.create);
    const o: Swapchain.Options = .{};
    try std.testing.expectEqual(vk.Format.b8g8r8a8_srgb, o.preferred_format.format);
    try std.testing.expectEqual(vk.ColorSpaceKHR.srgb_nonlinear_khr, o.preferred_format.color_space);
    try std.testing.expectEqual(vk.PresentModeKHR.mailbox_khr, o.preferred_present_mode);
    try std.testing.expectEqual(@as(u32, 0), o.desired_image_count);
    try std.testing.expect(o.image_usage.color_attachment and o.image_usage.transfer_dst);
}

// WHEN selecting a surface format · GIVEN the preferred one is listed, then not · THEN it takes the preferred one, else the first listed.
test "selectSurfaceFormat: preferred if listed, else the first" {
    try gate(done.select);
    const unorm: vk.SurfaceFormatKHR = .{ .format = .r8g8b8a8_unorm, .color_space = .srgb_nonlinear_khr };
    const srgb: vk.SurfaceFormatKHR = .{ .format = .b8g8r8a8_srgb, .color_space = .srgb_nonlinear_khr };
    try std.testing.expectEqual(srgb, Swapchain.selectSurfaceFormat(&.{ unorm, srgb }, srgb));
    const other: vk.SurfaceFormatKHR = .{ .format = .r16g16b16a16_sfloat, .color_space = .srgb_nonlinear_khr };
    try std.testing.expectEqual(unorm, Swapchain.selectSurfaceFormat(&.{ unorm, other }, srgb));
}

// WHEN selecting a present mode · GIVEN the preferred one is listed, then not · THEN it takes the preferred one, else FIFO.
test "selectPresentMode: preferred if listed, else FIFO" {
    try gate(done.select);
    try std.testing.expectEqual(vk.PresentModeKHR.mailbox_khr, Swapchain.selectPresentMode(&.{ .fifo_khr, .mailbox_khr }, .mailbox_khr));
    try std.testing.expectEqual(vk.PresentModeKHR.fifo_khr, Swapchain.selectPresentMode(&.{ .immediate_khr, .fifo_khr }, .mailbox_khr));
    try std.testing.expectEqual(vk.PresentModeKHR.fifo_khr, Swapchain.selectPresentMode(&.{}, .immediate_khr));
}

// WHEN selecting an image count · GIVEN auto, too few, too many, and no upper limit · THEN it clamps into [min, max] (max 0 = no limit).
test "selectImageCount: auto is min + 1, clamped to the surface's range" {
    try gate(done.select);
    const extent = test_extent;
    try std.testing.expectEqual(@as(u32, 3), Swapchain.selectImageCount(capabilitiesWith(extent, 2, 8), 0));
    try std.testing.expectEqual(@as(u32, 2), Swapchain.selectImageCount(capabilitiesWith(extent, 2, 8), 1));
    try std.testing.expectEqual(@as(u32, 8), Swapchain.selectImageCount(capabilitiesWith(extent, 2, 8), 20));
    try std.testing.expectEqual(@as(u32, 2), Swapchain.selectImageCount(capabilitiesWith(extent, 2, 2), 0));
    try std.testing.expectEqual(@as(u32, 20), Swapchain.selectImageCount(capabilitiesWith(extent, 2, 0), 20));
}

// WHEN selecting an extent · GIVEN a fixed current extent, a swapchain-chosen one, and a 0×0 surface · THEN current wins, else the fallback is clamped, and 0×0 is SurfaceHasZeroExtent.
test "selectExtent: current extent, else the clamped fallback; 0x0 is an error" {
    try gate(done.select);
    const fixed = capabilitiesWith(.{ .width = 1024, .height = 768 }, 2, 8);
    try std.testing.expectEqual(vk.Extent2D{ .width = 1024, .height = 768 }, try Swapchain.selectExtent(fixed, test_extent));
    const chosen = vk_stack.swapchain_extent_chosen_by_swapchain;
    const free = capabilitiesWith(.{ .width = chosen, .height = chosen }, 2, 8);
    try std.testing.expectEqual(test_extent, try Swapchain.selectExtent(free, test_extent));
    try std.testing.expectEqual(vk.Extent2D{ .width = 4096, .height = 16 }, try Swapchain.selectExtent(free, .{ .width = 9000, .height = 1 }));
    const minimized = capabilitiesWith(.{ .width = 0, .height = 0 }, 2, 8);
    try std.testing.expectError(error.SurfaceHasZeroExtent, Swapchain.selectExtent(minimized, test_extent));
}

// --- create / deinit -------------------------------------------------------

// WHEN creating a swapchain on a headless surface · GIVEN a device with VK_KHR_swapchain · THEN it yields one image view per image, the fallback extent, and an image that can be acquired.
test "create: one image view per swapchain image, sized by the fallback extent" {
    try gate(done.create);
    var context = try h.HeadlessSurfaceContext.init(std.testing.allocator);
    defer context.deinit();
    var sc = try Swapchain.create(std.testing.allocator, context.vki, context.vkd, context.physical, context.device, context.surface, .{ .fallback_extent = test_extent });
    defer sc.deinit(std.testing.allocator, context.vkd, context.device);
    try std.testing.expectEqual(sc.images.len, sc.views.len);
    try std.testing.expect(sc.images.len > 0);
    try std.testing.expectEqual(test_extent, sc.extent);
    try std.testing.expect(sc.create_info.image_usage.color_attachment);
    _ = try acquireOneImage(&context, &sc);
}

// WHEN deinit-ing then creating again · GIVEN a device + surface · THEN a fresh swapchain is obtainable (clean teardown).
test "deinit: a swapchain can be created again after teardown" {
    try gate(done.create and done.deinit);
    var context = try h.HeadlessSurfaceContext.init(std.testing.allocator);
    defer context.deinit();
    var first = try Swapchain.create(std.testing.allocator, context.vki, context.vkd, context.physical, context.device, context.surface, .{});
    first.deinit(std.testing.allocator, context.vkd, context.device);
    var second = try Swapchain.create(std.testing.allocator, context.vki, context.vkd, context.physical, context.device, context.surface, .{});
    defer second.deinit(std.testing.allocator, context.vkd, context.device);
    try std.testing.expect(second.images.len > 0);
}

// --- recreate --------------------------------------------------------------

// WHEN recreating after a resize · GIVEN an existing swapchain with an acquired image · THEN it takes the new size, a new handle, and the new images can be acquired.
test "recreate: takes the new size and stays usable" {
    try gate(done.create and done.recreate);
    var context = try h.HeadlessSurfaceContext.init(std.testing.allocator);
    defer context.deinit();
    var sc = try Swapchain.create(std.testing.allocator, context.vki, context.vkd, context.physical, context.device, context.surface, .{ .fallback_extent = test_extent });
    defer sc.deinit(std.testing.allocator, context.vkd, context.device);
    _ = try acquireOneImage(&context, &sc);
    const old_handle = sc.handle;

    const resized: vk.Extent2D = .{ .width = 320, .height = 200 };
    try sc.recreate(std.testing.allocator, context.vki, context.vkd, context.physical, context.device, context.surface, resized);
    try std.testing.expect(sc.handle != old_handle);
    try std.testing.expectEqual(resized, sc.extent);
    try std.testing.expectEqual(resized, sc.options.fallback_extent);
    try std.testing.expectEqual(sc.images.len, sc.views.len);
    try std.testing.expectEqual(old_handle, sc.create_info.old_swapchain);
    _ = try acquireOneImage(&context, &sc);
}

// WHEN recreating to a 0×0 size · GIVEN a swapchain-chosen extent · THEN it is SurfaceHasZeroExtent and the old swapchain is kept.
test "recreate: a zero size is an error and keeps the old swapchain" {
    try gate(done.create and done.recreate);
    var context = try h.HeadlessSurfaceContext.init(std.testing.allocator);
    defer context.deinit();
    var sc = try Swapchain.create(std.testing.allocator, context.vki, context.vkd, context.physical, context.device, context.surface, .{ .fallback_extent = test_extent });
    defer sc.deinit(std.testing.allocator, context.vkd, context.device);
    const old_handle = sc.handle;
    try std.testing.expectError(
        error.SurfaceHasZeroExtent,
        sc.recreate(std.testing.allocator, context.vki, context.vkd, context.physical, context.device, context.surface, .{ .width = 0, .height = 0 }),
    );
    try std.testing.expectEqual(old_handle, sc.handle);
    try std.testing.expectEqual(test_extent, sc.extent);
    _ = try acquireOneImage(&context, &sc);
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

// WHEN calling toRaw on a live swapchain · GIVEN a headless surface · THEN it hands back the same handle, images, views, and the create-info used.
test "toRaw: the live handle, images, views, and create-info" {
    try gate(done.create and done.toRaw);
    var context = try h.HeadlessSurfaceContext.init(std.testing.allocator);
    defer context.deinit();
    var sc = try Swapchain.create(std.testing.allocator, context.vki, context.vkd, context.physical, context.device, context.surface, .{ .fallback_extent = test_extent });
    defer sc.deinit(std.testing.allocator, context.vkd, context.device);
    const raw = sc.toRaw();
    try std.testing.expectEqual(sc.handle, raw.handle);
    try std.testing.expectEqualSlices(vk.Image, sc.images, raw.images);
    try std.testing.expectEqualSlices(vk.ImageView, sc.views, raw.views);
    try std.testing.expectEqual(test_extent, raw.create_info.image_extent);
    try std.testing.expectEqual(sc.format.format, raw.create_info.image_format);
}

// --- buildCreateInfo (pro tier) --------------------------------------------

// WHEN inspecting buildCreateInfo's type · GIVEN the pro-tier API · THEN it returns a raw `SwapchainError!vk.SwapchainCreateInfoKHR` — feedable straight to `vkd.createSwapchainKHR`, creating nothing itself.
test "buildCreateInfo: returns a raw create-info (raw path never blocked)" {
    try gate(done.buildCreateInfo);
    // Coercion pins the contract: returns the raw create-info type, no wrapper.
    const expected: *const fn (vk.InstanceWrapper, vk.PhysicalDevice, vk.SurfaceKHR, Swapchain.Options) vk_stack.SwapchainError!vk.SwapchainCreateInfoKHR = Swapchain.buildCreateInfo;
    _ = expected;
}

// WHEN building a create-info and feeding it to raw vkd.createSwapchainKHR · GIVEN a headless surface · THEN it matches what create chose, and the raw call succeeds.
test "buildCreateInfo: same policy as create, and the raw path takes it" {
    try gate(done.create and done.buildCreateInfo);
    var context = try h.HeadlessSurfaceContext.init(std.testing.allocator);
    defer context.deinit();
    const options: Swapchain.Options = .{ .fallback_extent = test_extent };
    const create_info = try Swapchain.buildCreateInfo(context.vki, context.physical, context.surface, options);
    try std.testing.expectEqual(vk.SwapchainKHR.null, create_info.old_swapchain);
    try std.testing.expectEqual(test_extent, create_info.image_extent);

    var sc = try Swapchain.create(std.testing.allocator, context.vki, context.vkd, context.physical, context.device, context.surface, options);
    defer sc.deinit(std.testing.allocator, context.vkd, context.device);
    try std.testing.expectEqual(sc.create_info.image_format, create_info.image_format);
    try std.testing.expectEqual(sc.create_info.present_mode, create_info.present_mode);
    try std.testing.expectEqual(sc.create_info.min_image_count, create_info.min_image_count);

    const raw_handle = try context.vkd.createSwapchainKHR(context.device, &create_info, null);
    context.vkd.destroySwapchainKHR(context.device, raw_handle, null);
}
