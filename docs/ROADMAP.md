# Roadmap — zig-cpp-vulkan-stack-adapter

> The versioned plan for this library, which bundles **vulkan-zig + volk + VMA + shaderc** version-pinned together. Sprint-level breakdown: [`sprint.md`](sprint.md).
>
> **Why bundled:** VMA's headers embed specific Vulkan-1.x signatures, vulkan-zig's bindings come from a specific `vk.xml` snapshot, and shaderc emits SPIR-V for a specific Vulkan version — they must move together or you get cryptic runtime errors. One `build.zig.zon` enforces atomic version coherence.

## Bundled libs

| Lib | License | Surfaces as | Real at |
| --- | --- | --- | --- |
| [vulkan-zig](https://github.com/Snektron/vulkan-zig) | MIT | `pub const vk = @import("vulkan")` re-export — typed enums, error sets, comptime dispatch | v0.1.0 |
| [volk](https://github.com/zeux/volk) | MIT | `vk_stack.volk` — loader / function-pointer table | v0.2.0 |
| [VMA](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) | MIT | `vk_stack.vma` — GPU memory; `extern "C"` bridge → idiomatic Zig | v0.3.0 |
| [shaderc](https://github.com/google/shaderc) (over glslang BSD-3) | Apache-2.0 | `vk_stack.shaderc` — GLSL→SPIR-V; pure-Zig `@cImport` over shaderc's C API (no C++ bridge), built from source via [`tiawl/shaderc.zig`](https://github.com/tiawl/shaderc.zig) under `-Dshaderc` | v0.4.0 |

Plus per-OS **surface creators** (`createX11Surface`/`createWaylandSurface`/`createWin32Surface`/`createAndroidSurface`) — each takes raw OS primitives, **no windowing-library import**.

## Version milestones

Status: ✅ shipped · 🚧 partial · ⬜ planned.

| Version | Status | Scope | Enables |
| --- | --- | --- | --- |
| **v0.1.0** | ✅ | `vk` re-export working; volk / VMA / shaderc + surface creators stubbed panic-on-call | Consumers can `@import("vulkan_stack").vk` and compile against the typed API |
| **v0.2.0** | ✅ | volk loader real (pure-Zig `std.DynLib`) + **X11 + Wayland** surface creators real | A real Vulkan instance + surface + clear screen |
| **v0.3.0** | ✅ | VMA wrapper real — `createAllocator` / `createBuffer` / `createImage` / `mapMemory` / lifecycle | Vertex/index/uniform buffers, images |
| **v0.4.0** | ✅ | shaderc wrapper real — `compile(glsl, stage)` → SPIR-V (built from source via `tiawl/shaderc.zig`, opt-in `-Dshaderc`); **+ depth:** macro `-D` defines, target SPIR-V/Vulkan version, `#include` resolution, ray-tracing + task/mesh `Stage`s | Runtime GLSL compilation with includes/macros (consumers can otherwise embed precompiled SPIR-V) |
| **v0.5.0** | 🚧 | **VMA depth shipped** — `getAllocationInfo`, `flushAllocation` / `invalidateAllocation`, allocation `Flags` (host-access, persistent `mapped`, dedicated). **Remaining:** Win32 + Android surface creators (X11 + Wayland already real) | Non-coherent host memory + persistent mapping; full per-OS surface coverage |
| **v1.0.0** | ⬜ | Full stack stable; version-coherence pin documented; CI across targets; tree-shake verified | Production-ready 1.0 |

## Note on volk vs. vulkan-zig

vulkan-zig generates its own dispatch wrappers from `vk.xml`, which overlaps volk's loader role. **Resolved at v0.2.0:** rather than vendor volk's C, the loader is reimplemented in **pure Zig** (`std.DynLib` opens `libvulkan` and resolves `vkGetInstanceProcAddr`); that bootstrap then feeds vulkan-zig's `BaseWrapper`/`InstanceWrapper`/`DeviceWrapper`, which own the typed dispatch. So there's no vendored C loader to keep version-coherent, and the binary doesn't hard-link `libvulkan`. `volk.loadInstance`/`loadDevice` are no-ops (the wrappers load).

## Deliberately NOT here

| Item | Where |
| --- | --- |
| Windowing | companion [platform-stack adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter) |
| SPIRV-Reflect | consumer-side `@cImport` (not Vulkan-version-coupled) |
| SPIRV-Cross | deferred (Metal/D3D transpile) |
| Frame graph / material pipeline | consumer code |

## C++ boundary discipline

VMA is the only C++↔Zig boundary: its `extern "C"` bridge functions are `noexcept` and catch all exceptions before crossing the C ABI. shaderc needs no bridge — it ships a C API consumed directly via `@cImport`. See [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## See also

- Companion library: [zig-cpp-platform-stack-adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter)
- Sprint plan: [`sprint.md`](sprint.md) · Test apps: [`validation-apps.md`](validation-apps.md)
- Deeper design rationale: the catalog in the [zVoxRealms](https://github.com/SETA1609/zigVoxelWorlds) project (the engine this was built for).
