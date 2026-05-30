# zig-cpp-vulkan-stack-adapter

A standalone **Zig library** that bundles the Vulkan stack — [vulkan-zig](https://github.com/Snektron/vulkan-zig) + [volk](https://github.com/zeux/volk) + [VMA](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) + [shaderc](https://github.com/google/shaderc) — **version-pinned together** and surfaced as idiomatic Zig. One dependency, no version drift between the pieces.

**License:** [MIT](LICENSE) · **Requires:** Zig 0.16+ · **Status:** pre-1.0, single-maintainer

> **Status detail:** `build.zig` exposes the `vulkan_stack` module + static-lib
> artifact and wires vulkan-zig's `vk.xml` codegen, so the **`vk` re-export is
> real** (`@import("vulkan_stack").vk` gives the full typed API today). `volk`,
> `vma`, `shaderc`, and the surface creators are authored, documented
> `@panic("not implemented")` stubs in `src/` awaiting their milestones (see
> [`docs/ROADMAP.md`](docs/ROADMAP.md)). `zig build` produces the lib;
> `zig build test` type-checks the surface and resolves the generated `vk`.

---

## Documentation

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
- **`volk`** — Vulkan loader / function-pointer table.
- **`shaderc`** — GLSL→SPIR-V, behind a `noexcept` `extern "C"` bridge.
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
const vk      = vk_stack.vk;        // re-exported vulkan-zig — full typed API
const vma     = vk_stack.vma;       // typed Zig wrapper over VMA
const shaderc = vk_stack.shaderc;   // GLSL→SPIR-V

const buf = try vma.createBuffer(allocator, &buf_info, .gpu_only);
const spv = try shaderc.compile(gpa, source, .vertex, .{});
```

## Surface creation — standalone, no windowing dependency

Surface creators take **raw OS primitives** (pointers + integers), not a windowing type:

```zig
pub fn createX11Surface(instance: vk.Instance, display: *anyopaque, window: u64) !vk.SurfaceKHR;
pub fn createWin32Surface(instance: vk.Instance, hinstance: *anyopaque, hwnd: *anyopaque) !vk.SurfaceKHR;
// ... wayland, android ...
```

So this library works with **any** window source — the companion platform adapter, SDL directly, raw X11, or none at all (headless/offscreen). Pair it with a windowing layer by feeding that layer's native handle into the matching creator.

## Companion & origin

- Companion: [zig-cpp-platform-stack-adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter) — windowing + input that provides the native handles these creators consume (each library is usable alone).
- Built for and used by the [zVoxRealms](https://github.com/SETA1609/zigVoxelWorlds) engine project, but designed to **stand alone** — usable in any Zig project.

## C++ boundary discipline

Every `extern "C"` bridge function (VMA, shaderc) is `noexcept` and catches all exceptions before they cross the C ABI. See [`CONTRIBUTING.md`](CONTRIBUTING.md).
