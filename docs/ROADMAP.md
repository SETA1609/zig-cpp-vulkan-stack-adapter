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

**Status:** `stable` = shipped & API-complete on `main` · `dev` = currently in development · `planned` = not yet started. *(No git tags are cut yet — formal tagging is part of the 1.0 hardening pass.)* The **Steps to cut this version** column is the concrete, ordered work that earns the tag; ☐ = open. House rule for every box: a gated TDD session (red→green), one atomic commit per group, and the headless-Vulkan `nm` gate (zero `SDL_`/`x11`/`wayland`) stays green. Fuller TDD detail: [`completion-plan.md`](completion-plan.md).

**Patch convention:** each ☐ task is one **patch** release. Working a minor line `v0.x`, the first task done tags `v0.x.1`, the second `v0.x.2`, and so on (one atomic commit → one patch bump) — the `.N` prefix on each step is the patch it produces. The minor line is **complete** when its last ☐ lands; the next milestone opens the next minor (`v0.(x+1).1`).

| Version | Features | Steps to cut this version | Status |
| --- | --- | --- | --- |
| **v0.1.0** | `vk` re-export working (vulkan-zig typed API); volk / VMA / shaderc + surface creators stubbed (panic-on-call). Consumers can `@import("vulkan_stack").vk` and compile against the typed API. | — shipped | stable |
| **v0.2.0** | volk loader real (pure-Zig `std.DynLib`); **X11 + Wayland** surface creators real. Enables a real Vulkan instance + surface + clear screen. | — shipped | stable |
| **v0.3.0** | VMA wrapper real — `createAllocator` / `createBuffer` / `createImage` / `mapMemory` + lifecycle. Enables vertex/index/uniform buffers and images. | — shipped | stable |
| **v0.4.0** | shaderc wrapper real — `compile(glsl, stage)` → SPIR-V (built from source via `tiawl/shaderc.zig`, opt-in `-Dshaderc`); macro `-D` defines, target SPIR-V/Vulkan version, `#include` resolution, ray-tracing + task/mesh `Stage`s. | — shipped | stable |
| **v0.5.0** | **Shipped:** VMA depth — `getAllocationInfo`, `flushAllocation`/`invalidateAllocation`, allocation `Flags` (host-access, persistent `mapped`, dedicated). **Remaining:** `createWin32Surface` + `createAndroidSurface` (X11 + Wayland already real). | ☐ **.1** `createWin32Surface` — `vkCreateWin32SurfaceKHR` via the existing `surfacePfn`/`surfaceResult` helpers (no SDL). ☐ **.2** `createAndroidSurface` — `vkCreateAndroidSurfaceKHR`, same shape. ☐ **.3** TDD `06_surface_win32_android_test.zig` — signature/type/wiring asserts (live path covered on X11/Wayland). ☐ **.4** CI cross-compile legs (`-Dtarget=x86_64-windows`, `aarch64-linux-android`) + `manual-testing.md` device e2e. **Minor done when** both surfaces compile on their cross-targets and the `nm` gate stays green. | **dev** |
| **v0.6.0** | **Opt-in swapchain abstraction** — a two-tier API: beginners get a `Swapchain` helper that picks sensible defaults (surface format/color-space, present mode, image count, extent clamp) and owns create / image-views / recreate-on-resize; pros stay on raw `vk`. **Raw is never blocked** (the abstraction is purely additive), and a **translate-to-raw escape hatch** maps the abstraction's choices back to raw Vulkan so a consumer can drop down at any point. See *Swapchain abstraction* below. | ☐ **.1** `Swapchain.Options` + default policy — format/color-space, present-mode (mailbox→FIFO fallback), image count, extent clamp from `SurfaceCapabilitiesKHR` / `SurfaceFormatKHR` / `PresentModeKHR`. ☐ **.2** `Swapchain.create` / `deinit` + image-view creation. ☐ **.3** `recreate` on resize / `error.OutOfDateKHR` (old-swapchain handoff). ☐ **.4** translate-to-raw: `toRaw()` exposing the `vk.SwapchainKHR` + images + views + the `vk.SwapchainCreateInfoKHR` used, and `buildCreateInfo()` returning the raw create-info **without** creating (pro path). ☐ **.5** TDD session; raw-only path still compiles & tree-shakes with the abstraction unused; `nm` gate stays green. **Minor done when** the helper round-trips to raw and the raw path is provably independent. | planned |
| **v1.0.0** | Full stack stable; all surfaces incl. Win32 / Android (+ macOS Metal); the v0.6 swapchain abstraction frozen alongside the raw API; version-coherence pin documented; CI across targets; tree-shake verified; API frozen. | ☐ **.1** *(contributor-led, parallel)* `createMetalSurface` — `vkCreateMetalSurfaceEXT` (MoltenVK) consuming a `CAMetalLayer` from the platform lib's `getCocoaHandle`. ☐ **.2** pin deps to released tags + document the coherence pin (vulkan-zig `vk.xml` snapshot · VMA tag · `tiawl/shaderc.zig` tag). ☐ **.3** CI matrix: linux-x64 (X11 + Wayland) device tests against a software ICD (lavapipe/SwiftShader) + cross-compile Windows/Android + a `-Dshaderc` leg. ☐ **.4** wire the `nm` decoupling check as a **hard CI gate**. ☐ **.5** tree-shake check (dead-strip when `-Dshaderc` off). ☐ **.6** freeze public API + error sets (`SurfaceError`/`vma.Error`/`shaderc.Error`/`LoaderError`); document stability. ☐ **.7** tick [`validation-apps.md`](validation-apps.md) → tag **v1.0.0**. | planned |

Critical path: v0.5 → v0.6 → v1.0; the macOS/Metal step (`v1.0.0 .1`) runs in parallel and is contributor-led. No milestones are planned **beyond v1.0.0** — SPIRV-Reflect, SPIRV-Cross, frame-graph, and the material pipeline are deliberately consumer-side (see *Deliberately NOT here* below).

## Swapchain abstraction (opt-in, raw-first) — v0.6.0

The swapchain is the one piece where "what's the right policy?" (format, present mode, image count, recreation) has no single answer — so historically this stack left it entirely to the consumer (raw `vk` only). v0.6 adds a **two-tier API** instead of picking a side:

- **Beginner tier — the `Swapchain` helper.** Opt-in. Picks sane defaults from the surface's reported capabilities, creates the swapchain + image views, and recreates on resize / `error.OutOfDateKHR`. Enough to get pixels on screen without reading the Vulkan spec.
- **Pro tier — raw `vk`, never blocked.** The raw `vk.createSwapchainKHR` path stays fully first-class and usable with the helper entirely absent (and tree-shaken out). The abstraction is *additive*, never a gate.
- **The bridge — translate-to-raw.** `Swapchain.toRaw()` hands back the underlying `vk.SwapchainKHR`, its images/views, and the exact `vk.SwapchainCreateInfoKHR` it used; `buildCreateInfo()` returns that create-info **without** creating anything. So a consumer can start on the helper and drop to raw at any boundary, or let the helper compute a good create-info and then drive Vulkan themselves — no lock-in either direction.

Design constraints (must hold): no helper type appears in the raw signatures; the raw path compiles and links with the abstraction unreferenced (verified by the tree-shake check); and the headless-Vulkan `nm` gate stays green. This keeps the library's "consumer owns policy" stance while lowering the on-ramp.

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
