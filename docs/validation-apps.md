# Validation apps — zig-cpp-vulkan-stack-adapter

> Small standalone apps that consume this library via `build.zig.zon` **the way a real consumer will** — to exercise the public Zig API (`vk` re-export, volk, VMA, shaderc, the per-OS surface creators). Each is a throwaway project in its own directory, not part of the library.
>
> These complement testing the library inside a larger host application: a C++ host using its own renderer **can't** exercise *this library's* idiomatic Zig wrappers (`vk_stack.vma`, `vk_stack.shaderc`) — these mini-apps are the only thing that does.
>
> Version gates: [`ROADMAP.md`](ROADMAP.md). Milestone plan: [`sprint.md`](sprint.md).

## Completion checklist

Mark `[x]` only when the app **builds and runs correctly** — not merely compiles. `[~]` = in progress.

- [ ] **Headless triangle → PPM** — offscreen render, no window, dump raw pixels · *v0.3.0 + v0.4.0 (no surface, no windowing lib)*
- [ ] **`nm` decoupling check** — headless-triangle binary shows **zero `SDL_*` symbols** · *v0.3.0+*
- [ ] **Reactive clear-color** — swapchain clear/present, color from input (pair with a windowing lib) · *v0.2.0 + a windowing lib*
- [ ] **Snake** — VMA quad buffer + ortho projection + draw loop · *v0.3.0 + a windowing lib*
- [ ] **Breakout** — many quads → instancing/batching throughput through VMA · *v0.3.0 + a windowing lib*
- [ ] **Conway's Life** — fullscreen grid via a real fragment/compute shader · *v0.4.0 + a windowing lib*

## The ladder — what each app validates

| App | Needs | Validates | Windowing? |
| --- | --- | --- | --- |
| **Headless triangle → PPM** | v0.3.0 + v0.4.0 | Proves the library is **fully standalone**: instance (no surface) → device → offscreen framebuffer → VMA buffer → shaderc shader → readback → PPM. No windowing dependency at all. | none |
| **Reactive clear-color** | + a windowing lib | `vk` instance + a per-OS surface creator (fed a native handle from your windowing layer) → swapchain → per-frame clear → present; swapchain-recreate on resize. The key proof the surface handoff works end to end. | yes |
| **Snake** | + a windowing lib | VMA vertex/index buffer (one quad), push-constant for per-cell color/position, ortho projection, the full present loop. (precompiled SPIR-V is fine — defer shaderc) | yes |
| **Breakout** | + a windowing lib | Many quads at once → instancing / batching throughput through VMA. Catches allocation-churn or descriptor issues a single quad won't. | yes |
| **Conway's Life** | + a windowing lib | A genuine fragment/compute shader + large dynamic buffer churn. The best shaderc stress test (needs v0.4.0). | yes |

> Tests stay 2D (quads + ortho) on purpose — they exercise *this library's* allocation / shader / surface paths, not a full 3D renderer.

## Required decoupling check (`nm`)

This library must drag **no windowing** code. After building the **Headless triangle**:

```sh
nm <headless-triangle-binary> | grep -i 'SDL_\|x11\|wayland\|glfw'   # must print NOTHING
```

A non-empty result means a windowing symbol leaked across the boundary — fix it now, while it's a ~200-line app.

## Notes

- Apps depend on this library (and, for paired apps, a windowing layer such as the companion [platform-stack adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter)) via pinned `build.zig.zon` entries — the same pattern a real consumer uses.
- Every `extern "C"` bridge crossed here (VMA, shaderc) must stay `noexcept`.
