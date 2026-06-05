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

**Status:** `stable` = shipped & API-complete on `main` · `dev` = currently in development · `planned` = not yet started. *(No git tags are cut yet — formal tagging is part of the 1.0 hardening pass.)* The **Steps to cut this version** column is the concrete, ordered work that earns the tag — ☑ a shipped patch, ☐ still open; shipped versions list the patches that got them there. House rule for every box: a gated TDD session (red→green), one atomic commit per group, and the headless-Vulkan `nm` gate (zero `SDL_`/`x11`/`wayland`) stays green. Fuller TDD detail: [`completion-plan.md`](completion-plan.md).

**Patch convention:** each ☐ task is one **patch** release. Working a minor line `v0.x`, the first task done tags `v0.x.1`, the second `v0.x.2`, and so on (one atomic commit → one patch bump) — the `.N` prefix on each step is the patch it produces. The minor line is **complete** when its last ☐ lands; the next milestone opens the next minor (`v0.(x+1).1`).

| Version | Features | Steps to cut this version | Status |
| --- | --- | --- | --- |
| **v0.1.0** | `vk` re-export working (vulkan-zig typed API); volk / VMA / shaderc + surface creators stubbed (panic-on-call). Consumers can `@import("vulkan_stack").vk` and compile against the typed API. | ☑ **.1** pin vulkan-zig; generate bindings from `vk.xml` at build; re-export `pub const vk`. ☑ **.2** declare the module shape — `volk`/`vma`/`shaderc` slots + surface-creator signatures as `@panic` stubs that compile & link. ☑ **.3** explicit public error sets (`LoaderError`/`SurfaceError`/`vma.Error`/`shaderc.Error`). ☑ **.4** `api_test.zig` contract tests against the typed surface. | stable |
| **v0.2.0** | volk loader real (pure-Zig `std.DynLib`); **X11 + Wayland** surface creators real. Enables a real Vulkan instance + surface + clear screen. | ☑ **.1** pure-Zig volk — `std.DynLib` opens `libvulkan`, resolves `vkGetInstanceProcAddr` (`loadBase`/`getInstanceProcAddr`). ☑ **.2** feed the gipa to vulkan-zig `BaseWrapper`/`InstanceWrapper`/`DeviceWrapper`; `loadInstance`/`loadDevice` no-ops. ☑ **.3** `createX11Surface` — `vkCreateXlibSurfaceKHR` via `surfacePfn`/`surfaceResult`. ☑ **.4** `createWaylandSurface` — `vkCreateWaylandSurfaceKHR`. ☑ **.5** gated volk + surface TDD on the headless `VkCtx` harness. | stable |
| **v0.3.0** | VMA wrapper real — `createAllocator` / `createBuffer` / `createImage` / `mapMemory` + lifecycle. Enables vertex/index/uniform buffers and images. | ☑ **.1** `noexcept` C++ bridge over VMA (catch before crossing the C ABI). ☑ **.2** `createAllocator` / `destroyAllocator`. ☑ **.3** `createBuffer` / `createImage` (+ destroy). ☑ **.4** `mapMemory` / `unmapMemory`. ☑ **.5** gated VMA TDD (`03_vma_test.zig`). | stable |
| **v0.4.0** | shaderc wrapper real — `compile(glsl, stage)` → SPIR-V (built from source via `tiawl/shaderc.zig`, opt-in `-Dshaderc`); macro `-D` defines, target SPIR-V/Vulkan version, `#include` resolution, ray-tracing + task/mesh `Stage`s. | ☑ **.1** wire `tiawl/shaderc.zig` build-from-source under `-Dshaderc`; expose `shaderc.available`. ☑ **.2** `compile(glsl, stage)` → SPIR-V via `@cImport` over shaderc's C API. ☑ **.3** macro `-D` defines + target SPIR-V/Vulkan version. ☑ **.4** `#include` resolution. ☑ **.5** ray-tracing + task/mesh `Stage`s. ☑ **.6** gated shaderc TDD (`01_shaderc_test.zig` + `05_shaderc_advanced_test.zig`). | stable |
| **v0.5.0** | **Shipped:** VMA depth — `getAllocationInfo`, `flushAllocation`/`invalidateAllocation`, allocation `Flags` (host-access, persistent `mapped`, dedicated). **Remaining:** `createWin32Surface` + `createAndroidSurface` (X11 + Wayland already real). | ☑ **.1** VMA `getAllocationInfo`. ☑ **.2** `flushAllocation` / `invalidateAllocation` (non-coherent host memory). ☑ **.3** allocation `Flags` — host-access, persistent `mapped`, dedicated. ☐ **.4** `createWin32Surface` — `vkCreateWin32SurfaceKHR` via the existing `surfacePfn`/`surfaceResult` helpers (no SDL). ☐ **.5** `createAndroidSurface` — `vkCreateAndroidSurfaceKHR`, same shape. ☐ **.6** TDD `06_surface_win32_android_test.zig` — signature/type/wiring asserts (live path covered on X11/Wayland). ☐ **.7** CI cross-compile legs (`-Dtarget=x86_64-windows`, `aarch64-linux-android`) + `manual-testing.md` device e2e. **Minor done when** both surfaces compile on their cross-targets and the `nm` gate stays green. | **dev** |
| **v0.6.0** | **Opt-in swapchain abstraction** — a two-tier API: beginners get a `Swapchain` helper that picks sensible defaults (surface format/color-space, present mode, image count, extent clamp) and owns create / image-views / recreate-on-resize; pros stay on raw `vk`. **Raw is never blocked** (the abstraction is purely additive), and a **translate-to-raw escape hatch** maps the abstraction's choices back to raw Vulkan so a consumer can drop down at any point. See *Swapchain abstraction* below. | ☐ **.1** `Swapchain.Options` + default policy — format/color-space, present-mode (mailbox→FIFO fallback), image count, extent clamp from `SurfaceCapabilitiesKHR` / `SurfaceFormatKHR` / `PresentModeKHR`. ☐ **.2** `Swapchain.create` / `deinit` + image-view creation. ☐ **.3** `recreate` on resize / `error.OutOfDateKHR` (old-swapchain handoff). ☐ **.4** translate-to-raw: `toRaw()` exposing the `vk.SwapchainKHR` + images + views + the `vk.SwapchainCreateInfoKHR` used, and `buildCreateInfo()` returning the raw create-info **without** creating (pro path). ☐ **.5** TDD session; raw-only path still compiles & tree-shakes with the abstraction unused; `nm` gate stays green. **Minor done when** the helper round-trips to raw and the raw path is provably independent. | planned |
| **v0.7.0** | **Bootstrap helpers** — opt-in, raw-first wrappers over the painful setup boilerplate, same two-tier pattern as the v0.6 swapchain (defaults + a `toRaw`/policy escape hatch; raw `vk` never blocked). Covers the `vk-bootstrap`-style quartet (`Instance`, `PhysicalDevice` pick, `Device` + queues, `DebugMessenger`) plus per-frame plumbing (`FrameSync` ring, `CommandPool`, `shaderModule`). See *Opt-in helpers* below. | ☐ **.1** `Instance` — `create` (merge required + validation/debug-utils/portability extensions, load dispatch) + `selectExtensions` (pro: compute the list, create nothing) + `toRaw`. ☐ **.2** `PhysicalDevice.pick` — score (discrete>integrated), require `VK_KHR_swapchain`, discover graphics + present queue families. ☐ **.3** `Device.create` (+ `buildCreateInfo`) — enable the swapchain ext + chosen features, dedup queue families, expose the queues. ☐ **.4** `DebugMessenger` — `VK_EXT_debug_utils` callback (debug-only, opt-in). ☐ **.5** `FrameSync` ring — image-available / render-finished semaphores + in-flight fences for N frames-in-flight. ☐ **.6** `CommandPool` create + allocate; `shaderModule(spirv)` (pairs with shaderc). ☐ **.7** TDD `08_instance_test.zig` (+ sibling sessions); each raw-only path tree-shakes with its helper unused; `nm` gate stays green. **Minor done when** the quartet round-trips to raw and each raw path is provably independent. | planned |
| **v1.0.0** | Full stack stable; all surfaces incl. Win32 / Android (+ macOS Metal); the v0.6 swapchain + v0.7 bootstrap helpers frozen alongside the raw API; version-coherence pin documented; CI across targets; tree-shake verified; API frozen. | ☐ **.1** *(contributor-led, parallel)* `createMetalSurface` — `vkCreateMetalSurfaceEXT` (MoltenVK) consuming a `CAMetalLayer` from the platform lib's `getCocoaHandle`. ☐ **.2** pin deps to released tags + document the coherence pin (vulkan-zig `vk.xml` snapshot · VMA tag · `tiawl/shaderc.zig` tag). ☐ **.3** CI matrix: linux-x64 (X11 + Wayland) device tests against a software ICD (lavapipe/SwiftShader) + cross-compile Windows/Android + a `-Dshaderc` leg. ☐ **.4** wire the `nm` decoupling check as a **hard CI gate**. ☐ **.5** tree-shake check (dead-strip when `-Dshaderc` off). ☐ **.6** freeze public API + error sets (`SurfaceError`/`vma.Error`/`shaderc.Error`/`LoaderError`/`SwapchainError`/`InstanceError`); document stability. ☐ **.7** tick [`validation-apps.md`](validation-apps.md) → tag **v1.0.0**. | planned |

Critical path: v0.5 → v0.6 → v0.7 → v1.0; the macOS/Metal step (`v1.0.0 .1`) runs in parallel and is contributor-led. No milestones are planned **beyond v1.0.0** — SPIRV-Reflect, SPIRV-Cross, frame-graph, and the material pipeline are deliberately consumer-side (see *Deliberately NOT here* below).

## Opt-in helpers (raw-first) — the v0.6+ principle

Some Vulkan steps have a "right policy" with no single answer (swapchain format/present-mode; which physical device; which extensions), and others are just painful boilerplate (sync rings, command pools). Rather than pick a side, this stack adds **opt-in, two-tier helpers** — first the v0.6 swapchain, then the v0.7 bootstrap set. Every helper obeys the same three-tier shape:

- **Beginner tier — the helper.** Opt-in. Picks sane defaults from what the driver reports and owns create/teardown (and, for the swapchain, recreate-on-resize). Enough to get going without reading the spec.
- **Pro tier — raw `vk`, never blocked.** The raw path stays fully first-class and usable with the helper entirely absent (and tree-shaken out). The abstraction is *additive*, never a gate.
- **The bridge — translate-to-raw.** A `toRaw()` / accessor hands back the underlying `vk` handles, and a pure builder computes the helper's policy decisions **without** creating anything — `buildCreateInfo()` for the swapchain/device, `selectExtensions()` for the instance, the returned handle+indices for the physical-device pick. Start on the helper and drop to raw at any boundary, or take the computed policy and drive Vulkan yourself. No lock-in either direction.

Design constraints (must hold for every helper): no helper type appears in the raw signatures; the raw path compiles and links with the abstraction unreferenced (verified by the tree-shake check); and the headless-Vulkan `nm` gate stays green. This keeps the library's "consumer owns policy" stance while lowering the on-ramp.

**v0.6 — swapchain** (the first instance): format/color-space, present mode (mailbox→FIFO fallback), image count, extent clamp, image views, recreate; `toRaw()` + `buildCreateInfo()`.

**v0.7 — bootstrap helpers** (the `vk-bootstrap`-style setup quartet + per-frame plumbing): `Instance` (api version + required/validation/portability extensions; `selectExtensions` pro hook), `PhysicalDevice` pick (score + queue-family discovery), `Device` (+ queues, swapchain ext, features; `buildCreateInfo`), `DebugMessenger`, and the thin conveniences `FrameSync` (frames-in-flight semaphores/fences), `CommandPool`, and `shaderModule(spirv)` (pairs with shaderc). What stays raw/consumer: render-pass/pipeline/descriptor *policy*, frame graph, material system — see *Deliberately NOT here*.

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
