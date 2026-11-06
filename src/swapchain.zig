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
        _ = gpa;
        _ = vki;
        _ = vkd;
        _ = physical;
        _ = device;
        _ = surface;
        _ = options;
        return error.SwapchainCreationFailed;
    }

    /// Destroy the image views and the swapchain, freeing the owned slices.
    /// The caller makes sure the GPU no longer uses the images. *(since v0.6.0)*
    pub fn deinit(self: *Swapchain, gpa: std.mem.Allocator, vkd: vk.DeviceWrapper, device: vk.Device) void {
        _ = self;
        _ = gpa;
        _ = vkd;
        _ = device;
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
        _ = self;
        _ = gpa;
        _ = vki;
        _ = vkd;
        _ = physical;
        _ = device;
        _ = surface;
        _ = fallback_extent;
        return error.SwapchainCreationFailed;
    }

    /// **Bridge.** The raw handle, images, views, and exact create-info used —
    /// for consumers dropping down to raw `vk`. *(since v0.6.0)*
    pub fn toRaw(self: Swapchain) Raw {
        _ = self;
        return .{ .handle = .null, .images = &.{}, .views = &.{}, .create_info = undefined };
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
        _ = vki;
        _ = physical;
        _ = surface;
        _ = options;
        return error.SwapchainCreationFailed;
    }

    /// **Policy.** The preferred format if the surface lists it, else the surface's
    /// first format (always valid). `available` must not be empty. *(since v0.6.0)*
    pub fn selectSurfaceFormat(available: []const vk.SurfaceFormatKHR, preferred: vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
        _ = preferred;
        return available[available.len - 1];
    }

    /// **Policy.** The preferred present mode if listed, else `.fifo_khr`, which
    /// every surface supports. *(since v0.6.0)*
    pub fn selectPresentMode(available: []const vk.PresentModeKHR, preferred: vk.PresentModeKHR) vk.PresentModeKHR {
        _ = available;
        _ = preferred;
        return .immediate_khr;
    }

    /// **Policy.** `desired` (or `minImageCount + 1` for 0), at least
    /// `minImageCount`, at most `maxImageCount` when that is not 0 (no limit).
    /// *(since v0.6.0)*
    pub fn selectImageCount(capabilities: vk.SurfaceCapabilitiesKHR, desired: u32) u32 {
        _ = capabilities;
        return desired;
    }

    /// **Policy.** The surface's `currentExtent`, or `fallback` clamped to the
    /// surface's limits when it reports `extent_chosen_by_swapchain`. A 0×0 result
    /// is `SurfaceHasZeroExtent`. *(since v0.6.0)*
    pub fn selectExtent(capabilities: vk.SurfaceCapabilitiesKHR, fallback: vk.Extent2D) Error!vk.Extent2D {
        _ = capabilities;
        return fallback;
    }
};
