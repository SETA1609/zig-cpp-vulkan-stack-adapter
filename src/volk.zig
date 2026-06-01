//! Vulkan loader (the "volk" role) — implemented in **pure Zig** via
//! `std.DynLib`, not the vendored C volk. It dynamically opens the platform's
//! Vulkan library at runtime (so the binary doesn't hard-link `libvulkan`) and
//! hands its `vkGetInstanceProcAddr` to vulkan-zig's dispatch wrappers
//! (`vk.BaseWrapper`/`InstanceWrapper`/`DeviceWrapper`), which own the actual
//! per-instance / per-device function loading. *(since v0.2.0)*

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

/// Errors `loadBase` can return.
pub const LoaderError = error{
    /// No Vulkan loader (`libvulkan`) could be found / opened at runtime.
    VulkanLibraryNotFound,
};

/// Per-OS candidate names for the Vulkan loader, tried in order.
const lib_names: []const []const u8 = switch (builtin.os.tag) {
    .windows => &.{"vulkan-1.dll"},
    .macos, .ios, .tvos => &.{ "libvulkan.dylib", "libvulkan.1.dylib", "libMoltenVK.dylib" },
    else => &.{ "libvulkan.so.1", "libvulkan.so" },
};

var lib: ?std.DynLib = null;
var gipa: ?vk.PfnGetInstanceProcAddr = null;

/// Bootstrap the loader: open the platform's Vulkan library and resolve
/// `vkGetInstanceProcAddr`. Idempotent. Fails if no `libvulkan` is present —
/// the binary does **not** hard-link the loader. *(since v0.2.0)*
pub fn loadBase() LoaderError!void {
    if (gipa != null) return;
    for (lib_names) |name| {
        var dl = std.DynLib.open(name) catch continue;
        if (dl.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr")) |ptr| {
            lib = dl;
            gipa = ptr;
            return;
        }
        dl.close();
    }
    return error.VulkanLibraryNotFound;
}

/// The bootstrap `vkGetInstanceProcAddr` resolved by `loadBase`. Feed it to
/// vulkan-zig's `vk.BaseWrapper.load` / `vk.InstanceWrapper.load` to build the
/// typed dispatch — the bridge between dynamic loading and vulkan-zig's
/// wrappers. Valid only after a successful `loadBase`. *(since v0.2.0)*
pub fn getInstanceProcAddr() vk.PfnGetInstanceProcAddr {
    return gipa orelse @panic("volk.loadBase() must succeed before getInstanceProcAddr()");
}

/// Instance-level loading is owned by vulkan-zig's `vk.InstanceWrapper.load`,
/// so this is a no-op in the pure-Zig loader. Kept for API symmetry (and a
/// future native backend that may want staged loading). *(since v0.2.0)*
pub fn loadInstance(instance: vk.Instance) void {
    _ = instance;
}

/// Device-level loading is owned by vulkan-zig's `vk.DeviceWrapper.load`, so
/// this is a no-op here. *(since v0.2.0)*
pub fn loadDevice(device: vk.Device) void {
    _ = device;
}
