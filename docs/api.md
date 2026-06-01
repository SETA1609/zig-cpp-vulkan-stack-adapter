# API reference — zig-cpp-vulkan-stack-adapter

> The **intended public API** of the `vulkan_stack` module — signatures + semantics, **not** implementation. Use it as a guide; the bodies are yours to fill in. *“since”* tags note the [roadmap](ROADMAP.md) version each lands in.
>
> ```zig
> const vk_stack = @import("vulkan_stack");
> ```
>
> **Note on shapes:** the `vk` re-export and the surface-creator signatures are fixed. The `vma` and `shaderc` wrapper *ergonomics* below are **suggestions** — refine them to taste when you implement the bridges. Every `extern "C"` bridge stays `noexcept` — but it is an *internal* boundary; the public Zig surface here uses the **Zig calling convention** throughout (no `callconv(.c)`, no C-style out-params).
>
> **Status:** the surface lives as code in [`../src/root.zig`](../src/root.zig) with [`../src/volk.zig`](../src/volk.zig), [`../src/vma.zig`](../src/vma.zig), [`../src/shaderc.zig`](../src/shaderc.zig). **Implemented:** the `vk` re-export (generated from `vk.xml`), the `volk` loader (pure-Zig `std.DynLib`), the **X11 + Wayland** surface creators, **VMA** (C++ bridge), and **shaderc** (built from source, under `-Dshaderc`). **Still stubbed:** the **Win32 / Android** surface creators. Numeric values for this library's own enums are in [`enum-values.md`](enum-values.md).
>
> **Error sets are explicit.** Each module exposes a named set — `volk.LoaderError`, `SurfaceError`, `vma.Error`, `shaderc.Error` — so the contract is documented and exhaustively `switch`-able (no inferred `!T` on the public surface).

## Module root

```zig
pub const vk      = @import("vulkan");      // vulkan-zig, re-exported as-is   (since v0.1.0)
pub const volk    = @import("volk.zig");    // loader                          (since v0.2.0)
pub const vma     = @import("vma.zig");      // GPU allocator                  (since v0.3.0)
pub const shaderc = @import("shaderc.zig"); // GLSL → SPIR-V                    (since v0.4.0)
// per-OS surface creators live at module root too                            (since v0.2.0)
```

## `vk` — Vulkan bindings  *(since v0.1.0)*

Re-exported from [vulkan-zig](https://github.com/Snektron/vulkan-zig) **unchanged** — the full typed API: `vk.Instance`, `vk.Device`, `vk.SurfaceKHR`, error sets, and the comptime dispatch wrappers (`vk.BaseWrapper`, `vk.InstanceWrapper`, `vk.DeviceWrapper`). This library adds nothing on top of it — see vulkan-zig's own docs.

## Loader  *(since v0.2.0)*

```zig
pub const LoaderError = error{ VulkanLibraryNotFound };
pub fn loadBase() LoaderError!void;                       // dlopen libvulkan + base fns
pub fn getInstanceProcAddr() vk.PfnGetInstanceProcAddr;   // bridge to vk.BaseWrapper.load
pub fn loadInstance(instance: vk.Instance) void;          // instance-level fns
pub fn loadDevice(device: vk.Device) void;                // device-level fns
```

> If vulkan-zig's own dispatch wrappers cover your needs, volk may be dropped — see the [ROADMAP](ROADMAP.md) note.

## Surface creators  *(since v0.2.0)*

Each takes **raw OS primitives** (from any windowing layer) and returns a surface — no windowing import.

```zig
pub const SurfaceError = error{ OutOfHostMemory, OutOfDeviceMemory, SurfaceCreationFailed };
pub fn createX11Surface(instance: vk.Instance, display: *anyopaque, window: u64) SurfaceError!vk.SurfaceKHR;
pub fn createWin32Surface(instance: vk.Instance, hinstance: *anyopaque, hwnd: *anyopaque) SurfaceError!vk.SurfaceKHR;
pub fn createWaylandSurface(instance: vk.Instance, display: *anyopaque, surface: *anyopaque) SurfaceError!vk.SurfaceKHR;  // since v0.5.0
pub fn createAndroidSurface(instance: vk.Instance, window: *anyopaque) SurfaceError!vk.SurfaceKHR;                         // since v0.5.0
```

## `vma` — GPU memory allocator  *(since v0.3.0)*

Idiomatic Zig over VMA's C++ (through a `noexcept` C bridge). *Shapes are suggestions.*

```zig
pub const Allocator = opaque {};
pub const Allocation = opaque {};
pub const Error = error{ OutOfHostMemory, OutOfDeviceMemory, MappingFailed, InitializationFailed, Unknown };

pub const AllocatorCreateInfo = struct {
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    instance: vk.Instance,
    api_version: u32 = vk.API_VERSION_1_3,
};
pub fn createAllocator(info: AllocatorCreateInfo) Error!*Allocator;
pub fn destroyAllocator(a: *Allocator) void;

pub const Usage = enum { auto, gpu_only, cpu_to_gpu, gpu_to_cpu };

pub const BufferResult = struct { buffer: vk.Buffer, allocation: *Allocation };
pub fn createBuffer(a: *Allocator, info: *const vk.BufferCreateInfo, usage: Usage) Error!BufferResult;
pub fn destroyBuffer(a: *Allocator, buffer: vk.Buffer, allocation: *Allocation) void;

pub const ImageResult = struct { image: vk.Image, allocation: *Allocation };
pub fn createImage(a: *Allocator, info: *const vk.ImageCreateInfo, usage: Usage) Error!ImageResult;
pub fn destroyImage(a: *Allocator, image: vk.Image, allocation: *Allocation) void;

pub fn mapMemory(a: *Allocator, allocation: *Allocation) Error![*]u8;
pub fn unmapMemory(a: *Allocator, allocation: *Allocation) void;
```

## `shaderc` — GLSL → SPIR-V  *(since v0.4.0)*

Built from source by `tiawl/shaderc.zig` and linked **only** under `-Dshaderc`
(a lazy dependency — no system SDK, cross-compiles). Without it, `compile` traps;
branch on `available` to choose runtime compilation vs. embedded SPIR-V. See
[`shaderc-distribution.md`](shaderc-distribution.md).

```zig
pub const available: bool;   // true when built with -Dshaderc

pub const Stage = enum { vertex, fragment, compute, geometry, tess_control, tess_eval };

pub const CompileOptions = struct {
    optimize: enum { none, size, performance } = .performance,
    debug_info: bool = false,
    entry_point: [:0]const u8 = "main",
};

pub const Error = error{ ShaderCompilationFailed, OutOfMemory };

/// On a failed compile, `message` is set (allocator-owned — free it); pass
/// `null` to ignore. Replaces a global "last error".
pub const Diagnostics = struct { message: []u8 = &.{} };

/// SPIR-V words owned by `allocator`. On ShaderCompilationFailed, `diagnostics`
/// (if non-null) is filled with the compiler log.
pub fn compile(allocator: std.mem.Allocator, source: []const u8, stage: Stage, opts: CompileOptions, diagnostics: ?*Diagnostics) Error![]u32;
```

> Consumers that don't need runtime compilation skip `-Dshaderc` entirely and
> embed precompiled SPIR-V (`@embedFile`) — see [`shaderc-distribution.md`](shaderc-distribution.md).

## Minimal usage

```zig
const vk_stack = @import("vulkan_stack");
const vk = vk_stack.vk;

// after you've created the instance + device:
const allocator = try vk_stack.vma.createAllocator(.{
    .physical_device = pdev, .device = dev, .instance = inst,
});
defer vk_stack.vma.destroyAllocator(allocator);

const buf = try vk_stack.vma.createBuffer(allocator, &buf_info, .gpu_only);
defer vk_stack.vma.destroyBuffer(allocator, buf.buffer, buf.allocation);

// runtime GLSL→SPIR-V (only when built with -Dshaderc; else embed a .spv):
const spv = try vk_stack.shaderc.compile(gpa, vert_src, .vertex, .{}, null);
defer gpa.free(spv);

// surface from a windowing layer's raw handle:
const surface = try vk_stack.createX11Surface(inst, x11_display, x11_window);
```

---

The `vk` re-export is real from v0.1.0; the rest are slots to fill as you implement each milestone. The VMA/shaderc wrapper shapes are guides — refine the ergonomics to taste, keeping every `extern "C"` bridge `noexcept` and catching before it crosses the C ABI.
