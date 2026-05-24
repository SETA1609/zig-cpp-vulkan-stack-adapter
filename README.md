# zig-cpp-vulkan-stack-adapter

A meta-package adapter exposing a **stable Zig API** for the Vulkan stack — Vulkan bindings, GPU memory allocator, loader, and shader compiler — all version-pinned together in one sub-repo to avoid drift between them.

**License:** [MIT](LICENSE)
**Status:** Phase 0 (Foundation) — currently a hello-world stub. Real Vulkan + VMA wrapping starts at [zVoxRealms](https://github.com/SETA1609/zigVoxelWorlds) Phase 1.

---

## What it is

A standalone Zig package that consumers (engines, games, tools) import as a single dependency to get the full Vulkan stack with idiomatic Zig types. Bundled in this single sub-repo:

- **Public Zig API** (`src/root.zig`) — re-exports `vk` (from vulkan-zig), `vma`, `volk`, `shaderc` as Zig namespaces
- **One Zig-native binding** (vulkan-zig, generated from `vk.xml`) re-exported as-is
- **Three C++ libraries** wrapped behind `extern "C"` bridges and surfaced as idiomatic Zig

The point of bundling is **version coherence**: VMA's headers embed assumptions about specific Vulkan-1.x function signatures, vulkan-zig's generated bindings come from a specific `vk.xml` snapshot, and shaderc emits SPIR-V targeting a specific Vulkan version. All three must move together or you get cryptic runtime errors. One sub-repo's `build.zig.zon` enforces atomic version coherence.

This is the first meta-package adapter under zVoxRealms. The sibling is [`zig-cpp-platform-stack-adapter`](https://github.com/SETA1609/zig-cpp-platform-stack-adapter). Both follow the `zig-cpp-<name>-stack-adapter` naming convention.

## What it's needed for

zVoxRealms ([`docs/external-libs-catalog.md` § 3 Vulkan-stack](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/external-libs-catalog.md)) needs a Vulkan stack that:

1. **Stays version-coherent across vulkan-zig + VMA + volk + shaderc.** Bumping any one in isolation breaks the others; bundling makes the version-pin atomic per sub-repo release
2. **Exposes vulkan-zig's idiomatic Zig API without a C-ABI tax.** vulkan-zig is already Zig-native — the adapter re-exports its `vk` namespace as-is, no extern "C" wrapping. Engine code gets full error sets, typed enums, and comptime dispatch tables
3. **Wraps the C++ libs (VMA / shaderc) behind extern "C" bridges and surfaces them as idiomatic Zig.** Per [`docs/external-libs-catalog.md` § The two C ABIs](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/external-libs-catalog.md), engine source never sees the C ABI directly — only the Zig wrappers
4. **Reduces engine top-level deps from four entries to one.** Engine's `build.zig.zon` lists this adapter; the four bundled libs are internal
5. **Provides a single `createBuffer` / `compileShader` / `loadVulkan` entry point per concern.** Idiomatic Zig types throughout — no manual sType-chaining for VMA buffer creation, no FFI ceremony for shader compilation
6. **Tree-shakes per export target.** Builds for Linux exclude Windows/Apple/Android stubs; verifiable with `nm libzvox-runtime.so`
7. **Provides cross-platform surface creation without any cross-adapter dependency.** Exposes `createX11Surface` / `createWaylandSurface` / `createWin32Surface` / `createAndroidSurface` — each takes only raw OS primitives (pointers + integers), no shared types imported from any windowing adapter. Each calls the matching `vkCreate*SurfaceKHR` from its `VK_KHR_*_surface` extension. Engine pairs these with the matching per-OS getter from [`zig-cpp-platform-stack-adapter`](https://github.com/SETA1609/zig-cpp-platform-stack-adapter) in a small `src/render/surface.zig` helper. Pattern matches Vulkan's own design (Vulkan has no unified "native surface" extension — every platform gets its own)

Full design rationale: [`docs/external-libs-catalog.md` § Note on the Vulkan-stack meta-package](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/external-libs-catalog.md).

## Which libraries this adapter will use and adapt

These land here progressively as the adapter's roadmap advances. Each is wrapped (or re-exported) behind the same stable Zig API.

### Bundled libs (v1.0 lineup)

| Library | License | Role | How it surfaces in this adapter |
| --- | --- | --- | --- |
| [**vulkan-zig**](https://github.com/Snektron/vulkan-zig) (Snektron) | MIT | Zig-native Vulkan bindings, generated from `vk.xml` | Imported via `build.zig.zon`; re-exported as-is from `src/root.zig` as `pub const vk = @import("vulkan");`. No C-ABI tax — engine gets typed enums, error sets, and comptime dispatch tables directly |
| [**VMA**](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator) (AMD GPUOpen) | MIT | GPU memory allocator — handles buffer/image creation, sub-allocation, defragmentation | Vendored under `vendor/VMA/`; built as a C++ static lib; `extern "C"` bridge in `src/c/vma_bridge.cpp`; idiomatic Zig wrapper at `src/vma.zig` |
| [**volk**](https://github.com/zeux/volk) | MIT | Vulkan loader / function-pointer table | Vendored under `vendor/volk/`; small C surface; thin Zig wrapper at `src/volk.zig` |
| [**shaderc**](https://github.com/google/shaderc) (Google, over [glslang](https://github.com/KhronosGroup/glslang) BSD-3) | Apache-2.0 | GLSL → SPIR-V compiler | Vendored under `vendor/shaderc/`; built as a C++ static lib; `extern "C"` bridge in `src/c/shaderc_bridge.cpp`; idiomatic Zig wrapper at `src/shaderc.zig` |

### Engine-side example (what consumers see)

```zig
const vk_stack = @import("vulkan_stack");
const vk       = vk_stack.vk;        // re-exported vulkan-zig — full typed API
const vma      = vk_stack.vma;       // typed Zig wrapper over VMA
const volk     = vk_stack.volk;      // loader
const shaderc  = vk_stack.shaderc;   // shader compiler

try cb.beginRenderPass(&info, .@"inline");
const buf = try vma.createBuffer(allocator, &buf_info, &alloc_info);
const spv = try shaderc.compile(allocator, source, .vertex);
```

### Deliberately NOT in this adapter

| Item | Where it lives | Why excluded |
| --- | --- | --- |
| **GLFW** / windowing | Sibling [`zig-cpp-platform-stack-adapter`](https://github.com/SETA1609/zig-cpp-platform-stack-adapter) | Windowing is orthogonal to Vulkan. Keeping platform separate means the platform adapter can swap GLFW → native without touching the Vulkan stack |
| **SPIRV-Reflect** | Engine-side `@cImport` (§2 in the catalog) | Pure C, not Vulkan-version-coupled (it walks SPIR-V binaries against the SPIR-V spec). Sits outside the version-coherence boundary |
| **SPIRV-Cross** | Deferred | Used for SPIR-V → HLSL/MSL transpilation, only needed for Metal/D3D fallback (post-v1.0 macOS/Windows-legacy support). Not bundled until then |
| **Post-processing / material pipeline / frame graph** | Engine code in `src/render/` | Not third-party libs — these are engine concerns built on top of this adapter |

## Future libs under consideration (v1.x+)

| Library | License | When we'd adopt |
| --- | --- | --- |
| [**slang**](https://github.com/shader-slang/slang) (NVIDIA) | Apache-2.0 + LLVM-Exception | If shader authoring outgrows GLSL — modules, generics, autodiff. Adopt as an alternative to shaderc, not in addition |
| [**FidelityFX SDK**](https://github.com/GPUOpen-Effects/FidelityFX-SDK) (AMD) | MIT | Optional upscaling / post-FX modules — only if a target game needs them. Stays out of the version-coherence bundle since each FX is independent |
| **Vulkan-Headers** (Khronos) | Apache-2.0 | If vulkan-zig stops being adequate (unlikely) — we'd switch to `@cImport`-ing Vulkan-Headers and lose the typed Zig wrappers. Documented as a fallback, not a goal |
| [**spirv-cross**](https://github.com/KhronosGroup/SPIRV-Cross) | Apache-2.0 | When cross-platform Metal/D3D rendering becomes a real target (deferred per `mission.md`) |

---

## Current state — Phase 0 hello-world

The repo currently contains a Zig + C + C++ hello-world stub inherited from the build template, plus:

- `LICENSE` — MIT
- `.clang-format` — Google C++ baseline + zVoxRealms tweaks (matches root project's [`docs/cpp-style.md`](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/cpp-style.md))
- `build.zig.zon` — package manifest

Real Vulkan + VMA wrapping has not started yet. Track progress at [zVoxRealms ROADMAP § Phase 1](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/ROADMAP.md).

## Planned layout (target — not yet on disk)

```text
.
├── LICENSE
├── README.md
├── .clang-format
├── build.zig
├── build.zig.zon
├── src/
│   ├── root.zig                # public API — re-exports vk + vma + volk + shaderc
│   ├── vma.zig                 # idiomatic Zig wrapper over the VMA C bridge
│   ├── volk.zig                # idiomatic Zig wrapper over volk
│   ├── shaderc.zig             # idiomatic Zig wrapper over the shaderc C bridge
│   └── c/
│       ├── vma_bridge.h        # extern "C" surface for VMA
│       ├── vma_bridge.cpp      # C++ → C ABI bridge
│       ├── shaderc_bridge.h    # extern "C" surface for shaderc
│       └── shaderc_bridge.cpp
└── vendor/
    ├── VMA/                    # git submodule (MIT)
    ├── volk/                   # git submodule (MIT)
    └── shaderc/                # git submodule (Apache-2.0, wraps glslang BSD-3)
```

`vendor/*` directories are **vendored dependencies** of the adapter, not sub-libraries. Each is compiled by this sub-repo's `build.zig` into static libs that the Zig wrappers link against.

## Build (current stub)

Requires [Zig 0.16+](https://ziglang.org/download/). No external C/C++ toolchain needed — Zig ships LLVM/Clang.

```bash
zig build              # build the stub binary
zig build run          # build + run
```

The compiled stub lives at `zig-out/bin/demo` and prints hello messages from Zig, C, and C++. Once Phase 1 starts, this becomes a static library, not an executable.

## Consuming this adapter

When real wrapping lands, consumers will use:

```zig
// In your build.zig.zon
.dependencies = .{
    .vulkan_stack_adapter = .{
        .url = "git+https://github.com/SETA1609/zig-cpp-vulkan-stack-adapter.git#<tag>",
        .hash = "...",
    },
},
```

```zig
// In your Zig code
const vk_stack = @import("vulkan_stack");
const vk       = vk_stack.vk;
const vma      = vk_stack.vma;
```

## C++ conventions

C++ code follows [zVoxRealms `docs/cpp-style.md`](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/cpp-style.md): Google C++ Style Guide as baseline + project deviations. Hard rule: every `extern "C"` boundary function is `noexcept` and catches all exceptions before they cross the C ABI.

## Cross-reference

- Parent project: [zVoxRealms](https://github.com/SETA1609/zigVoxelWorlds)
- Catalog entry: [`docs/external-libs-catalog.md` § 3 Vulkan-stack](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/external-libs-catalog.md)
- Sibling adapter: [zig-cpp-platform-stack-adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter)
- Licensing policy: [`docs/licensing.md`](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/licensing.md)
- C++ style: [`docs/cpp-style.md`](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/cpp-style.md)

## Adapter pattern note — the two C ABIs

zVoxRealms has two distinct `extern "C"` surfaces and this adapter touches one of them:

1. **Internal adapter bridge** (this repo, `src/c/*_bridge.cpp`) — C++ libs (VMA, shaderc) need this because Zig's `@cImport` can't translate C++ classes/templates/mangled names. The Zig wrappers in `src/vma.zig`, `src/shaderc.zig` re-export idiomatic types over this bridge
2. **Public mod/script ABI** — a separate concern, lives in the parent project's `docs/specs/c-abi.md`. Not consumed by this adapter

Adapter authors care about (1). Mod authors care about (2). The two aren't the same surface.

## Contributing

This adapter is part of zVoxRealms's [learning project](https://github.com/SETA1609/zigVoxelWorlds/blob/main/docs/guard.md). Outside contributions aren't open until the Vulkan + VMA wrapping is real — likely once zVoxRealms Phase 2 (module system) lands. Doc PRs and link-rot reports welcome.

For now, see [zVoxRealms CONTRIBUTING.md](https://github.com/SETA1609/zigVoxelWorlds/blob/main/CONTRIBUTING.md) for the umbrella project's contribution policy.

## Contact

Through GitHub:

- **Maintainer:** [@SETA1609](https://github.com/SETA1609)
- **Issues / Discussions:** this repo (once open) or the parent [zigVoxelWorlds](https://github.com/SETA1609/zigVoxelWorlds)
- **Security:** [GitHub Security Advisory on zigVoxelWorlds](https://github.com/SETA1609/zigVoxelWorlds/security/advisories)
