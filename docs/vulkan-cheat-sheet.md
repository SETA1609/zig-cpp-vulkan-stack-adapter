# Vulkan cheat sheet

> What Vulkan is, how it works, and how **this stack maps onto it** — a quick
> reference for working on the bridges (`src/{volk,vma,shaderc}.zig`, surface
> creators). For the Zig↔C/C++ mechanics see [`cheat_sheet.md`](cheat_sheet.md).
>
> Deep dives link to the **[Khronos Vulkan docs](https://docs.vulkan.org/)** and
> the upstreams.

## What Vulkan is

[Vulkan](https://www.vulkan.org/) is a low-level, **explicit** cross-platform
GPU API from Khronos. "Explicit" means *you* manage almost everything OpenGL
hid: memory allocation, synchronization, command recording, and which functions
even exist (loaded by extension/version). That's more code, but it's
predictable and multi-threadable — the right base for an engine.

This library bundles the Vulkan **stack** as one version-coherent Zig package:

| Piece | Role | Surfaced as |
| --- | --- | --- |
| [vulkan-zig](https://github.com/Snektron/vulkan-zig) | Typed Zig bindings generated from `vk.xml` | `vk_stack.vk` (re-export) |
| [volk](https://github.com/zeux/volk) (we do it in pure Zig) | Dynamic loader / dispatch bootstrap | `vk_stack.volk` |
| [VMA](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) | GPU memory allocator | `vk_stack.vma` |
| [shaderc](https://github.com/google/shaderc) | GLSL → SPIR-V compiler | `vk_stack.shaderc` |

Why bundled together: VMA's headers, vulkan-zig's `vk.xml`, and shaderc's
SPIR-V target must move as a **set** or you get cryptic mismatches — see
[`docs/vision.md`](vision.md).

## The big picture — how a Vulkan frame is shaped

```
load loader (vkGetInstanceProcAddr)         // volk / dynamic load
  └─ Instance  (+ extensions: VK_KHR_surface + platform)
       └─ pick PhysicalDevice (GPU) + a queue family
            └─ Device  (+ swapchain extension) + Queues
                 ├─ Surface (from a window) → Swapchain (images to present)
                 ├─ allocate memory (VMA) → Buffers / Images
                 ├─ compile GLSL → SPIR-V (shaderc) → ShaderModule → Pipeline
                 └─ per frame: record CommandBuffer → submit → present
                      synchronized with Fences + Semaphores
```

Two ideas underpin everything:

1. **Function dispatch is loaded, not linked.** You start with one bootstrap
   pointer (`vkGetInstanceProcAddr`), load *instance-level* functions from it,
   then *device-level* functions from the device. Device-level dispatch skips an
   indirection (faster on hot paths). vulkan-zig models this as
   `BaseWrapper` → `InstanceWrapper` → `DeviceWrapper`; volk's job is just to
   provide the bootstrap pointer.
2. **Objects form a strict hierarchy.** Instance → PhysicalDevice → Device →
   (everything else). Children must be destroyed before parents.

## Core concepts (and where they live here)

| Concept | What it is | In this lib |
| --- | --- | --- |
| **Loader / dispatch** | Resolving `vkXxx` function pointers | `volk.loadBase` + `getInstanceProcAddr` → vulkan-zig `*Wrapper.load` |
| **Instance** | The Vulkan context; enables instance extensions/layers | `vk.BaseWrapper.createInstance` (consumer code) |
| **Physical device** | A GPU; query its queue families, memory heaps, limits | `vk.InstanceWrapper.enumeratePhysicalDevices` |
| **Device + queues** | Logical device you actually use; queues submit work | `vk.InstanceWrapper.createDevice` |
| **Surface (WSI)** | A handle to a window's drawable area | `vk_stack.createX11Surface` / `createWaylandSurface` |
| **Swapchain** | The ring of images you present to the surface | consumer (vulkan-zig `vk`) |
| **Memory / resources** | Heaps & types; buffers/images bound to allocations | `vk_stack.vma` |
| **Shaders** | SPIR-V modules; GLSL is compiled to SPIR-V | `vk_stack.shaderc` |
| **Commands** | Recorded into command buffers, submitted to a queue | consumer (`vk`) |
| **Sync** | Fences (GPU→CPU), semaphores (GPU→GPU), barriers | consumer (`vk`) |
| **Validation layers** | Catch misuse at dev time (`VK_LAYER_KHRONOS_validation`) | enable on the instance |

## How this stack maps

| Our API | What it does |
| --- | --- |
| `vk_stack.vk` | vulkan-zig, re-exported unchanged — the full typed API + `BaseWrapper`/`InstanceWrapper`/`DeviceWrapper`. |
| `volk.loadBase()` | `std.DynLib` opens `libvulkan` and resolves `vkGetInstanceProcAddr` (pure Zig — no vendored C). |
| `volk.getInstanceProcAddr()` | Hands that bootstrap pointer to `vk.BaseWrapper.load` / `InstanceWrapper.load` — the bridge between dynamic loading and vulkan-zig's dispatch. |
| `createX11Surface` / `createWaylandSurface` | Loads the one `vkCreate*SurfaceKHR` via the proc-addr and builds the vulkan-zig create-info from **raw OS primitives** (no windowing import). |
| `vma.*` | Idiomatic Zig over VMA's C++ via a `noexcept` `extern "C"` bridge *(real, v0.3.0; depth in v0.5.0)*. |
| `shaderc.compile` | GLSL source → SPIR-V words — pure-Zig `@cImport`, opt-in under `-Dshaderc` *(real, v0.4.0)*. |

## Gotchas

- **Load order matters.** base → instance → device. A device-level call through
  the instance dispatch works but is slower; build a `DeviceWrapper` for hot paths.
- **Surface extensions must be enabled on the instance.** `createX11Surface`
  needs `VK_KHR_surface` + `VK_KHR_xlib_surface` enabled at `createInstance` —
  which is exactly what the platform adapter's `requiredVulkanInstanceExtensions()`
  returns. Mismatch (e.g. enabling xcb but creating an xlib surface) fails.
- **Handles are 64-bit even on 32-bit builds.** vulkan-zig models them as
  `enum(u64)`; `.null_handle` is the zero handle.
- **`VkResult` is a return value, not an exception.** Check it (`.success`) and
  map to errors — vulkan-zig's wrappers do this for you (typed error sets).
- **Validation layers are your friend.** Develop with `VK_LAYER_KHRONOS_validation`
  on; a "silent" validation log is the real pass criterion for the GPU bridges
  (see [`docs/manual-testing.md`](manual-testing.md)).
- **Version coherence.** Don't bump vulkan-zig / VMA / shaderc independently — see
  the [ROADMAP](ROADMAP.md) note.

## Deep-dive links

- [Vulkan Specification](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html) — the authority (dense)
- [Vulkan Tutorial](https://docs.vulkan.org/tutorial/latest/index.html) — step-by-step first triangle
- [Vulkan Guide](https://docs.vulkan.org/guide/latest/index.html) — concepts explained · [vkguide.dev](https://vkguide.dev/) — a modern engine-oriented walkthrough
- [Khronos Vulkan docs hub](https://docs.vulkan.org/) · [registry](https://registry.khronos.org/vulkan/)
- Upstreams: [vulkan-zig](https://github.com/Snektron/vulkan-zig) · [volk](https://github.com/zeux/volk) · [VMA docs](https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/) · [shaderc](https://github.com/google/shaderc)
- Companion: [`docs/api.md`](api.md) (our surface) · [`docs/dependencies.md`](dependencies.md) (the bundle)
