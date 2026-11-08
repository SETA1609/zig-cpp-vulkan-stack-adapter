# API reference — zig-cpp-vulkan-stack-adapter

> The **intended public API** of the `vulkan_stack` module — signatures + semantics, **not** implementation. Use it as a guide; the bodies are yours to fill in. *“since”* tags note the [roadmap](ROADMAP.md) version each lands in.
>
> ```zig
> const vk_stack = @import("vulkan_stack");
> ```
>
> **Note on shapes:** the `vk` re-export and the surface-creator signatures are fixed. The `vma` and `shaderc` wrapper *ergonomics* below are **suggestions** — refine them to taste when you implement the bridges. Every `extern "C"` bridge stays `noexcept` — but it is an *internal* boundary; the public Zig surface here uses the **Zig calling convention** throughout (no `callconv(.c)`, no C-style out-params).
>
> **Status:** the surface lives as code in [`../src/root.zig`](../src/root.zig) with [`../src/volk.zig`](../src/volk.zig), [`../src/vma.zig`](../src/vma.zig), [`../src/shaderc.zig`](../src/shaderc.zig). **Implemented:** the `vk` re-export (generated from `vk.xml`), the `volk` loader (pure-Zig `std.DynLib`), the **X11 + Wayland + Win32** surface creators, **VMA** (C++ bridge), and **shaderc** (built from source, under `-Dshaderc`). **Still stubbed:** the **Android** surface creator. Numeric values for this library's own enums are in [`enum-values.md`](enum-values.md).
>
> **Error sets are explicit.** Each module exposes a named set — `volk.LoaderError`, `SurfaceError`, `vma.Error`, `shaderc.Error` — so the contract is documented and exhaustively `switch`-able (no inferred `!T` on the public surface).

## Module root

```zig
pub const vk      = @import("vulkan");      // vulkan-zig, re-exported as-is   (since v0.1.0)
pub const volk    = @import("volk.zig");    // loader                          (since v0.2.0)
pub const vma     = @import("vma.zig");      // GPU allocator                  (since v0.3.0)
pub const shaderc = @import("shaderc.zig"); // GLSL → SPIR-V                    (since v0.4.0)
// per-OS surface creators live at module root too                            (since v0.2.0)
pub const Swapchain      = @import("swapchain.zig").Swapchain; // opt-in helper (since v0.6.0)
pub const SwapchainError = @import("swapchain.zig").Error;     // its error set (since v0.6.0)
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

## `Swapchain` — opt-in swapchain helper  *(since v0.6.0)*

A **two-tier** convenience over the raw `vk` swapchain API. The raw path is
**never blocked** — `vkd.createSwapchainKHR` stays first-class, and this module
tree-shakes away when unreferenced. **No helper type appears in a raw signature**:
the bridge methods hand back plain `vk` objects so a consumer can drop to raw at
any boundary.

- **Beginner tier** — `create` picks a sane format / present mode / image count /
  extent from the surface's reported capabilities, makes the `VkSwapchainKHR` and
  one image view per image, and `recreate`s on resize / `error.OutOfDateKHR`.
- **Pro tier** — `buildCreateInfo` computes a good `vk.SwapchainCreateInfoKHR`
  from the same policy **without creating anything**, so a consumer drives Vulkan
  itself; `toRaw` exposes the underlying handle, images, views, and create-info.
- **Policy** — the `select*` functions are the defaults as pure functions over what
  the surface reports, so a consumer can reuse one rule and replace another.

Implemented (Issue 8). `recreate` waits for the device to go idle before it
destroys the old swapchain, and keeps the old one if building the new one fails.
A 0×0 surface (a minimized window) is `SurfaceHasZeroExtent`: wait for a resize,
then `recreate`. Tested on a real `VkSurfaceKHR` from `VK_EXT_headless_surface`
(lavapipe), so create, recreate, and acquire run in CI without a window.

```zig
pub const Error = error{ OutOfHostMemory, OutOfDeviceMemory, DeviceLost, SurfaceLost, OutOfMemory, SwapchainCreationFailed, SurfaceHasZeroExtent };

// currentExtent of a surface that lets the swapchain pick the size (Wayland, headless).
pub const extent_chosen_by_swapchain = std.math.maxInt(u32); // root: vk_stack.swapchain_extent_chosen_by_swapchain

pub const Swapchain = struct {
    handle: vk.SwapchainKHR,
    format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,
    extent: vk.Extent2D,
    images: []vk.Image,
    views: []vk.ImageView,
    options: Options,                       // what it was created with; recreate reuses them
    create_info: vk.SwapchainCreateInfoKHR, // of the current swapchain

    // Consumer preferences — every field is a *wish*, clamped against surface caps.
    pub const Options = struct {
        preferred_format: vk.SurfaceFormatKHR = .{ .format = .b8g8r8a8_srgb, .color_space = .srgb_nonlinear_khr },
        preferred_present_mode: vk.PresentModeKHR = .mailbox_khr, // falls back to .fifo_khr
        desired_image_count: u32 = 0,                             // 0 → minImageCount + 1 (clamped)
        fallback_extent: vk.Extent2D = .{ .width = 800, .height = 600 }, // used when currentExtent == 0xFFFF_FFFF
        image_usage: vk.ImageUsageFlags = .{ .color_attachment = true, .transfer_dst = true }, // ∩ supported; color attachment required
    };

    // The raw objects behind the abstraction — escape hatch for driving Vulkan directly.
    pub const Raw = struct {
        handle: vk.SwapchainKHR,
        images: []const vk.Image,
        views: []const vk.ImageView,
        create_info: vk.SwapchainCreateInfoKHR,
    };

    // Beginner tier: choose policy from surface caps, create swapchain + views. Caller owns it.
    pub fn create(gpa: std.mem.Allocator, vki: vk.InstanceWrapper, vkd: vk.DeviceWrapper, physical: vk.PhysicalDevice, device: vk.Device, surface: vk.SurfaceKHR, options: Options) Error!Swapchain;
    // Destroy the image views and the swapchain, freeing the owned slices.
    pub fn deinit(self: *Swapchain, gpa: std.mem.Allocator, vkd: vk.DeviceWrapper, device: vk.Device) void;
    // Recreate after a resize / error.OutOfDateKHR, reusing the old swapchain as oldSwapchain.
    // fallback_extent: the new size where the surface lets the swapchain choose (Wayland, headless).
    // Waits for device idle; on error the old swapchain is kept.
    pub fn recreate(self: *Swapchain, gpa: std.mem.Allocator, vki: vk.InstanceWrapper, vkd: vk.DeviceWrapper, physical: vk.PhysicalDevice, device: vk.Device, surface: vk.SurfaceKHR, fallback_extent: vk.Extent2D) Error!void;
    // Bridge: the raw handle, images, views, and the exact create-info used.
    pub fn toRaw(self: Swapchain) Raw;
    // Pro tier: compute a vk.SwapchainCreateInfoKHR from the same policy, creating nothing.
    pub fn buildCreateInfo(vki: vk.InstanceWrapper, physical: vk.PhysicalDevice, surface: vk.SurfaceKHR, options: Options) Error!vk.SwapchainCreateInfoKHR;

    // Policy, pure: preferred format else the first listed; preferred present mode else FIFO;
    // desired (0 → min + 1) clamped into [min, max] (max 0 = no limit); currentExtent, else the
    // fallback clamped to the surface's limits, 0×0 → SurfaceHasZeroExtent.
    pub fn selectSurfaceFormat(available: []const vk.SurfaceFormatKHR, preferred: vk.SurfaceFormatKHR) vk.SurfaceFormatKHR;
    pub fn selectPresentMode(available: []const vk.PresentModeKHR, preferred: vk.PresentModeKHR) vk.PresentModeKHR;
    pub fn selectImageCount(capabilities: vk.SurfaceCapabilitiesKHR, desired: u32) u32;
    pub fn selectExtent(capabilities: vk.SurfaceCapabilitiesKHR, fallback: vk.Extent2D) Error!vk.Extent2D;
};
```

### Surface formats

This library defines **no format enum of its own**. `Options.preferred_format` and
`Swapchain.format` are a `vk.SurfaceFormatKHR`, a struct of two enums that vulkan-zig
generates from `vk.xml`:

```zig
pub const SurfaceFormatKHR = extern struct {
    format: Format,             // how a pixel is stored
    color_space: ColorSpaceKHR, // how the presentation engine interprets those values
};
```

**Names.** Each value is the Vulkan name without its type prefix, in lower case:
`VK_FORMAT_B8G8R8A8_SRGB` is `.b8g8r8a8_srgb`, and
`VK_COLOR_SPACE_SRGB_NONLINEAR_KHR` is `.srgb_nonlinear_khr`.

**The full list.** Search for `VkFormat` and `VkColorSpaceKHR` in the Vulkan
specification, or for `pub const Format = enum` and `pub const ColorSpaceKHR = enum`
in the `vk.zig` your build generates. The values follow the `vulkan_headers` version
pinned in `build.zig.zon`. Numeric values are Vulkan's own, so
[`enum-values.md`](enum-values.md) does not list them.

Formats that surfaces commonly list:

| `vk.Format` | Bytes in memory | Encoding on write |
|---|---|---|
| `.b8g8r8a8_srgb` (the default) | blue, green, red, alpha; 8 bits each | Linear shader output is encoded to the standard red-green-blue (sRGB) curve by the hardware. |
| `.r8g8b8a8_srgb` | red, green, blue, alpha; 8 bits each | Same. |
| `.b8g8r8a8_unorm` | blue, green, red, alpha; 8 bits each | None. The shader writes values that are already encoded. |
| `.r8g8b8a8_unorm` | red, green, blue, alpha; 8 bits each | None. |
| `.a2b10g10r10_unorm_pack32` | one 32-bit word; 10 bits per colour, 2 bits of alpha | None. |
| `.r16g16b16a16_sfloat` | red, green, blue, alpha; 16-bit floats | None. Usually paired with `.extended_srgb_linear_ext`. |

Colour spaces:

| `vk.ColorSpaceKHR` | Meaning | Needs |
|---|---|---|
| `.srgb_nonlinear_khr` (the default) | The standard red-green-blue colour space. | `VK_KHR_surface` |
| `.extended_srgb_linear_ext` | The same primaries, linear, with values allowed outside 0 to 1. | Instance extension `VK_EXT_swapchain_colorspace` |
| `.hdr10_st2084_ext` | High dynamic range: the wide BT.2020 primaries with the SMPTE ST 2084 curve. | Instance extension `VK_EXT_swapchain_colorspace` |

Every other value numbered `1000104xxx` also comes from `VK_EXT_swapchain_colorspace`,
and this library does not enable that extension for you.

**Rules when choosing one:**

- A surface supports only the **pairs** it lists, so a format and a colour space that
  are each listed may still not be listed together. `selectSurfaceFormat` compares both
  fields.
- `preferred_format` is a wish. When the surface does not list that pair, the helper
  takes the surface's **first** listed pair without an error, and that pair may have a
  different encoding. Build pipelines from `Swapchain.format.format`, and read the
  encoding from it instead of assuming your preference was met.
- Both enums are non-exhaustive (they end in `_`), because a driver can report a value
  newer than the pinned headers. A `switch` over one needs an `else` or `_` prong.

```zig
const swapchain = try vk_stack.Swapchain.create(gpa, vki, vkd, physical, device, surface, .{
    .preferred_format = .{ .format = .r8g8b8a8_unorm, .color_space = .srgb_nonlinear_khr },
});
const color_attachment_format: vk.Format = swapchain.format.format; // what the surface gave you
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
pub fn destroyAllocator(allocator: *Allocator) void;

pub const Usage = enum { auto, gpu_only, cpu_to_gpu, gpu_to_cpu };

pub const BufferResult = struct { buffer: vk.Buffer, allocation: *Allocation };
pub fn createBuffer(allocator: *Allocator, info: *const vk.BufferCreateInfo, usage: Usage) Error!BufferResult;
pub fn destroyBuffer(allocator: *Allocator, buffer: vk.Buffer, allocation: *Allocation) void;

pub const ImageResult = struct { image: vk.Image, allocation: *Allocation };
pub fn createImage(allocator: *Allocator, info: *const vk.ImageCreateInfo, usage: Usage) Error!ImageResult;
pub fn destroyImage(allocator: *Allocator, image: vk.Image, allocation: *Allocation) void;

pub fn mapMemory(allocator: *Allocator, allocation: *Allocation) Error![*]u8;
pub fn unmapMemory(allocator: *Allocator, allocation: *Allocation) void;

// --- depth (since v0.5.0) ---------------------------------------------------

// Allocation-create flags. With `Usage.auto`, set a `host_access_*` bit to get
// mappable memory; `mapped` keeps it persistently mapped (see getAllocationInfo).
pub const Flags = packed struct(u32) {
    dedicated_memory: bool = false,
    mapped: bool = false,
    host_access_sequential_write: bool = false,
    host_access_random: bool = false,
    _reserved: u28 = 0,
};
pub fn createBufferWithFlags(allocator: *Allocator, info: *const vk.BufferCreateInfo, usage: Usage, flags: Flags) Error!BufferResult;
pub fn createImageWithFlags(allocator: *Allocator, info: *const vk.ImageCreateInfo, usage: Usage, flags: Flags) Error!ImageResult;

// Where an allocation lives; `mapped_data` non-null only under `Flags.mapped`.
pub const AllocationInfo = struct { memory_type: u32, device_memory: vk.DeviceMemory, offset: u64, size: u64, mapped_data: ?[*]u8 };
pub fn getAllocationInfo(allocator: *Allocator, allocation: *Allocation) AllocationInfo;

// Non-coherent host memory: flush CPU→GPU, invalidate GPU→CPU. `vk.WHOLE_SIZE`
// covers offset→end. No-ops on host-coherent memory.
pub fn flushAllocation(allocator: *Allocator, allocation: *Allocation, offset: u64, size: u64) Error!void;
pub fn invalidateAllocation(allocator: *Allocator, allocation: *Allocation, offset: u64, size: u64) Error!void;
```

## `shaderc` — GLSL → SPIR-V  *(since v0.4.0)*

Uses the system shaderc library (libshaderc-dev on Debian/Ubuntu, the Vulkan SDK elsewhere),
linked **only** under `-Dshaderc`. Without it, `compile` traps;
branch on `available` to choose runtime compilation vs. embedded SPIR-V. See
[`shaderc-distribution.md`](shaderc-distribution.md).

```zig
pub const available: bool;   // true when built with -Dshaderc

pub const Stage = enum {
    vertex, fragment, compute, geometry, tess_control, tess_eval,
    raygen, any_hit, closest_hit, miss, intersection, callable, // ray tracing
    task, mesh,                                                  // mesh pipeline
};

// Vulkan environment to target — drives the emitted SPIR-V version and gates
// ray-tracing / mesh features.
pub const SpirvVersion = enum { vulkan_1_0, vulkan_1_1, vulkan_1_2, vulkan_1_3 };

// A `-D` macro; `value == null` is a bare `#define NAME`.
pub const Macro = struct { name: []const u8, value: ?[]const u8 = null };

// `#include` resolution. `resolve` returns the source, or null if not found.
pub const IncludeResult = struct { name: []const u8, content: []const u8 };
pub const Includer = struct {
    context: ?*anyopaque = null,
    resolve: *const fn (context: ?*anyopaque, requested: []const u8, requesting: []const u8) ?IncludeResult,
};

pub const CompileOptions = struct {
    optimize: enum { none, size, performance } = .performance,
    debug_info: bool = false,
    entry_point: [:0]const u8 = "main",
    target: SpirvVersion = .vulkan_1_3,   // since v0.4.x
    macros: []const Macro = &.{},         // since v0.4.x
    includer: ?Includer = null,           // since v0.4.x
};

pub const Error = error{ ShaderCompilationFailed, OutOfMemory };

/// On a failed compile, `message` is set (allocator-owned — free it); pass
/// `null` to ignore. Replaces a global "last error".
pub const Diagnostics = struct { message: []u8 = &.{} };

/// SPIR-V words owned by `allocator`. On ShaderCompilationFailed, `diagnostics`
/// (if non-null) is filled with the compiler log.
pub fn compile(allocator: std.mem.Allocator, source: []const u8, stage: Stage, options: CompileOptions, diagnostics: ?*Diagnostics) Error![]u32;
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
