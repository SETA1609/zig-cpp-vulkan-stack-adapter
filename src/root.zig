//! Public Zig API for the **vulkan-stack adapter** — the Vulkan stack
//! (vulkan-zig `vk` + volk + VMA + shaderc) version-pinned together and
//! surfaced as idiomatic Zig, plus per-OS surface creators.
//!
//! ```zig
//! const vk_stack = @import("vulkan_stack");
//! const vk = vk_stack.vk;
//! ```
//!
//! ## What is real vs. stubbed
//!
//!  * `vk` — **real from v0.1.0**: vulkan-zig's bindings, generated from
//!    `vk.xml` at build time and re-exported unchanged.
//!  * `volk`, `vma`, `shaderc`, and the surface creators — `@panic`
//!    stubs until their milestones land (see `docs/ROADMAP.md` /
//!    `docs/sprint.md`). They compile and link so consumers can wire against
//!    the surface today; calling one traps at runtime with a clear message.
//!
//! ## Boundary discipline
//!
//! Surface creators take **raw OS primitives** (pointers + integers) — no
//! windowing-library type is imported here, so this library pairs with any
//! window source (the companion platform adapter, SDL directly, or none).
//! Every `extern "C"` bridge added later (VMA, shaderc) must be `noexcept`
//! and catch before crossing the C ABI.

/// vulkan-zig's bindings, re-exported **as-is** — the full typed Vulkan API:
/// `vk.Instance`, `vk.Device`, `vk.SurfaceKHR`, error sets, and the comptime
/// dispatch wrappers (`vk.BaseWrapper`/`vk.InstanceWrapper`/`vk.DeviceWrapper`).
/// This library adds nothing on top; see vulkan-zig's own docs. *(since v0.1.0)*
pub const vk = @import("vulkan");

/// Vulkan loader / function-pointer table (volk). *(since v0.2.0)*
pub const volk = @import("volk.zig");

/// GPU memory allocator (VMA) as idiomatic Zig over a `noexcept` C bridge.
/// *(since v0.3.0)*
pub const vma = @import("vma.zig");

/// GLSL → SPIR-V compilation (shaderc). *(since v0.4.0)*
pub const shaderc = @import("shaderc.zig");

/// Opt-in **swapchain abstraction** — a two-tier helper (beginner defaults +
/// pro `buildCreateInfo`/`toRaw` bridge) over the raw `vk` swapchain API, which
/// stays first-class and links with this unreferenced. See `swapchain.zig`.
/// *(since v0.6.0)*
pub const Swapchain = @import("swapchain.zig").Swapchain;

/// Errors the `Swapchain` helper can return. *(since v0.6.0)*
pub const SwapchainError = @import("swapchain.zig").Error;

/// Opt-in **`Instance` bootstrap helper** — the first of the v0.7 `vk-bootstrap`-
/// style helpers (api version + extension/layer policy over `vkb.createInstance`).
/// Raw instance creation stays first-class; see `instance.zig`. *(since v0.7.0)*
pub const Instance = @import("instance.zig").Instance;

/// Errors the `Instance` helper can return. *(since v0.7.0)*
pub const InstanceError = @import("instance.zig").Error;

// =============================================================================
// Surface creators  (since v0.2.0)
// =============================================================================
// Each takes raw OS primitives from any windowing layer and returns a Vulkan
// surface. No windowing import; no shared type with the window source — that
// decoupling is the whole point (the platform adapter's native-handle getters
// produce exactly these primitives).

/// Errors any `create*Surface` can return. Maps the relevant `VkResult`s from
/// `vkCreate*SurfaceKHR`; a missing platform surface extension on the instance
/// surfaces as `SurfaceCreationFailed`.
pub const SurfaceError = error{
    OutOfHostMemory,
    OutOfDeviceMemory,
    SurfaceCreationFailed,
};

/// Map a `vkCreate*SurfaceKHR` result to our surface contract.
fn surfaceResult(result: vk.Result, surface: vk.SurfaceKHR) SurfaceError!vk.SurfaceKHR {
    return switch (result) {
        .success => surface,
        .error_out_of_host_memory => SurfaceError.OutOfHostMemory,
        .error_out_of_device_memory => SurfaceError.OutOfDeviceMemory,
        else => SurfaceError.SurfaceCreationFailed,
    };
}

/// Load one instance-level surface command by name (volk's loader resolves it).
fn surfacePfn(comptime Pfn: type, instance: vk.Instance, name: [*:0]const u8) SurfaceError!Pfn {
    const raw = volk.getInstanceProcAddr()(instance, name) orelse return SurfaceError.SurfaceCreationFailed;
    return @ptrCast(raw);
}

/// Create a surface for an **X11** window. `display` is the `Display*`,
/// `window` the X11 `Window` XID. *(since v0.2.0)*
pub fn createX11Surface(instance: vk.Instance, display: *anyopaque, window: u64) SurfaceError!vk.SurfaceKHR {
    const pfn = try surfacePfn(vk.PfnCreateXlibSurfaceKHR, instance, "vkCreateXlibSurfaceKHR");
    const info = vk.XlibSurfaceCreateInfoKHR{ .dpy = @ptrCast(display), .window = @intCast(window) };
    var surface: vk.SurfaceKHR = .null_handle;
    return surfaceResult(pfn(instance, &info, null, &surface), surface);
}

/// Create a surface for a **Win32** window. `hinstance` is the module
/// `HINSTANCE`, `hwnd` the window `HWND`. *(since v0.2.0)*
pub fn createWin32Surface(instance: vk.Instance, hinstance: *anyopaque, hwnd: *anyopaque) SurfaceError!vk.SurfaceKHR {
    _ = instance;
    _ = hinstance;
    _ = hwnd;
    @panic("not implemented");
}

/// Create a surface for a **Wayland** surface. `display` is the
/// `wl_display*`, `surface` the `wl_surface*`. *(since v0.5.0)*
pub fn createWaylandSurface(instance: vk.Instance, display: *anyopaque, surface: *anyopaque) SurfaceError!vk.SurfaceKHR {
    const pfn = try surfacePfn(vk.PfnCreateWaylandSurfaceKHR, instance, "vkCreateWaylandSurfaceKHR");
    const info = vk.WaylandSurfaceCreateInfoKHR{ .display = @ptrCast(display), .surface = @ptrCast(surface) };
    var out: vk.SurfaceKHR = .null_handle;
    return surfaceResult(pfn(instance, &info, null, &out), out);
}

/// Create a surface for an **Android** native window (`ANativeWindow*`).
/// *(since v0.5.0)*
pub fn createAndroidSurface(instance: vk.Instance, window: *anyopaque) SurfaceError!vk.SurfaceKHR {
    _ = instance;
    _ = window;
    @panic("not implemented");
}

test {
    // Force semantic analysis of this module's surface and the re-exports.
    @import("std").testing.refAllDecls(@This());
}
