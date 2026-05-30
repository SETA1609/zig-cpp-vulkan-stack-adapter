# Security Policy — zig-cpp-vulkan-stack-adapter

## Supported versions

Pre-1.0, single-maintainer library. Security fixes land on the **latest tag + `main`** only.

| Version | Supported |
| --- | --- |
| latest tag / `main` | ✅ |
| older tags | ❌ (upgrade to latest) |

## Reporting a vulnerability

**Please do not open a public issue.** Report privately via a **[GitHub Security Advisory on this repo](https://github.com/SETA1609/zig-cpp-vulkan-stack-adapter/security/advisories/new)** (or, if you prefer, on the [parent project](https://github.com/SETA1609/zigVoxelWorlds/security/advisories/new) that maintains it). Include the affected commit, platform, reproduction, and impact. Best-effort response — small project.

## Scope / threat model

This library wraps a Vulkan stack. Realistic surface:

- **Shader compilation (shaderc):** if a consumer compiles **untrusted GLSL** at runtime (e.g. user- or mod-supplied shaders), malformed input could crash or misbehave inside shaderc / glslang. Treat runtime compilation of untrusted shaders as a risk in the *consumer*; report wrapper-level memory issues here.
- **C++ ↔ C ABI bridges (VMA, shaderc):** memory safety across the FFI boundary — lifetimes, and buffer sizes passed as pointer + length — is this library's own surface.
- **GPU memory (VMA):** allocation-size handling.

## Upstream dependencies

The heavy lifting is upstream: [vulkan-zig](https://github.com/Snektron/vulkan-zig), [volk](https://github.com/zeux/volk), [VMA](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator), [shaderc](https://github.com/google/shaderc) / glslang. Vulnerabilities **inside** those libs should be reported to their projects; this library then bumps the coherent version set. Report here only issues in **this library's own bridges / wrappers**.

## Out of scope

Issues requiring an already-compromised process, or living in a consumer's renderer / app code, are not vulnerabilities in this library.
