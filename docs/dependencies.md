# Dependencies & language mix — zig-cpp-vulkan-stack-adapter

> What this library bundles, and the language split of the code **written here** (the glue) vs. **vendored** (the upstreams). These are very different numbers — see the note at the bottom.

## Consumed libraries

| Library | Upstream language | License | Role | How it surfaces |
| --- | --- | --- | --- | --- |
| [vulkan-zig](https://github.com/Snektron/vulkan-zig) | **Zig** | MIT | Vulkan bindings from `vk.xml` | Re-exported as `vk` — no wrapping, no C-ABI tax |
| [volk](https://github.com/zeux/volk) | **C** | MIT | Loader / function-pointer table | The *role* only — reimplemented in **pure Zig** (`std.DynLib`); no vendored C volk is compiled |
| [VMA](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) | **C++** (header-only) | MIT | GPU memory allocator | `extern "C"` bridge → idiomatic Zig |
| [shaderc](https://github.com/google/shaderc) (wraps [glslang](https://github.com/KhronosGroup/glslang)) | **C++**, ships a **C** API | Apache-2.0 / BSD-3 | GLSL → SPIR-V | built from source by [`tiawl/shaderc.zig`](https://github.com/tiawl/shaderc.zig) (lazy, `-Dshaderc`); pure-Zig `@cImport` wrapper, **no bridge** — see [`shaderc-distribution.md`](shaderc-distribution.md) |

No GPL/LGPL dependencies.

## Hand-written code — language split (estimate)

| Language | Estimate | What |
| --- | --- | --- |
| **Zig** | **~80–85%** | `root.zig` (surface creators), `vma.zig`, `volk.zig`, `shaderc.zig`, `build.zig` |
| **C++** | **~15–20%** | `src/c/vma_bridge.{h,cpp}` — VMA's `VMA_IMPLEMENTATION` translation unit + `extern "C"` wrappers (the **only** C++ here) |
| **C** | **~0%** | nothing hand-authored; the volk role is pure Zig, not vendored C |

### Where the C++ actually comes from — and how to cut it

- **VMA genuinely forces C++.** It's header-only C++ with no C entry point, so `@cImport` can't process it; you must compile a C++ translation unit (`VMA_IMPLEMENTATION`) and expose a C-clean header. This is the irreducible C++ in the repo.
- **shaderc does *not* force C++.** It ships a C API (`shaderc/shaderc.h`), so we translate it with `b.addTranslateC` (Zig 0.17 removed `@cImport`), link the system `libshaderc`, and write the wrapper in **Zig** — **no shaderc C++ bridge.** That keeps the hand-written split at roughly **Zig ~82% / C++ ~18%** (the VMA bridge is the only C++). The `-cpp-` in the repo name is earned by that single bridge plus the upstream C/C++ in the shipped binary.

Every `extern "C"` bridge function (the VMA bridge — the only one) is `noexcept` and catches before crossing the C ABI (see [`CONTRIBUTING.md`](../CONTRIBUTING.md)).

## "Written" vs. "compiled"

The split above is **code authored in this repo** (a few hundred lines). If you measured the **compiled artifact** instead, it would read as overwhelmingly C++ — glslang/shaderc alone is a large C++ codebase, plus VMA and volk. So:

- **Authored here:** mostly Zig, with a slice of C++ for VMA.
- **In the shipped binary:** mostly upstream C/C++ (shaderc/glslang dominate), with a thin Zig surface on top.

Estimates only — the bridges (VMA C++, shaderc/volk Zig) are now implemented, so the split reflects the real authored code rather than a plan.
