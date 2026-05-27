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
| [shaderc](https://github.com/google/shaderc) (over glslang BSD-3) | Apache-2.0 | `vk_stack.shaderc` — GLSL→SPIR-V; `extern "C"` bridge → idiomatic Zig | v0.4.0 |

Plus per-OS **surface creators** (`createX11Surface`/`createWaylandSurface`/`createWin32Surface`/`createAndroidSurface`) — each takes raw OS primitives, **no windowing-library import**.

## Version milestones

| Version | Scope | Enables |
| --- | --- | --- |
| **v0.1.0** | `vk` re-export working; volk / VMA / shaderc + surface creators stubbed panic-on-call | Consumers can `@import("vulkan_stack").vk` and compile against the typed API |
| **v0.2.0** | volk loader real + per-OS surface creators real (X11 + Win32) | A real Vulkan instance + surface + clear screen |
| **v0.3.0** | VMA wrapper real — `createBuffer` / `createImage` / lifecycle | Vertex/index/uniform buffers, images |
| **v0.4.0** | shaderc wrapper real — `compile(glsl, stage)` → SPIR-V | Runtime GLSL compilation (consumers can otherwise embed precompiled SPIR-V) |
| **v0.5.0** | Wayland + Android surface creators; full per-OS coverage | All target platforms |
| **v1.0.0** | Full stack stable; version-coherence pin documented; CI across targets; tree-shake verified | Production-ready 1.0 |

## Note on volk vs. vulkan-zig

vulkan-zig generates its own dispatch wrappers from `vk.xml`, which overlaps volk's loader role. volk stays in the lineup for now, but whether it's still needed once vulkan-zig's dispatch is wired is worth revisiting at v0.2.0 — if redundant, drop it and reclaim a vendored dependency.

## Deliberately NOT here

| Item | Where |
| --- | --- |
| Windowing | companion [platform-stack adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter) |
| SPIRV-Reflect | consumer-side `@cImport` (not Vulkan-version-coupled) |
| SPIRV-Cross | deferred (Metal/D3D transpile) |
| Frame graph / material pipeline | consumer code |

## C++ boundary discipline

Every `extern "C"` bridge function (VMA, shaderc) is `noexcept` and catches all exceptions before they cross the C ABI. See [`.github/CONTRIBUTING.md`](../.github/CONTRIBUTING.md).

## See also

- Companion library: [zig-cpp-platform-stack-adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter)
- Sprint plan: [`sprint.md`](sprint.md) · Test apps: [`validation-apps.md`](validation-apps.md)
- Deeper design rationale: the catalog in the [zVoxRealms](https://github.com/SETA1609/zigVoxelWorlds) project (the engine this was built for).
