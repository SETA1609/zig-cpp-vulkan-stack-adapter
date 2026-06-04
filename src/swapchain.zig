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
//!  * **Bridge** — `toRaw` hands back the underlying handle, images, views, and
//!    the exact create-info used, so a consumer can drop to raw at any boundary.
//!
//! Boundary rule: no helper type appears in the raw signatures. All bodies
//! `@panic` until the v0.6.0 milestone lands — see `docs/ROADMAP.md`.

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
};

pub const Swapchain = struct {
    handle: vk.SwapchainKHR,
    format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,
    extent: vk.Extent2D,
    images: []vk.Image,
    views: []vk.ImageView,

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
        @panic("not implemented");
    }

    /// Destroy the image views and the swapchain, freeing the owned slices.
    /// *(since v0.6.0)*
    pub fn deinit(self: *Swapchain, gpa: std.mem.Allocator, vkd: vk.DeviceWrapper, device: vk.Device) void {
        _ = self;
        _ = gpa;
        _ = vkd;
        _ = device;
        @panic("not implemented");
    }

    /// Recreate after a resize or `error.OutOfDateKHR`, reusing the old
    /// swapchain as `oldSwapchain` for a gapless handoff. *(since v0.6.0)*
    pub fn recreate(
        self: *Swapchain,
        gpa: std.mem.Allocator,
        vki: vk.InstanceWrapper,
        vkd: vk.DeviceWrapper,
        physical: vk.PhysicalDevice,
        device: vk.Device,
        surface: vk.SurfaceKHR,
    ) Error!void {
        _ = self;
        _ = gpa;
        _ = vki;
        _ = vkd;
        _ = physical;
        _ = device;
        _ = surface;
        @panic("not implemented");
    }

    /// **Bridge.** The raw handle, images, views, and exact create-info used —
    /// for consumers dropping down to raw `vk`. *(since v0.6.0)*
    pub fn toRaw(self: Swapchain) Raw {
        _ = self;
        @panic("not implemented");
    }

    /// **Pro tier.** Compute a `VkSwapchainCreateInfoKHR` from the same default
    /// policy **without creating anything** — the consumer calls
    /// `vkd.createSwapchainKHR` itself. *(since v0.6.0)*
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
        @panic("not implemented");
    }
};
