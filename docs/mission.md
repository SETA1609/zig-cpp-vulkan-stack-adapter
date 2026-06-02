# Mission — zig-cpp-vulkan-stack-adapter

> The concrete commitments behind the [vision](vision.md).

## What we will build

1. **Re-export vulkan-zig as-is** — `pub const vk = @import("vulkan")`. Typed enums, error sets, comptime dispatch tables. No C-ABI tax.

2. **Surface the native libs as idiomatic Zig.** VMA is header-only C++, so it sits behind a `noexcept` `extern "C"` bridge that catches all exceptions before they cross the C ABI — `vk_stack.vma.createBuffer(...)`. shaderc ships a C API, so it needs no bridge: a pure-Zig `@cImport` wrapper (`vk_stack.shaderc.compile(...)`), opt-in under `-Dshaderc`.

3. **volk loader** (`vk_stack.volk`) — resolved at v0.2.0: the loader *role* is reimplemented in **pure Zig** (`std.DynLib` opens `libvulkan`, resolves `vkGetInstanceProcAddr`) and feeds vulkan-zig's dispatch wrappers; `loadInstance`/`loadDevice` are no-ops (see [`ROADMAP.md`](ROADMAP.md)).

4. **Per-OS surface creators** — `createX11Surface`/`createWaylandSurface`/`createWin32Surface`/`createAndroidSurface`, each taking raw OS primitives, **no windowing-library import**.

5. **Atomic version coherence** — one `build.zig.zon` pins all four bundled libs; a bump moves them together so signatures never drift.

6. **Per-target tree-shake** — a Linux build drags no Windows/Android surface code (`nm`-verified).

## Success criteria

- Every app in [`validation-apps.md`](validation-apps.md) builds and runs — including the **headless triangle** (proves standalone: instance → device → VMA → shaderc → readback, no window, no surface).
- The `nm` decoupling check passes: a headless binary shows zero `SDL_*` symbols.
- A version bump never produces a vulkan-zig / VMA / shaderc signature mismatch.

## Non-goals

Windowing (companion adapter) · the frame graph / material system (consumer code) · SPIR-V reflection (consumer-side `@cImport`) · Metal/D3D transpilation (deferred, SPIRV-Cross later).
