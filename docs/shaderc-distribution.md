# shaderc distribution — how to give consumers zero setup

> shaderc (= glslang + SPIRV-Tools) is a large C++ codebase. The question this
> doc answers: **how does a downstream consumer get `vk_stack.shaderc.compile`
> without installing anything by hand?** Goal: a plain `zig build` in the
> consumer's project works on Linux/macOS/Windows, no SDK install, no env vars.
>
> Guiding idea: move the setup burden **off the consumer and onto this library**
> (fetch/build it for them), or **remove the need** (don't require shaderc at
> runtime at all). Everything that asks the consumer to install an SDK fails the
> goal.

## The options

### 0. System / SDK auto-detect *(baseline — NOT zero-setup)*
`build.zig` finds shaderc via `VULKAN_SDK` / system paths and links it; gated off
when absent. **This is what we have wired today.** It's fine for *us* (we have
the SDK) but every consumer must install the Vulkan SDK first → fails the goal.
Keep it as a fast path / override, not the answer.

### A. Don't require runtime shaderc — ship/precompile SPIR-V *(zero-setup by removal)*
Most engines **ship precompiled `.spv`**, not a GLSL compiler. Make `shaderc`
optional and document the `@embedFile` path; offer a **build-step helper** that
precompiles `*.glsl → *.spv` at build time *only on machines that have a
compiler*, with the `.spv` checked in so consumers without one still build.

```zig
const frag align(4) = @embedFile("tri.frag.spv").*;
// vkCreateShaderModule(.{ .code_size = frag.len, .p_code = @ptrCast(&frag) })
```

- **Zero-setup:** ✅ (nothing to install — there's no shaderc at runtime)
- **Reproducible:** ✅  **Cross-compile:** ✅  **Build cost:** none
- **Loses:** runtime GLSL→SPIR-V (hot-reload, user/mod-supplied shaders). For a
  shipped game that's usually fine; for a live shader playground it isn't.
- **Effort:** ~0. **This is the pragmatic default and unblocks the whole ladder.**

### B. Reuse an existing Zig package — ✅ **ADOPTED** (`tiawl/shaderc.zig`)
A maintained `build.zig.zon` package, [`tiawl/shaderc.zig`](https://github.com/tiawl/shaderc.zig),
builds shaderc + glslang + SPIRV-Tools **from source via the Zig build system**
(no system SDK, cross-compiles), supports Zig 0.16.0, and tracks upstream via a
daily cron. We depend on it as a **lazy** dep enabled by **`-Dshaderc`**:

```sh
zig build -Dshaderc           # fetches + builds shaderc from source, runtime GLSL→SPIR-V on
zig build                     # default: shaderc off, nothing extra fetched (embed .spv)
```

Pinned at `zig-0.16.0` in `build.zig.zon` (reproducible). Effectively **Option C
done for us**: zero consumer setup *and* runtime compilation, without us porting
glslang's CMake build. Cost: a slow first `-Dshaderc` build (compiles glslang).

### C. Vendor + build from source via `build.zig.zon` *(zero-setup, high author effort)*
Add shaderc + glslang + SPIRV-Tools + SPIRV-Headers as **pinned `build.zig.zon`
dependencies** and compile them in our `build.zig`. The consumer just runs
`zig build`; everything is fetched and compiled for their target.

- **Zero-setup:** ✅  **Reproducible:** ✅ (pinned)  **Cross-compile:** ✅
  (zig cc builds the C++ for any target — a real Zig superpower)
- **Cost:** **high, and ours** — porting glslang's + SPIRV-Tools' CMake builds
  (generated headers, Python grammar codegen) to `build.zig` is the single
  biggest build task in the project; multi-session, and slow first builds
  (minutes to compile glslang).
- The "correct" long-term end state, but disproportionate for an optional feature
  right now. Revisit at v1.0.

### D. Ship prebuilt per-platform binaries as **lazy** deps *(zero-setup, moderate maintenance)*
We build `libshaderc_combined` once per target (linux-x64, windows-x64,
macos-arm64/x64), host them (GitHub releases), and reference them as
**lazy** `build.zig.zon` deps keyed by target. `zig build` downloads only the
prebuilt matching the consumer's target and links it.

- **Zero-setup:** ✅  **Build cost:** ~none (no glslang compile)  **Reproducible:** ✅ (pinned hashes)
- **Cross-compile:** ⚠️ only to targets we shipped a prebuilt for.
- **Cost:** **ours, ongoing** — rebuild/host/pin per shaderc bump, per platform.
- **C++ runtime:** prefer **shared** prebuilts (C++ encapsulated behind the C ABI)
  to dodge cross-toolchain C++ ABI mixing (esp. MSVC on Windows).

## Comparison

| Option | Consumer setup | Author effort | Reproducible | Cross-compile | Runtime GLSL | Build time |
| --- | --- | --- | --- | --- | --- | --- |
| 0 — SDK detect | **install SDK** ❌ | low | ❌ | native only | ✅ | fast |
| A — precompiled SPIR-V | **none** ✅ | ~0 | ✅ | ✅ | ❌ | none |
| B — existing Zig pkg | **none** ✅ | low* | inherits pkg | ✅ | ✅ | slow first build |
| C — vendor from source | **none** ✅ | **high** | ✅ | ✅ | ✅ | slow first build |
| D — prebuilt lazy deps | **none** ✅ | moderate (ongoing) | ✅ | shipped targets | ✅ | fast |

\* *if a good package exists.*

## Cross-cutting notes

- **Lazy dependencies** (`b.lazyDependency`): for B/C/D, only fetch shaderc when
  the consumer actually enables it — projects that embed `.spv` pay nothing.
- **The C ABI is the friend.** shaderc's public API is C, so however we link it
  (shared/static/source), Zig only touches the C boundary — no C++ ABI exposed.
  For *prebuilts*, prefer **shared** so glslang's C++ runtime stays inside the
  `.so`/`.dll` and never mixes with Zig's toolchain.
- **Self-contained vs runtime dep:** static (`combined`) → no runtime dependency
  but C++-runtime-sensitive across toolchains; shared → a `.so`/`.dll` to bundle
  but a clean boundary. Source/lazy builds (C) give static + self-contained the
  cleanly, since zig compiles them with one toolchain.
- **Version coherence:** whatever path, shaderc's SPIR-V target must stay
  coherent with the pinned `vk.xml` — pin it (B/C/D pin; option 0 floats).

## What we shipped

**A + B together — no consumer setup either way:**

- **Default (`zig build`) → Option A.** `shaderc` is off; nothing extra is
  fetched. Use `shaderc.available` to branch and embed precompiled SPIR-V
  (`@embedFile`). This is what CI and most consumers use.
- **`zig build -Dshaderc` → Option B.** The lazy `tiawl/shaderc.zig` dep is
  fetched and built from source (glslang etc.), turning on runtime GLSL→SPIR-V.
  Still zero manual setup — the build system does it.

Neither path asks the consumer to install an SDK (Option 0 was rejected for that
reason). Options C (vendor the whole tree ourselves) and D (ship prebuilts)
remain on the table for v1.0 if we ever want to drop the dependency on
`tiawl/shaderc.zig` or shave the first-build time — but they're not needed now.

**Bottom line:** the consumer never installs anything. Default to *not needing
shaderc at runtime* (A); opt into runtime compilation with `-Dshaderc`, which
the build system fetches + builds for you (B). The SDK is never required.
