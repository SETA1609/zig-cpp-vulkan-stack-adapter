# Completion plan — zig-cpp-vulkan-stack-adapter → 1.0

> The path from today's state to a stable **v1.0.0**. Milestone targets live in
> [`ROADMAP.md`](ROADMAP.md); this doc is the *ordered, actionable* breakdown.
> Every feature group follows the house workflow: a gated TDD session under
> `src/tests/tdd/` (red→green), one atomic commit per group, a
> `// WHEN … · GIVEN … · THEN …` spec per test, and the headless-Vulkan `nm`
> decoupling check stays green (zero `SDL_`/`x11`/`wayland` symbols).

## Where we are

✅ `vk` re-export · `volk` (pure-Zig `std.DynLib`) · **X11 + Wayland** surfaces ·
**VMA** (create/destroy buffer+image, map/unmap, **+ depth:** `getAllocationInfo`,
`flushAllocation`/`invalidateAllocation`, allocation `Flags`) · **shaderc**
(`compile`, **+ depth:** macros, target version, `#include`, ray-tracing +
task/mesh stages).

🚧 The **two surface functions still `@panic`**: `createWin32Surface`,
`createAndroidSurface`. The **v0.6.0 `Swapchain` abstraction** is scaffolded —
`Swapchain` + `Options` / `Raw` / `Error` and the methods
`create` / `deinit` / `recreate` / `toRaw` / `buildCreateInfo` exist with their
final signatures, but every body still `@panic`s.

## Phase V1 — finish per-OS surfaces (closes v0.5.0)

Size: **S** · CI: build-only on Linux (cross-compile), behavior on real devices.

- [ ] `createWin32Surface` — `vkCreateWin32SurfaceKHR` via the existing
      `surfacePfn`/`surfaceResult` helpers (the pattern X11/Wayland use). No SDL.
- [ ] `createAndroidSurface` — `vkCreateAndroidSurfaceKHR`, same shape.
- [ ] TDD session `06_surface_win32_android_test.zig` — signature/type checks +
      wiring asserts (the live behavioral path is covered on X11/Wayland; these
      can't run on Linux).
- [ ] CI **cross-compile legs** (`-Dtarget=x86_64-windows`, `aarch64-linux-android`)
      to prove they compile; add a `manual-testing.md` e2e for device sign-off.

## Phase V1.5 — opt-in swapchain abstraction (closes v0.6.0)

Size: **M** · e2e on a real device (the create path needs a surface + device);
the policy + bridge are unit-checkable in-process.

- [ ] `Swapchain.Options` + the default policy — pick format / present mode /
      image count / extent from the surface caps, clamping every wish.
- [ ] `Swapchain.create` / `deinit` — make the `VkSwapchainKHR` + one image view
      per image; release the owned slices.
- [ ] `Swapchain.recreate` — on resize / `error.OutOfDateKHR`, reusing the old
      swapchain as `oldSwapchain` for a gapless handoff.
- [ ] `toRaw()` + `buildCreateInfo()` bridge — hand back the raw handle / images /
      views / create-info; compute a `vk.SwapchainCreateInfoKHR` creating nothing.
- [ ] TDD session `07_swapchain_test.zig` (options/policy + `toRaw`/`buildCreateInfo`
      contract) + the **raw-only tree-shake** check (raw `vk` swapchain with this
      module unreferenced) + the headless `nm` decoupling gate stays green.

## Phase V2 — macOS / Metal (in scope, contributor-led)

Size: **M** · **Not maintainer-tested** — see [`CONTRIBUTING.md`](../CONTRIBUTING.md).

- [ ] `createMetalSurface` — `vkCreateMetalSurfaceEXT` (MoltenVK), consuming a
      `CAMetalLayer` from the platform lib's `getCocoaHandle`. This is the one
      piece that unblocks macOS for **both** libs.
- Parallel to V1/V3; a clean self-tested PR is welcome. 1.0 *CI* is gated to
  Linux/Windows/Android, but the function is in scope so coverage is complete.

## Phase V3 — 1.0 hardening

Size: **M–L** · mostly infra.

- [ ] **Pin deps to released tags** and document the coherence pin (vulkan-zig's
      `vk.xml` snapshot · VMA vendor tag · `tiawl/shaderc.zig` tag) — a bump must
      move the set atomically (the whole reason the libs are bundled).
- [ ] **CI matrix.** linux-x64 (X11 + Wayland) running the device-dependent
      volk/VMA/surface/shaderc→`vkCreateShaderModule` tests against a **software
      Vulkan ICD (lavapipe / SwiftShader)** so they execute headless in CI
      (today they need a GPU); cross-compile legs for Windows + Android; a
      `-Dshaderc` leg.
- [ ] **Wire the `nm` decoupling check as a hard CI gate.**
- [ ] **Tree-shake check** — verify dead-strip when `-Dshaderc` is off.
- [ ] **Freeze** the public API + error sets (`SurfaceError` / `vma.Error` /
      `shaderc.Error` / `LoaderError`); document stability.
- [ ] Tick [`validation-apps.md`](validation-apps.md) → tag **v1.0.0**.

## Critical path

V1 → V1.5 → V3. V2 (macOS) runs in parallel and is contributor-led. Realistically
a small number of focused sessions: the surfaces are quick, the swapchain helper
is medium; the bulk of the remaining effort is the CI/lavapipe + pinning
hardening in V3.

## Deliberately still NOT in 1.0

SPIRV-Reflect / SPIRV-Cross / frame-graph / material pipeline — consumer-side, by
design (see [`ROADMAP.md`](ROADMAP.md) "Deliberately NOT here").
