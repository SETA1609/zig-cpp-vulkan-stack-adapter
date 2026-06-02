# zig-cpp-vulkan-stack-adapter

A standalone **Zig library** that bundles the Vulkan stack — [vulkan-zig](https://github.com/Snektron/vulkan-zig) + [volk](https://github.com/zeux/volk) + [VMA](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) + [shaderc](https://github.com/google/shaderc) — **version-pinned together** and surfaced as idiomatic Zig. One dependency, no version drift between the pieces.

**License:** [MIT](LICENSE) · **Requires:** Zig 0.16+ · **Status:** pre-1.0, single-maintainer

> **Status detail:** real today — the **`vk` re-export** (full typed API via
> `@import("vulkan_stack").vk`), the **`volk` loader** (pure Zig via `std.DynLib`),
> the **X11 + Wayland surface creators**, **VMA** (via a `noexcept` C++ bridge),
> and **shaderc** (built from source by `tiawl/shaderc.zig`, opt-in under
> **`-Dshaderc`** — see [`docs/shaderc-distribution.md`](docs/shaderc-distribution.md)).
> Still `@panic("not implemented")`: the **Win32 / Android** surface creators —
> see [`docs/ROADMAP.md`](docs/ROADMAP.md). Public error sets (`LoaderError` /
> `SurfaceError` / `vma.Error` / `shaderc.Error`) are pinned. Calling a
> not-yet-implemented function traps at runtime with a clear message.

---

## Documentation

- [`docs/getting-started.md`](docs/getting-started.md) — **start here**: add the dep, wire the build, bootstrap instance + surface
- [`docs/vulkan-cheat-sheet.md`](docs/vulkan-cheat-sheet.md) — what Vulkan is + how it works (the stack), with deep-dive links
- [`docs/shaderc-distribution.md`](docs/shaderc-distribution.md) — how shaderc ships with zero consumer setup (`-Dshaderc`)
- [`docs/vision.md`](docs/vision.md) — what this library is for; the version-coherence guarantee
- [`docs/mission.md`](docs/mission.md) — concrete commitments (vk re-export, VMA/shaderc bridges, surface creators)
- [`docs/api.md`](docs/api.md) — intended public API surface (signatures + semantics)
- [`docs/enum-values.md`](docs/enum-values.md) — stable enum name→value maps (for serialization)
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — versioned milestones (v0.1.0 → v1.0.0)
- [`docs/sprint.md`](docs/sprint.md) — current milestone plan
- [`docs/validation-apps.md`](docs/validation-apps.md) — standalone test apps + completion checklist
- [`docs/dependencies.md`](docs/dependencies.md) — consumed libraries + Zig/C/C++ language split
- [`docs/cheat_sheet.md`](docs/cheat_sheet.md) — Zig/C/C++ cross-language field guide
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to contribute
- [`SECURITY.md`](SECURITY.md) — security policy

## What it is

A single Zig package that gives you the full Vulkan stack with idiomatic Zig types:

- **`vk`** — [vulkan-zig](https://github.com/Snektron/vulkan-zig)'s bindings, re-exported as-is. Typed enums, error sets, comptime dispatch — no C-ABI tax.
- **`vma`** — GPU memory allocator (VMA) behind a `noexcept` `extern "C"` bridge, surfaced as idiomatic Zig.
- **`volk`** — Vulkan loader, implemented in **pure Zig** (`std.DynLib` dynamically opens `libvulkan` and resolves `vkGetInstanceProcAddr`). `getInstanceProcAddr()` then feeds vulkan-zig's `vk.BaseWrapper`/`InstanceWrapper`/`DeviceWrapper`, which own the typed dispatch — so the binary doesn't hard-link `libvulkan`, and there's no vendored C loader to keep version-coherent.
- **`shaderc`** — GLSL→SPIR-V, a pure-Zig `@cImport` wrapper over shaderc's C API (no C++ bridge), built from source by `tiawl/shaderc.zig` and opt-in under `-Dshaderc`.
- **Per-OS surface creators** — `createX11Surface` / `createWaylandSurface` / `createWin32Surface` / `createAndroidSurface`, each taking raw OS primitives (no windowing-library import).

## Why bundled — version coherence

VMA's headers embed specific Vulkan-1.x signatures, vulkan-zig's bindings come from a specific `vk.xml` snapshot, and shaderc emits SPIR-V for a specific Vulkan version. Bumping any one in isolation breaks the others. One `build.zig.zon` pins all four so a version bump moves them **as a set** — that atomic coherence is the reason they live in one library.

## Quick start

```zig
// build.zig.zon
.dependencies = .{
    .vulkan_stack = .{
        .url = "git+https://github.com/SETA1609/zig-cpp-vulkan-stack-adapter.git#<tag>",
        .hash = "...",
    },
},
```

```zig
const vk_stack = @import("vulkan_stack");
const vk   = vk_stack.vk;     // re-exported vulkan-zig — full typed API
const volk = vk_stack.volk;   // pure-Zig dynamic loader

// 1. Open the Vulkan loader and bootstrap vulkan-zig's typed dispatch.
try volk.loadBase();
const vkb = vk.BaseWrapper.load(volk.getInstanceProcAddr());

// 2. Create an instance (enable whatever extensions your window source needs).
const instance = try vkb.createInstance(&create_info, null);
const vki = vk.InstanceWrapper.load(instance, volk.getInstanceProcAddr());

// 3. Turn a window's raw OS handle into a surface — no windowing import.
const surface = try vk_stack.createX11Surface(instance, x11_display, x11_window);

// (coming) the idiomatic VMA + shaderc wrappers, same shape:
//   const buf = try vk_stack.vma.createBuffer(allocator, &buf_info, .gpu_only);
//   const spv = try vk_stack.shaderc.compile(gpa, source, .vertex, .{});
```

## Surface creation — standalone, no windowing dependency

Surface creators take **raw OS primitives** (pointers + integers), not a windowing type:

```zig
pub const SurfaceError = error{ OutOfHostMemory, OutOfDeviceMemory, SurfaceCreationFailed };
pub fn createX11Surface(instance: vk.Instance, display: *anyopaque, window: u64) SurfaceError!vk.SurfaceKHR;       // ✅ real
pub fn createWaylandSurface(instance: vk.Instance, display: *anyopaque, surface: *anyopaque) SurfaceError!vk.SurfaceKHR; // ✅ real
pub fn createWin32Surface(instance: vk.Instance, hinstance: *anyopaque, hwnd: *anyopaque) SurfaceError!vk.SurfaceKHR;    // stub → v0.5.0
// ... android (stub → v0.5.0) ...
```

So this library works with **any** window source — the companion platform adapter, SDL directly, raw X11, or none at all (headless/offscreen). Pair it with a windowing layer by feeding that layer's native handle into the matching creator.

## Companion & origin

- Companion: [zig-cpp-platform-stack-adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter) — windowing + input that provides the native handles these creators consume (each library is usable alone).
- Built for and used by the [zVoxRealms](https://github.com/SETA1609/zigVoxelWorlds) engine project, but designed to **stand alone** — usable in any Zig project.

## C++ boundary discipline

VMA is the only C++↔Zig boundary: its `extern "C"` bridge functions are `noexcept` and catch all exceptions before they cross the C ABI. shaderc ships a C API and is consumed directly via `@cImport` — no bridge. See [`CONTRIBUTING.md`](CONTRIBUTING.md).
