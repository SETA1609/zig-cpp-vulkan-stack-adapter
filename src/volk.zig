//! Vulkan loader wrapper (volk).
//!
//! Loads Vulkan entry points into function-pointer tables in three stages —
//! base (no instance), instance-level, then device-level — mirroring how
//! Vulkan itself layers symbol resolution. Idiomatic Zig surface; the actual
//! loading is done against volk's C loader once it is vendored. *(since v0.2.0)*
//!
//! > If vulkan-zig's own comptime dispatch wrappers (`vk.BaseWrapper` etc.)
//! > cover your needs, volk may be dropped — see `docs/ROADMAP.md`.

const vk = @import("vulkan");

/// Errors `loadBase` can return.
pub const LoaderError = error{
    /// No Vulkan loader (`libvulkan`) could be found / opened at runtime.
    VulkanLibraryNotFound,
};

/// Bootstrap the loader: dynamically open the platform's Vulkan library
/// (`volkInitialize`) and load the base (no-instance) entry points. Call once
/// before creating an instance. Fails if no `libvulkan` is present — the binary
/// does **not** hard-link the loader. *(since v0.2.0)*
pub fn loadBase() LoaderError!void {
    @panic("not implemented");
}

/// The bootstrap `vkGetInstanceProcAddr` resolved by `loadBase`. Feed it to
/// vulkan-zig's `vk.BaseWrapper.load` / `vk.InstanceWrapper.load` to build the
/// typed dispatch — this is the bridge between volk's dynamic loading and
/// vulkan-zig's wrappers. Valid only after a successful `loadBase`. *(since v0.2.0)*
pub fn getInstanceProcAddr() vk.PfnGetInstanceProcAddr {
    @panic("not implemented");
}

/// Load instance-level function pointers for `instance`. Call after
/// `vkCreateInstance`. *(since v0.2.0)*
pub fn loadInstance(instance: vk.Instance) void {
    _ = instance;
    @panic("not implemented");
}

/// Load device-level function pointers for `device` (skips the instance
/// dispatch indirection). Call after `vkCreateDevice`. *(since v0.2.0)*
pub fn loadDevice(device: vk.Device) void {
    _ = device;
    @panic("not implemented");
}

test {
    @import("std").testing.refAllDecls(@This());
}
