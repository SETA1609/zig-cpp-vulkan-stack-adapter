# zig-cpp-vulkan-adapter

A thin `extern "C"` Zig + C/C++ adapter for **Vulkan + VMA** (Vulkan Memory Allocator). Designed to be consumed by [zVoxRealms](https://github.com/SETA1609/zigVoxelWorlds) as a standalone dependency via `build.zig.zon`, but usable in any Zig project that wants Vulkan with idiomatic Zig types on top.

**License:** [MIT](LICENSE)
**Status:** Phase 0 (Foundation) — currently a hello-world stub. Real Vulkan + VMA wrapping starts at zVoxRealms Phase 1.

## Why this exists

zVoxRealms wraps every C++ vendor library behind a stable `extern "C"` adapter sub-repo per its [external-libs policy](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/external-libs.md). Vulkan-Headers + VMA is the first such adapter. The pattern:

- This repo builds the C/C++ as a static lib via `build.zig`
- Exposes a thin `extern "C"` header (`adapter.h`)
- A Zig module (`adapter.zig`) gives idiomatic Zig types on top
- zVoxRealms (or any consumer) pulls this in via `build.zig.zon`

This decoupling means the adapter can evolve independently and be reused by other Zig projects.

## Current state

The repo currently contains a Zig + C + C++ hello-world stub inherited from the build template, plus:

- `LICENSE` — MIT
- `.clang-format` — Google style + project tweaks (matches zVoxRealms root config; see [cpp-style.md](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/cpp-style.md))

Real Vulkan + VMA wrapping has not started yet. Track progress at [zVoxRealms ROADMAP § Phase 1](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/ROADMAP.md).

## Planned layout (target — not yet on disk)

```text
.
├── LICENSE
├── README.md
├── .clang-format
├── build.zig
├── build.zig.zon
└── src/
    ├── adapter.h         # extern "C" surface (the stable ABI)
    ├── adapter.cpp       # C++ → C ABI bridge (VMA, device, swapchain helpers)
    └── adapter.zig       # idiomatic Zig wrapper on top of the C ABI
└── vendor/
    ├── Vulkan-Headers/   # git submodule (Apache-2.0)
    └── VMA/              # git submodule (MIT)
```

## Build (current stub)

Requires [Zig 0.16+](https://ziglang.org/download/). No external C/C++ toolchain needed — Zig ships LLVM/Clang.

```bash
zig build              # build the stub binary
zig build run          # build + run
```

The compiled stub lives at `zig-out/bin/demo` and prints hello messages from Zig, C, and C++. Once Phase 1 starts, this becomes a static library, not an executable.

## C++ conventions

C++ code follows [zVoxRealms cpp-style.md](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/cpp-style.md): Google C++ Style Guide as baseline + project deviations. Hard rule: every `extern "C"` boundary function is `noexcept` and catches all exceptions before they cross the C ABI.

## Contributing

This adapter is part of zVoxRealms's [learning project](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/guard.md). Outside contributions aren't open until the Vulkan + VMA wrapping is real — likely once zVoxRealms Phase 2 (module system) lands. Doc PRs and link-rot reports welcome.

For now, see [zVoxRealms CONTRIBUTING.md](https://github.com/SETA1609/zigVoxelWorlds/blob/main/CONTRIBUTING.md) for the umbrella project's contribution policy.

## Contact

Through GitHub:

- **Maintainer:** [@SETA1609](https://github.com/SETA1609)
- **Issues / Discussions:** this repo (once open) or the parent [zigVoxelWorlds](https://github.com/SETA1609/zigVoxelWorlds)
- **Security:** [GitHub Security Advisory on zigVoxelWorlds](https://github.com/SETA1609/zigVoxelWorlds/security/advisories)
