# Contributing — zig-cpp-vulkan-stack-adapter

Thanks for your interest! This is a standalone, single-maintainer Zig library,
built **test-first**. Please read this before opening a PR.

## What this library is

A **version-coherent** Vulkan stack — vulkan-zig + volk + VMA + shaderc bundled in one repo — surfaced as idiomatic Zig. See [`docs/vision.md`](docs/vision.md) and [`docs/mission.md`](docs/mission.md).

## Maintainer stance

- Validated on **Linux + Windows** first. macOS / Metal is **in scope, not deferred** — but the maintainer won't build or test it, so it's contributor-led: a clean, self-tested PR is welcome. The concrete piece is `createMetalSurface` (`vkCreateMetalSurfaceEXT` via MoltenVK, consuming a `CAMetalLayer` from the platform lib's `getCocoaHandle`). See the macOS row in [`docs/completion-plan.md`](docs/completion-plan.md).
- Docs / link-rot / build-config PRs are welcome any time.

## The version-coherence rule — the whole point of this repo

VMA's headers, vulkan-zig's generated bindings, and shaderc's SPIR-V target **must move together**. Therefore:

- **Never bump one bundled lib in isolation.** A PR touching any of vulkan-zig / volk / VMA / shaderc versions must bump them as a coherent set and re-run the validation apps.
- One `build.zig.zon` pins all four. If a bump breaks a signature, that's the system working — fix the *set*, don't paper over one lib.

## Test-first development

The public API (`src/root.zig` + `volk.zig` / `vma.zig` / `shaderc.zig`) is
almost entirely implemented: the `vk` re-export, the `volk` loader, the X11 +
Wayland surface creators, VMA (incl. depth), and shaderc (incl. depth) are real.
Only `createWin32Surface` / `createAndroidSurface` remain
`@panic("not implemented")` stubs (see [`docs/completion-plan.md`](docs/completion-plan.md)).
Implementing or extending the library means replacing/adding behind a stub and
proving it — by an automated test where the result is provable in-process, or by
an e2e procedure where it needs a live GPU.

### The two test steps

| Step | File(s) | What it is | When it runs |
| --- | --- | --- | --- |
| `zig build test` | `src/tests/api_test.zig` | **Contract / data tests** — the real `vk` re-export, wrapper enum values, option defaults. Need no GPU. | **Gates CI** — must always be green. |
| `zig build test-tdd` | `src/tests/tdd/*` | **Ordered red→green suite** — every test calls the real function and asserts its result; each carries a `// WHEN … · GIVEN … · THEN …` spec. shaderc sessions need `-Dshaderc`; the VMA sessions need a live Vulkan device. | Off CI (needs a device / `-Dshaderc`). |

### Two kinds of work

**1. Automated (shaderc) — has a TDD test.** `shaderc.compile` (and its
`*Diagnostics` failure path) is pure-CPU GLSL→SPIR-V: the result is fully
verifiable with no GPU, instance, or device. It lives in the TDD suite
(`01_shaderc_test.zig` + `05_shaderc_advanced_test.zig`, under `-Dshaderc`).

**2. e2e (volk, surfaces, VMA) — has a manual procedure.** These return opaque
Vulkan handles or mutate GPU state, only meaningful against a live
instance/device/window — they **cannot** be unit-tested. Implement them against
the e2e procedures in [`docs/manual-testing.md`](docs/manual-testing.md) and the
examples-repo Vulkan clear-color rung.

### The contributor workflow

**For shaderc (automated):** add behavior in `src/shaderc.zig`, add a test with a
`// WHEN … · GIVEN … · THEN …` spec to the matching session
(`01_shaderc_test.zig` / `05_shaderc_advanced_test.zig`); run
`zig build test-tdd -Dshaderc` until green, then the whole suite and
`zig build test`; tick the box in `docs/manual-testing.md`.

**For volk / surfaces / VMA (e2e):** implement the function(s) + bridge code;
walk the matching procedure in `docs/manual-testing.md` (validation layers on)
and confirm every **pass criterion**; tick the box in its coverage checklist.

A PR may implement **one or more** functions.

### Definition of done

- **shaderc:** **every one of its TDD tests passes** under `-Dshaderc` — not
  skipped, not commented out.
- **volk / surfaces / VMA:** the e2e procedure passes with **zero validation
  errors**, and the headless-Vulkan `nm` decoupling check (zero
  `SDL_`/`x11`/`wayland` symbols, `docs/manual-testing.md`) holds.
- `zig build test` (contract) and `zig fmt --check .` stay green.

Do **not** disable, comment out, or weaken a test to make something pass. If a
test encodes the wrong contract, fix the test in the same PR and say so.

### The implementation ladder

| # | Area | Functions | Kind | Milestone | Depends on |
| --- | --- | --- | --- | --- | --- |
| 1 | shaderc | `compile` (+ macros / `target` / `#include` / RT + mesh stages) · `Diagnostics` | **TDD** (`01_`/`05_shaderc*_test.zig`) | v0.4.0 | — |
| 2 | volk | `loadBase` · `loadInstance` · `loadDevice` | e2e (`manual-testing.md` §1) | v0.2.0 | a Vulkan loader |
| 3 | surfaces | `createX11Surface` · `createWaylandSurface` (real) · `createWin32Surface` · `createAndroidSurface` (stubbed) | e2e (§2) + **TDD** (`06_surface_win32_android_test.zig`, wiring/type checks) | v0.2.0 / v0.5.0 | 2, a window handle |
| 4 | VMA | `createAllocator`/`destroyAllocator` · `createBuffer(WithFlags)`/`destroyBuffer` · `createImage(WithFlags)`/`destroyImage` · `mapMemory`/`unmapMemory` · `getAllocationInfo` · `flush`/`invalidateAllocation` | e2e (§3) + **TDD** (`03_`/`04_vma*_test.zig`, needs a device) | v0.3.0 / v0.5.0 | 2, a `VkDevice` |
| 5 | swapchain | `Swapchain.create`/`deinit`/`recreate`/`toRaw`/`buildCreateInfo` (+ `Options`/`Raw`/`Error`) | **TDD** (`07_swapchain_test.zig`, options/policy + bridge) + e2e (§5, the create path needs a device) | v0.6.0 | 2, a `VkDevice` + surface |

(The `vk` re-export is real from v0.1.0 and already covered by `zig build test`.)
The surface section is the **cross-library** test — it consumes the native
handles from the companion **platform adapter**; that decoupling is the point of
the two libraries.

## C++ bridge discipline (hard rules)

Much of this library's backend is C/C++ by nature — VMA is header-only **C++**,
shaderc ships a **C** API, volk is a **C** loader. You are free to use C and C++
for that code, but it stays **behind the Zig API**:

- Every `extern "C"` boundary function (the VMA bridge — shaderc needs none, it ships a C API consumed via `@cImport`) is **`noexcept`** and **catches all exceptions before it crosses the C ABI**.
- **No C++ type (class / template / `std::*`) crosses the boundary** — the Zig wrappers (`src/vma.zig`, `src/shaderc.zig`) own the idiomatic surface.
- **C++ style: Google conventions, max C++23.** Already encoded in [`.clang-format`](.clang-format) (`BasedOnStyle: Google`, `Standard: Latest`). Run `clang-format`; do not use language features past C++23.
- **Smart pointers first, manual pointers later — in separate PRs.** Write the initial bridge with RAII / smart pointers (`std::unique_ptr`, `std::shared_ptr`) so ownership is obviously correct, and land that. If profiling later shows a smart-pointer is a real cost on a hot path, move it to a manual / raw pointer **in a follow-up PR** dedicated to that optimization, with the measurement that justifies it. Correctness first, optimization second, never mixed in one PR.

## Out of scope

- Windowing (companion [platform-stack adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter)).
- Frame graph / render passes / materials (consumer code).
- Adding a lib that isn't Vulkan-version-coupled — that belongs *outside* this bundle (e.g. SPIRV-Reflect is a consumer-side `@cImport`).

## Licensing & legal

- Contributions are licensed under this repo's **MIT** license. By submitting a PR you agree to MIT. **No CLA required.**
- **No GPL / LGPL / AGPL dependencies.** Bundled libs stay MIT / Apache-2.0 / BSD only.

## Dev setup

- **Zig 0.16+**; `zig build`, `zig build test` (contract suite), `zig build test-tdd` (red→green TDD suite — needs a Vulkan device + `-Dshaderc` for the shaderc sessions).
- **`./scripts/ci.sh [check|clang-format|shaderc|device-tests]`** runs the CI gates locally; the workflow just installs the toolchain / ICD and calls this same script.
- **Reproducible container:** `docker build -t vk-stack .` then `docker run --rm vk-stack` runs the gate in a clean image; `docker run --rm vk-stack bash scripts/ci.sh device-tests` runs the volk/VMA suite against lavapipe (software Vulkan — no GPU).
- Lint: `zig fmt --check .` + `clang-format-18 --dry-run -Werror` on `src/c` (the `.clang-format` `Standard: Latest` needs clang-format-18). CI runs these, plus a `lint-workflows` job that validates the workflow YAML with the bundled [`check-workflows` skill](.claude/skills/check-workflows).

## Commits & PRs

- **Conventional Commits**, atomic, subject ≤ 72 chars.
- Larger work (adding to the stack, an API change): **open an issue first.**
- New functionality should add a validation app or a test (see [`docs/validation-apps.md`](docs/validation-apps.md)).
