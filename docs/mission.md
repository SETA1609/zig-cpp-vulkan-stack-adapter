# Mission — zig-cpp-vulkan-stack-adapter

> The concrete commitments behind the [vision](vision.md).

## What we will build

1. **Re-export vulkan-zig as-is** — `pub const vk = @import("vulkan")`. Typed enums, error sets, comptime dispatch tables. No C-ABI tax.

2. **Wrap the C++ libs behind `noexcept` `extern "C"` bridges, surfaced as idiomatic Zig** — `vk_stack.vma.createBuffer(...)`, `vk_stack.shaderc.compile(...)`. Every boundary function catches all exceptions before they cross the C ABI.

3. **volk loader** (`vk_stack.volk`) — pending the v0.2.0 review of whether vulkan-zig's own generated dispatch makes it redundant (see [`ROADMAP.md`](ROADMAP.md)).

4. **Per-OS surface creators** — `createX11Surface`/`createWaylandSurface`/`createWin32Surface`/`createAndroidSurface`, each taking raw OS primitives, **no windowing-library import**.

5. **Atomic version coherence** — one `build.zig.zon` pins all four bundled libs; a bump moves them together so signatures never drift.

6. **Per-target tree-shake** — a Linux build drags no Windows/Android surface code (`nm`-verified).

## Success criteria

- Every app in [`validation-apps.md`](validation-apps.md) builds and runs — including the **headless triangle** (proves standalone: instance → device → VMA → shaderc → readback, no window, no surface).
- The `nm` decoupling check passes: a headless binary shows zero `SDL_*` symbols.
- A version bump never produces a vulkan-zig / VMA / shaderc signature mismatch.

## Non-goals

Windowing (companion adapter) · the frame graph / material system (consumer code) · SPIR-V reflection (consumer-side `@cImport`) · Metal/D3D transpilation (deferred, SPIRV-Cross later).
