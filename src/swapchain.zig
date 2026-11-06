//! **Opt-in swapchain abstraction** (v0.6.0) — a two-tier helper layered over
//! the raw `vk` swapchain API, which stays first-class and usable with this
//! module entirely absent (tree-shaken when unreferenced).
//!
//!  * **Beginner tier** — `Swapchain.create` picks a sane format / present mode /
//!    image count / extent from the surface's reported capabilities, creates the
//!    `VkSwapchainKHR` and its image views, and `recreate`s on resize /
//!    `error.OutOfDateKHR`.
//!  * **Pro tier** — raw `vkd.createSwapchainKHR` is never blocked.
//!    `buildCreateInfo` computes a good `VkSwapchainCreateInfoKHR` from the same
//!    policy **without creating anything**, so a consumer can drive Vulkan itself.
//!    The `select*` functions are that policy as pure functions over what the
//!    surface reports.
//!  * **Bridge** — `toRaw` hands back the underlying handle, images, views, and
//!    the exact create-info used, so a consumer can drop to raw at any boundary.
//!
//! Boundary rule: no helper type appears in the raw signatures.

const std = @import("std");
const vk = @import("vulkan");

/// Errors `Swapchain` operations can return — explicit and exhaustively
/// `switch`-able, like the rest of this library's public surface.
pub const Error = error{
    OutOfHostMemory,
    OutOfDeviceMemory,
    DeviceLost,
    SurfaceLost,
    OutOfMemory,
    SwapchainCreationFailed,
    /// The surface is 0×0 (a minimized window). Vulkan cannot create a swapchain for it;
    /// wait for a resize, then `recreate`. *(since v0.6.0)*
    SurfaceHasZeroExtent,
};

/// The surface reports this as `currentExtent` when the swapchain decides the size
/// (Wayland, headless surfaces).
pub const extent_chosen_by_swapchain = std.math.maxInt(u32);

pub const Swapchain = struct {
    handle: vk.SwapchainKHR,
    format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,
    extent: vk.Extent2D,
    images: []vk.Image,
    views: []vk.ImageView,
    /// The options it was created with; `recreate` reuses them.
    options: Options,
    /// The create-info of the current swapchain (`old_swapchain` as it was passed).
    create_info: vk.SwapchainCreateInfoKHR,

    /// Consumer preferences. The helper clamps / falls back against the surface's
    /// reported capabilities, so every field is a *wish*, not a guarantee.
    pub const Options = struct {
        preferred_format: vk.SurfaceFormatKHR = .{ .format = .b8g8r8a8_srgb, .color_space = .srgb_nonlinear_khr },
        /// Falls back to `.fifo_khr` (the only universally supported mode).
        preferred_present_mode: vk.PresentModeKHR = .mailbox_khr,
        /// `0` → `minImageCount + 1` (clamped to `maxImageCount`).
        desired_image_count: u32 = 0,
        /// Used when the surface reports `currentExtent == 0xFFFF_FFFF`.
        fallback_extent: vk.Extent2D = .{ .width = 800, .height = 600 },
        /// Usage of the swapchain images, intersected with what the surface supports.
        /// `color_attachment` is required; `transfer_dst` lets a frame start with
        /// `vkCmdClearColorImage`, and is dropped when the surface lacks it. *(since v0.6.0)*
        image_usage: vk.ImageUsageFlags = .{ .color_attachment = true, .transfer_dst = true },
    };

    /// The raw Vulkan objects behind the abstraction — the escape hatch for
    /// consumers who want to drive Vulkan directly from here on.
    pub const Raw = struct {
        handle: vk.SwapchainKHR,
        images: []const vk.Image,
        views: []const vk.ImageView,
        create_info: vk.SwapchainCreateInfoKHR,
    };

    /// **Beginner tier.** Choose policy from the surface caps, create the
    /// swapchain + one image view per image. Caller owns it — release with
    /// `deinit`. *(since v0.6.0)*
    pub fn create(
        gpa: std.mem.Allocator,
        vki: vk.InstanceWrapper,
        vkd: vk.DeviceWrapper,
        physical: vk.PhysicalDevice,
        device: vk.Device,
        surface: vk.SurfaceKHR,
        options: Options,
    ) Error!Swapchain {
        const create_info = try buildCreateInfo(vki, physical, surface, options);
        return createFromInfo(gpa, vkd, device, create_info, options);
    }

    /// Destroy the image views and the swapchain, freeing the owned slices.
    /// The caller makes sure the GPU no longer uses the images. *(since v0.6.0)*
    pub fn deinit(self: *Swapchain, gpa: std.mem.Allocator, vkd: vk.DeviceWrapper, device: vk.Device) void {
        destroyViews(vkd, device, self.views);
        vkd.destroySwapchainKHR(device, self.handle, null);
        gpa.free(self.views);
        gpa.free(self.images);
        self.* = undefined;
    }

    /// Recreate after a resize or `error.OutOfDateKHR`, reusing the old
    /// swapchain as `oldSwapchain` for a gapless handoff. `fallback_extent` is the
    /// new size for surfaces that let the swapchain choose (Wayland, headless); it
    /// replaces `options.fallback_extent`. Waits for the device to go idle before the
    /// old swapchain is destroyed. On error the old swapchain is kept and still valid.
    /// *(since v0.6.0)*
    pub fn recreate(
        self: *Swapchain,
        gpa: std.mem.Allocator,
        vki: vk.InstanceWrapper,
        vkd: vk.DeviceWrapper,
        physical: vk.PhysicalDevice,
        device: vk.Device,
        surface: vk.SurfaceKHR,
        fallback_extent: vk.Extent2D,
    ) Error!void {
        var options = self.options;
        options.fallback_extent = fallback_extent;
        var create_info = try buildCreateInfo(vki, physical, surface, options);
        create_info.old_swapchain = self.handle;
        // The old images may still be in flight; nothing below may destroy them before this.
        vkd.deviceWaitIdle(device) catch |wait_error| return mapVulkanError(wait_error);
        const replacement = try createFromInfo(gpa, vkd, device, create_info, options);
        // The retired swapchain stays valid until destroyed, so a failure above kept it usable.
        self.deinit(gpa, vkd, device);
        self.* = replacement;
    }

    /// **Bridge.** The raw handle, images, views, and exact create-info used —
    /// for consumers dropping down to raw `vk`. *(since v0.6.0)*
    pub fn toRaw(self: Swapchain) Raw {
        return .{ .handle = self.handle, .images = self.images, .views = self.views, .create_info = self.create_info };
    }

    /// **Pro tier.** Compute a `VkSwapchainCreateInfoKHR` from the same default
    /// policy **without creating anything** — the consumer calls
    /// `vkd.createSwapchainKHR` itself. `old_swapchain` is `.null`. *(since v0.6.0)*
    pub fn buildCreateInfo(
        vki: vk.InstanceWrapper,
        physical: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
        options: Options,
    ) Error!vk.SwapchainCreateInfoKHR {
        const capabilities = vki.getPhysicalDeviceSurfaceCapabilitiesKHR(physical, surface) catch |query_error|
            return mapVulkanError(query_error);

        var format_buffer: [max_listed_surface_formats]vk.SurfaceFormatKHR = undefined;
        var format_count: u32 = format_buffer.len;
        // `incomplete` (more formats than the buffer) is a success code: the first ones are enough.
        _ = vki.getPhysicalDeviceSurfaceFormatsKHR(physical, surface, &format_count, &format_buffer) catch |query_error|
            return mapVulkanError(query_error);
        if (format_count == 0) return error.SwapchainCreationFailed;

        var present_mode_buffer: [max_listed_present_modes]vk.PresentModeKHR = undefined;
        var present_mode_count: u32 = present_mode_buffer.len;
        _ = vki.getPhysicalDeviceSurfacePresentModesKHR(physical, surface, &present_mode_count, &present_mode_buffer) catch |query_error|
            return mapVulkanError(query_error);

        var image_usage = options.image_usage.intersect(capabilities.supported_usage_flags);
        if (!image_usage.color_attachment) return error.SwapchainCreationFailed;
        image_usage.color_attachment = true;

        const format = selectSurfaceFormat(format_buffer[0..format_count], options.preferred_format);
        return .{
            .surface = surface,
            .min_image_count = selectImageCount(capabilities, options.desired_image_count),
            .image_format = format.format,
            .image_color_space = format.color_space,
            .image_extent = try selectExtent(capabilities, options.fallback_extent),
            .image_array_layers = 1,
            .image_usage = image_usage,
            .image_sharing_mode = .exclusive,
            .pre_transform = capabilities.current_transform,
            .composite_alpha = selectCompositeAlpha(capabilities.supported_composite_alpha),
            .present_mode = selectPresentMode(present_mode_buffer[0..present_mode_count], options.preferred_present_mode),
            .clipped = .true,
            .old_swapchain = .null,
        };
    }

    /// **Policy.** The preferred format if the surface lists it, else the surface's
    /// first format (always valid). `available` must not be empty. *(since v0.6.0)*
    pub fn selectSurfaceFormat(available: []const vk.SurfaceFormatKHR, preferred: vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
        for (available) |candidate| {
            if (candidate.format == preferred.format and candidate.color_space == preferred.color_space) return candidate;
        }
        return available[0];
    }

    /// **Policy.** The preferred present mode if listed, else `.fifo_khr`, which
    /// every surface supports. *(since v0.6.0)*
    pub fn selectPresentMode(available: []const vk.PresentModeKHR, preferred: vk.PresentModeKHR) vk.PresentModeKHR {
        for (available) |candidate| if (candidate == preferred) return candidate;
        return .fifo_khr;
    }

    /// **Policy.** `desired` (or `minImageCount + 1` for 0), at least
    /// `minImageCount`, at most `maxImageCount` when that is not 0 (no limit).
    /// *(since v0.6.0)*
    pub fn selectImageCount(capabilities: vk.SurfaceCapabilitiesKHR, desired: u32) u32 {
        var image_count = if (desired == 0) capabilities.min_image_count + 1 else desired;
        image_count = @max(image_count, capabilities.min_image_count);
        if (capabilities.max_image_count != 0) image_count = @min(image_count, capabilities.max_image_count);
        return image_count;
    }

    /// **Policy.** The surface's `currentExtent`, or `fallback` clamped to the
    /// surface's limits when it reports `extent_chosen_by_swapchain`. A 0×0 result
    /// is `SurfaceHasZeroExtent`. *(since v0.6.0)*
    pub fn selectExtent(capabilities: vk.SurfaceCapabilitiesKHR, fallback: vk.Extent2D) Error!vk.Extent2D {
        const extent: vk.Extent2D = if (capabilities.current_extent.width != extent_chosen_by_swapchain)
            capabilities.current_extent
        else if (fallback.width == 0 or fallback.height == 0)
            // A 0x0 request stays 0x0, even when the surface's minimum is larger.
            .{ .width = 0, .height = 0 }
        else
            .{
                .width = std.math.clamp(fallback.width, capabilities.min_image_extent.width, capabilities.max_image_extent.width),
                .height = std.math.clamp(fallback.height, capabilities.min_image_extent.height, capabilities.max_image_extent.height),
            };
        if (extent.width == 0 or extent.height == 0) return error.SurfaceHasZeroExtent;
        return extent;
    }

    fn createFromInfo(
        gpa: std.mem.Allocator,
        vkd: vk.DeviceWrapper,
        device: vk.Device,
        create_info: vk.SwapchainCreateInfoKHR,
        options: Options,
    ) Error!Swapchain {
        const handle = vkd.createSwapchainKHR(device, &create_info, null) catch |create_error|
            return mapVulkanError(create_error);
        errdefer vkd.destroySwapchainKHR(device, handle, null);

        const images = vkd.getSwapchainImagesAllocKHR(device, handle, gpa) catch |query_error|
            return mapVulkanError(query_error);
        errdefer gpa.free(images);

        const views = try gpa.alloc(vk.ImageView, images.len);
        errdefer gpa.free(views);
        var created_view_count: usize = 0;
        errdefer destroyViews(vkd, device, views[0..created_view_count]);
        for (images, views) |image, *view| {
            view.* = vkd.createImageView(device, &.{
                .image = image,
                .view_type = .@"2d",
                .format = create_info.image_format,
                .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
                .subresource_range = .{
                    .aspect_mask = .{ .color = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            }, null) catch |create_error| return mapVulkanError(create_error);
            created_view_count += 1;
        }

        return .{
            .handle = handle,
            .format = .{ .format = create_info.image_format, .color_space = create_info.image_color_space },
            .present_mode = create_info.present_mode,
            .extent = create_info.image_extent,
            .images = images,
            .views = views,
            .options = options,
            .create_info = create_info,
        };
    }
};

/// Formats and present modes read per query; surfaces list far fewer.
const max_listed_surface_formats = 64;
const max_listed_present_modes = 16;

fn destroyViews(vkd: vk.DeviceWrapper, device: vk.Device, views: []const vk.ImageView) void {
    for (views) |view| vkd.destroyImageView(device, view, null);
}

/// Opaque when the surface allows it (almost every desktop surface), else the first mode it
/// supports, so creation never fails over compositing.
fn selectCompositeAlpha(supported: vk.CompositeAlphaFlagsKHR) vk.CompositeAlphaFlagsKHR {
    if (supported.opaque_khr) return .{ .opaque_khr = true };
    if (supported.inherit_khr) return .{ .inherit_khr = true };
    if (supported.pre_multiplied_khr) return .{ .pre_multiplied_khr = true };
    if (supported.post_multiplied_khr) return .{ .post_multiplied_khr = true };
    return .{ .opaque_khr = true };
}

/// The swapchain error for any Vulkan error from the calls above.
fn mapVulkanError(vulkan_error: anyerror) Error {
    return switch (vulkan_error) {
        error.OutOfHostMemory => error.OutOfHostMemory,
        error.OutOfDeviceMemory => error.OutOfDeviceMemory,
        error.OutOfMemory => error.OutOfMemory,
        error.DeviceLost => error.DeviceLost,
        error.SurfaceLostKHR => error.SurfaceLost,
        else => error.SwapchainCreationFailed,
    };
}
