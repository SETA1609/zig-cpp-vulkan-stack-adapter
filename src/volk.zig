//! Vulkan loader (the "volk" role) — implemented in **pure Zig**, not the
//! vendored C volk. It dynamically opens the platform's Vulkan library at
//! runtime (so the binary doesn't hard-link `libvulkan`) and hands its
//! `vkGetInstanceProcAddr` to vulkan-zig's dispatch wrappers
//! (`vk.BaseWrapper`/`InstanceWrapper`/`DeviceWrapper`), which own the actual
//! per-instance / per-device function loading.
//!
//! POSIX targets use `std.DynLib`; **Windows uses the Win32 loader directly**
//! (`LoadLibraryW`/`GetProcAddress`), because `std.DynLib` has no Windows
//! backend in Zig 0.16 (it `@compileError`s on that platform). *(since v0.2.0)*

const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

/// Errors `loadBase` can return.
pub const LoaderError = error{
    /// No Vulkan loader (`libvulkan` / `vulkan-1.dll`) could be opened at runtime.
    VulkanLibraryNotFound,
};

var gipa: ?vk.PfnGetInstanceProcAddr = null;

/// OS-split loader backend. The Windows branch is only semantically analyzed
/// when building for Windows (comptime-selected), so the kernel32 externs never
/// reach a POSIX build.
const loader = if (builtin.os.tag == .windows) struct {
    const windows = std.os.windows;

    // std.os.windows doesn't expose these in Zig 0.16 — declare them directly.
    extern "kernel32" fn LoadLibraryW(lpLibFileName: [*:0]const u16) callconv(.winapi) ?windows.HMODULE;
    extern "kernel32" fn GetProcAddress(hModule: windows.HMODULE, lpProcName: [*:0]const u8) callconv(.winapi) ?windows.FARPROC;

    var module: ?windows.HMODULE = null;

    fn open() ?vk.PfnGetInstanceProcAddr {
        const handle = LoadLibraryW(std.unicode.utf8ToUtf16LeStringLiteral("vulkan-1.dll")) orelse return null;
        const proc = GetProcAddress(handle, "vkGetInstanceProcAddr") orelse return null;
        module = handle; // keep the DLL loaded for the process lifetime
        const fn_ptr: vk.PfnGetInstanceProcAddr = @ptrCast(proc);
        return fn_ptr;
    }
} else struct {
    /// Per-OS candidate names for the Vulkan loader, tried in order.
    const names: []const []const u8 = switch (builtin.os.tag) {
        .macos, .ios, .tvos => &.{ "libvulkan.dylib", "libvulkan.1.dylib", "libMoltenVK.dylib" },
        else => &.{ "libvulkan.so.1", "libvulkan.so" },
    };

    var lib: ?std.DynLib = null;

    fn open() ?vk.PfnGetInstanceProcAddr {
        for (names) |name| {
            var dl = std.DynLib.open(name) catch continue;
            if (dl.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr")) |ptr| {
                lib = dl; // keep it open for the process lifetime
                return ptr;
            }
            dl.close();
        }
        return null;
    }
};

/// Bootstrap the loader: open the platform's Vulkan library and resolve
/// `vkGetInstanceProcAddr`. Idempotent. Fails if no loader is present — the
/// binary does **not** hard-link it. *(since v0.2.0)*
pub fn loadBase() LoaderError!void {
    if (gipa != null) return;
    gipa = loader.open() orelse return error.VulkanLibraryNotFound;
}

/// The bootstrap `vkGetInstanceProcAddr` resolved by `loadBase`. Feed it to
/// vulkan-zig's `vk.BaseWrapper.load` / `vk.InstanceWrapper.load` to build the
/// typed dispatch. Valid only after a successful `loadBase`. *(since v0.2.0)*
pub fn getInstanceProcAddr() vk.PfnGetInstanceProcAddr {
    return gipa orelse @panic("volk.loadBase() must succeed before getInstanceProcAddr()");
}

/// Instance-level loading is owned by vulkan-zig's `vk.InstanceWrapper.load`,
/// so this is a no-op in the pure-Zig loader. Kept for API symmetry. *(since v0.2.0)*
pub fn loadInstance(instance: vk.Instance) void {
    _ = instance;
}

/// Device-level loading is owned by vulkan-zig's `vk.DeviceWrapper.load`, so
/// this is a no-op here. *(since v0.2.0)*
pub fn loadDevice(device: vk.Device) void {
    _ = device;
}
