# Milestone plan — v0.1.0 → v0.4.0

> The plan to bring the four bundled libs from stub → real, across four tagged releases. By v0.4.0 a consumer can render with `vk_stack.{vk, volk, vma, shaderc}` + the per-OS surface creators. Roadmap: [`ROADMAP.md`](ROADMAP.md).
>
> **Definition of done (for the set):** `v0.1.0`–`v0.4.0` tagged; a consumer's surface bridge resolves and produces a non-null surface; `nm` on a Linux build shows no Windows/Android surface symbols; CI green on `x86_64-linux-gnu` + `x86_64-windows-gnu`.

Each `[ ]` is one atomic commit (Conventional Commits, subject ≤ 72 chars).

> **Historical plan — execution diverged on three points** (see [`ROADMAP.md`](ROADMAP.md) / [`completion-plan.md`](completion-plan.md) for the current state):
> the surface code lives in `src/root.zig`, **not** a separate `src/surface.zig`; **Wayland** shipped in v0.2.0 alongside X11 (Win32/Android are the remaining stubs); and **shaderc has no C++ bridge** — it is a pure-Zig `@cImport` over shaderc's C API, built from source by `tiawl/shaderc.zig` under `-Dshaderc` (so "§ D / V4.1 vendor shaderc + `shaderc_bridge.{h,cpp}`" did not happen). VMA depth and shaderc depth (macros, target, `#include`, RT/mesh stages) landed after v0.4.0.

## § A — v0.1.0: vk re-export

- [ ] **V1.1** `build.zig.zon`: add [vulkan-zig](https://github.com/Snektron/vulkan-zig) as a pinned dependency.
  - Commit: `chore(zon): add vulkan-zig dependency (pinned)`

- [ ] **V1.2** `build.zig`: drop the hello-world executable; expose a `vulkan_stack` module; wire vulkan-zig's `vk.xml` codegen.
  - Acceptance: `zig build` produces a static lib exporting `vulkan_stack`
  - Commit: `feat(build): expose vulkan_stack module + wire vulkan-zig codegen`

- [ ] **V1.3** `src/root.zig`: `pub const vk = @import("vulkan");` + stub `vma` / `volk` / `shaderc` and the per-OS surface creators as panic-on-call.
  - Acceptance: a consumer can reach `vk.Instance`, `vk.SurfaceKHR`
  - Commit: `feat(api): re-export vk; stub vma/volk/shaderc/surface (panic-on-call)`

- [ ] **V1.4** Tag `v0.1.0`; push.

## § B — v0.2.0: loader + surface creators

- [ ] **V2.1** Vendor volk under `vendor/volk/` (submodule); `src/volk.zig` thin Zig wrapper loading `vkGetInstanceProcAddr` + instance/device tables. *(Skip if the review concludes vulkan-zig's own dispatch suffices — see ROADMAP note.)*
  - Commit: `feat(volk): real loader wrapper`

- [ ] **V2.2** `src/surface.zig`: real `createX11Surface` + `createWin32Surface` calling `vkCreate{Xlib,Win32}SurfaceKHR`. Wayland/Android stay stubbed until v0.5.0.
  - Acceptance: a valid `vk.Instance` + raw display/window pointers → non-null `vk.SurfaceKHR`; validation layer clean
  - Commit: `feat(surface): implement createX11Surface + createWin32Surface`

- [ ] **V2.3** Tag `v0.2.0`; push.

## § C — v0.3.0: VMA

- [ ] **V3.1** Add VMA as a pinned `build.zig.zon` dependency (header-only); `src/c/vma_bridge.{h,cpp}` — `extern "C"` bridge, every boundary fn `noexcept` and catching before crossing the C ABI.
  - Commit: `feat(vma): extern C bridge over VulkanMemoryAllocator`

- [ ] **V3.2** `src/vma.zig`: idiomatic Zig wrapper — `createBuffer` / `createImage` / `destroyBuffer` + allocator lifecycle.
  - Acceptance: allocate + free a vertex buffer; no validation-layer complaints
  - Commit: `feat(vma): idiomatic Zig wrapper — createBuffer/createImage`

- [ ] **V3.3** Tag `v0.3.0`; push.

## § D — v0.4.0: shaderc (consumers may otherwise embed precompiled SPIR-V)

- [ ] **V4.1** Vendor shaderc under `vendor/shaderc/` (submodule, Apache-2.0 over glslang BSD-3); `src/c/shaderc_bridge.{h,cpp}`.
  - Commit: `feat(shaderc): extern C bridge over shaderc`

- [ ] **V4.2** `src/shaderc.zig`: `compile(allocator, source, stage)` → SPIR-V bytes.
  - Acceptance: a trivial `.vert` compiles to valid SPIR-V
  - Commit: `feat(shaderc): idiomatic Zig wrapper — compile GLSL→SPIR-V`

- [ ] **V4.3** Tag `v0.4.0`; push.

## § E — Docs + CI (alongside the above)

- [ ] **V5.1** Keep `README.md` build/status in sync as wrapping lands.
  - Commit: `docs(readme): update status as wrapping lands`

- [ ] **V5.2** CI: build on `x86_64-linux-gnu` + `x86_64-windows-gnu`; `zig fmt --check` + `clang-format --dry-run -Werror` on `src/c`.
  - Commit: `ci: build + lint C bridges on linux + windows`
