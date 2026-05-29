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

/// Bootstrap the loader with the platform's `vkGetInstanceProcAddr`. Call
/// once before creating an instance. *(since v0.2.0)*
pub fn loadBase(get_instance_proc_addr: vk.PfnGetInstanceProcAddr) void {
    _ = get_instance_proc_addr;
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
