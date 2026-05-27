# Contributing — zig-cpp-vulkan-stack-adapter

Thanks for your interest! This is a standalone, single-maintainer Zig library. Please read this before opening a PR.

## What this library is

A **version-coherent** Vulkan stack — vulkan-zig + volk + VMA + shaderc bundled in one repo — surfaced as idiomatic Zig. See [`docs/vision.md`](../docs/vision.md) and [`docs/mission.md`](../docs/mission.md).

## Maintainer stance

- Code contributions are most useful **once the real wrapping has landed** (the `vk` re-export + the C++ bridges). Until then, **docs / link-rot / build-config PRs are welcome.**
- Validated on **Linux + Windows** first; macOS / Metal is deferred.

## The version-coherence rule — the whole point of this repo

VMA's headers, vulkan-zig's generated bindings, and shaderc's SPIR-V target **must move together**. Therefore:

- **Never bump one bundled lib in isolation.** A PR touching any of vulkan-zig / volk / VMA / shaderc versions must bump them as a coherent set and re-run the validation apps.
- One `build.zig.zon` pins all four. If a bump breaks a signature, that's the system working — fix the *set*, don't paper over one lib.

## C++ bridge discipline (hard rules)

- Every `extern "C"` boundary function (VMA, shaderc bridges) is **`noexcept`** and **catches all exceptions before they cross the C ABI**.
- C++ follows the Google C++ Style baseline — run `clang-format`.
- No C++ type (class / template / `std::*`) crosses the boundary — the Zig wrappers (`src/vma.zig`, `src/shaderc.zig`) own the idiomatic surface.

## Out of scope

- Windowing (companion [platform-stack adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter)).
- Frame graph / render passes / materials (consumer code).
- Adding a lib that isn't Vulkan-version-coupled — that belongs *outside* this bundle (e.g. SPIRV-Reflect is a consumer-side `@cImport`).

## Licensing & legal

- Contributions are licensed under this repo's **MIT** license. By submitting a PR you agree to MIT. **No CLA required.**
- **No GPL / LGPL / AGPL dependencies.** Bundled libs stay MIT / Apache-2.0 / BSD only.

## Dev setup

- **Zig 0.16+**; `zig build`, `zig build test`.
- Lint: `zig fmt --check .` + `clang-format --dry-run -Werror` on `src/c`. CI runs these.

## Commits & PRs

- **Conventional Commits**, atomic, subject ≤ 72 chars.
- Larger work (adding to the stack, an API change): **open an issue first.**
- New functionality should add a validation app or a test (see [`docs/validation-apps.md`](../docs/validation-apps.md)).
