# API reference — zig-cpp-vulkan-stack-adapter

> The **intended public API** of the `vulkan_stack` module — signatures + semantics, **not** implementation. Use it as a guide; the bodies are yours to fill in. *“since”* tags note the [roadmap](ROADMAP.md) version each lands in.
>
> ```zig
> const vk_stack = @import("vulkan_stack");
> ```
>
> **Note on shapes:** the `vk` re-export and the surface-creator signatures are fixed. The `vma` and `shaderc` wrapper *ergonomics* below are **suggestions** — refine them to taste when you implement the bridges. Every `extern "C"` bridge stays `noexcept` — but it is an *internal* boundary; the public Zig surface here uses the **Zig calling convention** throughout (no `callconv(.c)`, no C-style out-params).
>
> **Now authored:** this surface lives as code in [`../src/root.zig`](../src/root.zig) (`vk` re-export + surface creators) with [`../src/volk.zig`](../src/volk.zig), [`../src/vma.zig`](../src/vma.zig), [`../src/shaderc.zig`](../src/shaderc.zig). The `vk` re-export is **real** (generated from `vk.xml`); the rest are `@panic("not implemented")` stubs. Numeric values for this library's own enums are in [`enum-values.md`](enum-values.md).
>
> **Note for the future — error sets.** `shaderc.compile` already exposes an explicit named error set (`shaderc.Error`); the surface creators and `vma.*` use *inferred* sets (`!T`) for now. The library-grade goal is explicit named sets per area (e.g. `SurfaceError!vk.SurfaceKHR`, `VmaError!*Allocator`) so the error contract is documented and exhaustively `switch`-able. **Counter-argument (why not yet):** the bridges aren't written, so the real failure taxonomy isn't known and a premature set would churn — keep inferred while the VMA/surface code is built, then **lock explicit named sets at v1.0**. Revisit at the 1.0 stabilization pass.

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
pub fn loadBase(get_instance_proc_addr: vk.PfnGetInstanceProcAddr) void;  // bootstrap
pub fn loadInstance(instance: vk.Instance) void;                          // instance-level fns
pub fn loadDevice(device: vk.Device) void;                                // device-level fns
```

> If vulkan-zig's own dispatch wrappers cover your needs, volk may be dropped — see the [ROADMAP](ROADMAP.md) note.

## Surface creators  *(since v0.2.0)*

Each takes **raw OS primitives** (from any windowing layer) and returns a surface — no windowing import.

```zig
pub fn createX11Surface(instance: vk.Instance, display: *anyopaque, window: u64) !vk.SurfaceKHR;
pub fn createWin32Surface(instance: vk.Instance, hinstance: *anyopaque, hwnd: *anyopaque) !vk.SurfaceKHR;
pub fn createWaylandSurface(instance: vk.Instance, display: *anyopaque, surface: *anyopaque) !vk.SurfaceKHR;  // since v0.5.0
pub fn createAndroidSurface(instance: vk.Instance, window: *anyopaque) !vk.SurfaceKHR;                         // since v0.5.0
```

## `vma` — GPU memory allocator  *(since v0.3.0)*

Idiomatic Zig over VMA's C++ (through a `noexcept` C bridge). *Shapes are suggestions.*

```zig
pub const Allocator = opaque {};
pub const Allocation = opaque {};

pub const AllocatorCreateInfo = struct {
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    instance: vk.Instance,
    api_version: u32 = vk.API_VERSION_1_3,
};
pub fn createAllocator(info: AllocatorCreateInfo) !*Allocator;
pub fn destroyAllocator(a: *Allocator) void;

pub const Usage = enum { auto, gpu_only, cpu_to_gpu, gpu_to_cpu };

pub const BufferResult = struct { buffer: vk.Buffer, allocation: *Allocation };
pub fn createBuffer(a: *Allocator, info: *const vk.BufferCreateInfo, usage: Usage) !BufferResult;
pub fn destroyBuffer(a: *Allocator, buffer: vk.Buffer, allocation: *Allocation) void;

pub const ImageResult = struct { image: vk.Image, allocation: *Allocation };
pub fn createImage(a: *Allocator, info: *const vk.ImageCreateInfo, usage: Usage) !ImageResult;
pub fn destroyImage(a: *Allocator, image: vk.Image, allocation: *Allocation) void;

pub fn mapMemory(a: *Allocator, allocation: *Allocation) ![*]u8;
pub fn unmapMemory(a: *Allocator, allocation: *Allocation) void;
```

## `shaderc` — GLSL → SPIR-V  *(since v0.4.0)*

```zig
pub const Stage = enum { vertex, fragment, compute, geometry, tess_control, tess_eval };

pub const CompileOptions = struct {
    optimize: enum { none, size, performance } = .performance,
    debug_info: bool = false,
    entry_point: [:0]const u8 = "main",
};

/// Returns SPIR-V words; caller frees with the same allocator.
pub fn compile(allocator: std.mem.Allocator, source: []const u8, stage: Stage, opts: CompileOptions) Error![]u32;

pub const Error = error{ ShaderCompilationFailed, OutOfMemory };
pub fn lastErrorMessage() []const u8;   // diagnostics for the most recent failure
```

> Consumers that don't need runtime compilation can skip this entirely and embed precompiled SPIR-V — see the [ROADMAP](ROADMAP.md).

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

const spv = try vk_stack.shaderc.compile(gpa, vert_src, .vertex, .{});
defer gpa.free(spv);

// surface from a windowing layer's raw handle:
const surface = try vk_stack.createX11Surface(inst, x11_display, x11_window);
```

---

The `vk` re-export is real from v0.1.0; the rest are slots to fill as you implement each milestone. The VMA/shaderc wrapper shapes are guides — refine the ergonomics to taste, keeping every `extern "C"` bridge `noexcept` and catching before it crosses the C ABI.
