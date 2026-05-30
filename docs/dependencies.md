# Dependencies & language mix — zig-cpp-vulkan-stack-adapter

> What this library bundles, and the language split of the code **written here** (the glue) vs. **vendored** (the upstreams). These are very different numbers — see the note at the bottom.

## Consumed libraries

| Library | Upstream language | License | Role | How it surfaces |
| --- | --- | --- | --- | --- |
| [vulkan-zig](https://github.com/Snektron/vulkan-zig) | **Zig** | MIT | Vulkan bindings from `vk.xml` | Re-exported as `vk` — no wrapping, no C-ABI tax |
| [volk](https://github.com/zeux/volk) | **C** | MIT | Loader / function-pointer table | Vendored, compiled as-is; thin Zig wrapper |
| [VMA](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) | **C++** (header-only) | MIT | GPU memory allocator | `extern "C"` bridge → idiomatic Zig |
| [shaderc](https://github.com/google/shaderc) (wraps [glslang](https://github.com/KhronosGroup/glslang)) | **C++**, ships a **C** API | Apache-2.0 / BSD-3 | GLSL → SPIR-V | `@cImport` its C header, or a thin C++ bridge → Zig |

No GPL/LGPL dependencies.

## Hand-written code — language split (estimate)

| Language | Estimate | What |
| --- | --- | --- |
| **Zig** | **~75–82%** | `root.zig`, `vma.zig`, `volk.zig`, `shaderc.zig`, `surface.zig`, `build.zig` |
| **C++** | **~18–25%** | `vma_bridge.{h,cpp}` — VMA's `VMA_IMPLEMENTATION` translation unit + `extern "C"` wrappers; optionally a shaderc bridge |
| **C** | **~0%** | volk is vendored, not written; nothing hand-authored |

### Where the C++ actually comes from — and how to cut it

- **VMA genuinely forces C++.** It's header-only C++ with no C entry point, so `@cImport` can't process it; you must compile a C++ translation unit (`VMA_IMPLEMENTATION`) and expose a C-clean header. This is the irreducible C++ in the repo.
- **shaderc does *not* force C++.** It ships a C API (`shaderc/shaderc.h`), so you can `@cImport` it directly, link the compiled `libshaderc`, and write the wrapper in **Zig** — **no shaderc C++ bridge needed.** Doing that pushes the split toward **Zig ~82% / C++ ~18%** (just the VMA bridge). Here the `-cpp-` in the repo name is earned.

Every `extern "C"` bridge function is `noexcept` and catches before crossing the C ABI (see [`CONTRIBUTING.md`](../CONTRIBUTING.md)).

## "Written" vs. "compiled"

The split above is **code authored in this repo** (a few hundred lines). If you measured the **compiled artifact** instead, it would read as overwhelmingly C++ — glslang/shaderc alone is a large C++ codebase, plus VMA and volk. So:

- **Authored here:** mostly Zig, with a slice of C++ for VMA.
- **In the shipped binary:** mostly upstream C/C++ (shaderc/glslang dominate), with a thin Zig surface on top.

Estimates only — real numbers land as the [milestone plan](sprint.md) is implemented (the repo is still a stub today).
