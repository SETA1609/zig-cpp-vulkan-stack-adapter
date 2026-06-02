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

The public API (`src/root.zig` + `volk.zig` / `vma.zig` / `shaderc.zig`) is a
complete set of signatures whose bodies are `@panic("not implemented")` stubs
(the `vk` re-export is the one already-real piece). Implementing the library
means replacing a stub and proving it — by an automated test where the result is
provable in-process, or by an e2e procedure where it needs a live GPU.

### The two test steps

| Step | File(s) | What it is | When it runs |
| --- | --- | --- | --- |
| `zig build test` | `src/tests/api_test.zig` | **Contract / data tests** — the real `vk` re-export, wrapper enum values, option defaults. Need no GPU. | **Gates CI** — must always be green. |
| `zig build test-tdd` | `src/tests/tdd/*` | **Ordered red→green suite** — every test calls the real function and asserts its result, skipped behind a `done` flag until implemented. | Off CI. Green today (all skipped). |

### Two kinds of work

**1. Automated (shaderc) — has a TDD test.** `shaderc.compile` /
`lastErrorMessage` are pure-CPU GLSL→SPIR-V: their result is fully verifiable
with no GPU, instance, or device. They live in the TDD suite.

**2. e2e (volk, surfaces, VMA) — has a manual procedure.** These return opaque
Vulkan handles or mutate GPU state, only meaningful against a live
instance/device/window — they **cannot** be unit-tested. Implement them against
the e2e procedures in [`docs/manual-testing.md`](docs/manual-testing.md) and the
examples-repo Vulkan clear-color rung.

### The contributor workflow

**For shaderc (automated):** implement `shaderc.compile` (then `lastErrorMessage`)
in `src/shaderc.zig`; flip `done.compile` / `done.lastErrorMessage` in
`src/tests/tdd/01_shaderc_test.zig` from `false` to `true`; run
`zig build test-tdd -- --test-filter compile` until green, then the whole suite
and `zig build test`; tick the box in `docs/manual-testing.md`.

**For volk / surfaces / VMA (e2e):** implement the function(s) + bridge code;
walk the matching procedure in `docs/manual-testing.md` (validation layers on)
and confirm every **pass criterion**; tick the box in its coverage checklist.

A PR may implement **one or more** functions.

### Definition of done

- **shaderc:** the `done.<fn>` flag is `true` and **every one of its TDD tests
  passes** — not skipped, not commented out.
- **volk / surfaces / VMA:** the e2e procedure passes with **zero validation
  errors**, and the headless-Vulkan `nm` decoupling check (zero
  `SDL_`/`x11`/`wayland` symbols, `docs/manual-testing.md`) holds.
- `zig build test` (contract) and `zig fmt --check .` stay green.

Do **not** disable, comment out, or weaken a test to make something pass. If a
test encodes the wrong contract, fix the test in the same PR and say so.

### The implementation ladder

| # | Area | Functions | Kind | Milestone | Depends on |
| --- | --- | --- | --- | --- | --- |
| 1 | shaderc | `compile` · `lastErrorMessage` | **TDD** (`01_shaderc_test.zig`) | v0.4.0 | — |
| 2 | volk | `loadBase` · `loadInstance` · `loadDevice` | e2e (`manual-testing.md` §1) | v0.2.0 | a Vulkan loader |
| 3 | surfaces | `createX11Surface` · `createWaylandSurface` · `createWin32Surface` · `createAndroidSurface` | e2e (§2) | v0.2.0 / v0.5.0 | 2, a window handle |
| 4 | VMA | `createAllocator`/`destroyAllocator` · `createBuffer`/`destroyBuffer` · `createImage`/`destroyImage` · `mapMemory`/`unmapMemory` | e2e (§3) | v0.3.0 | 2, a `VkDevice` |

(The `vk` re-export is real from v0.1.0 and already covered by `zig build test`.)
The surface section is the **cross-library** test — it consumes the native
handles from the companion **platform adapter**; that decoupling is the point of
the two libraries.

## C++ bridge discipline (hard rules)

Much of this library's backend is C/C++ by nature — VMA is header-only **C++**,
shaderc ships a **C** API, volk is a **C** loader. You are free to use C and C++
for that code, but it stays **behind the Zig API**:

- Every `extern "C"` boundary function (VMA, shaderc bridges) is **`noexcept`** and **catches all exceptions before they cross the C ABI**.
- **No C++ type (class / template / `std::*`) crosses the boundary** — the Zig wrappers (`src/vma.zig`, `src/shaderc.zig`) own the idiomatic surface.
- **C++ style: Google conventions, max C++23.** Already encoded in [`.clang-format`](.clang-format) (`BasedOnStyle: Google`, `Standard: c++23`). Run `clang-format`; do not use language features past C++23.
- **Smart pointers first, manual pointers later — in separate PRs.** Write the initial bridge with RAII / smart pointers (`std::unique_ptr`, `std::shared_ptr`) so ownership is obviously correct, and land that. If profiling later shows a smart-pointer is a real cost on a hot path, move it to a manual / raw pointer **in a follow-up PR** dedicated to that optimization, with the measurement that justifies it. Correctness first, optimization second, never mixed in one PR.

## Out of scope

- Windowing (companion [platform-stack adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter)).
- Frame graph / render passes / materials (consumer code).
- Adding a lib that isn't Vulkan-version-coupled — that belongs *outside* this bundle (e.g. SPIRV-Reflect is a consumer-side `@cImport`).

## Licensing & legal

- Contributions are licensed under this repo's **MIT** license. By submitting a PR you agree to MIT. **No CLA required.**
- **No GPL / LGPL / AGPL dependencies.** Bundled libs stay MIT / Apache-2.0 / BSD only.

## Dev setup

- **Zig 0.16+**; `zig build`, `zig build test` (contract suite), `zig build test-tdd` (red→green TDD suite).
- Lint: `zig fmt --check .` + `clang-format --dry-run -Werror` on `src/c`. CI runs these.

## Commits & PRs

- **Conventional Commits**, atomic, subject ≤ 72 chars.
- Larger work (adding to the stack, an API change): **open an issue first.**
- New functionality should add a validation app or a test (see [`docs/validation-apps.md`](docs/validation-apps.md)).
