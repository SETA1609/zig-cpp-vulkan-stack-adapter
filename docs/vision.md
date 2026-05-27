# Vision — zig-cpp-vulkan-stack-adapter

> One Zig dependency that delivers the **whole Vulkan stack, version-coherent** — vulkan-zig + volk + VMA + shaderc moving together — surfaced as idiomatic Zig, never a raw C ABI.

## The north star

A consumer adds **one** `build.zig.zon` entry and gets typed Vulkan bindings, a GPU memory allocator, a loader, a shader compiler, and per-OS surface creators — all pinned to versions known to agree. The bundling exists to make that agreement **atomic**: bump the library, and all four move as one. No more "VMA expects a Vulkan signature vulkan-zig didn't generate."

## Standalone — no windowing dependency

Surface creators take **raw OS primitives**, not a windowing type. So this library is usable with any window source — the companion [platform-stack adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter), SDL directly, raw X11, or none at all (headless / offscreen). Enforced by the `nm` check in [`validation-apps.md`](validation-apps.md): a headless binary shows zero `SDL_*` symbols.

## A clean Vulkan target — including for migrations

Because the surface side is decoupled and the stack is a single dependency, this library is a low-friction **Vulkan target** for any renderer — including one being migrated from OpenGL incrementally (build Vulkan paths against it while the GL renderer keeps shipping, flip when ready). The job here is to make "adopt Vulkan" cost one dependency, not four entangled ones.

## Non-vision

- Windowing / input — companion [platform-stack adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter).
- Frame graph, render passes, materials — consumer code.
- Metal / D3D backends — deferred (SPIRV-Cross, later).

## Origin

Built for and used by the [zVoxRealms](https://github.com/SETA1609/zigVoxelWorlds) engine, but designed to stand alone. See [`mission.md`](mission.md) for the concrete commitments and [`ROADMAP.md`](ROADMAP.md) for the version sequence.
