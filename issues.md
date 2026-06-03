# Candidate issues — vulkan-stack adapter

Each section is a standalone, real-world task: explore the codebase, implement
the behavior, and make it pass programmatically. The idiomatic Zig surfaces are
`src/shaderc.zig`, `src/vma.zig`, `src/volk.zig`, `src/root.zig`; the only
C++↔Zig boundary is the VMA bridge in `src/c/vma_bridge.{h,cpp}`. shaderc is
compiled in only under `-Dshaderc` (its tests gate on `shaderc.available`); the
device-dependent VMA/volk tests run against a Vulkan ICD (lavapipe in CI). TDD
suite: `src/tests/tdd/`.

---

## Issue 1 — Add a GLSL preprocess-only pass to `shaderc`

Tooling (shader hot-reload inspectors, `#include`-graph tools) needs the
**preprocessed GLSL text** — macros expanded and `#include`s resolved — without
compiling to SPIR-V. Add it next to `compile` in `src/shaderc.zig`:

```zig
/// Run only the preprocessor; returns the expanded GLSL text (allocator-owned).
pub fn preprocess(
    allocator: std.mem.Allocator,
    source: []const u8,
    stage: Stage,
    options: CompileOptions,
    diagnostics: ?*Diagnostics,
) Error![]u8;
```

Back it with `shaderc_compile_into_preprocessed_text` (mirror how `compile` is
wired in the `backend` struct).

**Requirements** (gated on `shaderc.available`; run `zig build test-tdd -Dshaderc`):

1. With `options.macros = &.{.{ .name = "N", .value = "4" }}`, preprocessing
   `#define`-using source yields text in which `N` has been replaced by `4`.
2. `options.includer` is honored: a source with `#include "x.glsl"` produces
   text that **contains the included file's contents**.
3. An `#include` the includer can't resolve returns `error.ShaderCompilationFailed`
   and fills `diagnostics.message` (non-empty); a successful preprocess leaves a
   passed `Diagnostics` untouched (`message.len == 0`).
4. The result is the preprocessed **text** (`[]u8`), owned by `allocator`, with
   length exactly the preprocessed source length (no stray trailing NUL).

**Notes.** The easy miss is reusing only part of `compile`'s option setup —
`preprocess` must install the **same macro definitions *and* include callbacks**,
or requirements 1–2 fail. The result is bytes via
`shaderc_result_get_bytes`/`_get_length`, not SPIR-V words.

---

## Issue 2 — Add a host→allocation upload helper to VMA

Every consumer hand-rolls "map, memcpy, flush, unmap" to push vertex/uniform
data into a host-visible allocation. Add the helper to `src/vma.zig`:

```zig
/// Copy `bytes` into `allocation` starting at `offset`, making the write
/// visible to the device. Errors (does not panic) if the allocation isn't
/// host-visible.
pub fn copyMemoryToAllocation(
    allocator: *Allocator,
    allocation: *Allocation,
    offset: u64,
    bytes: []const u8,
) Error!void;
```

**Requirements** (device test — `zig build test-tdd`, ICD/lavapipe present):

1. After `copyMemoryToAllocation(a, alloc, 0, data)` on a `cpu_to_gpu` buffer,
   mapping it reads back exactly `data`.
2. `offset` is honored: copying `len` bytes at `offset = 8` writes `[8, 8+len)`
   and leaves `[0, 8)` unchanged.
3. On a `gpu_only` (non-host-visible) allocation it returns
   `Error.MappingFailed` — **not a panic / not `unreachable`**.
4. The written range is flushed so non-coherent host memory is visible to the
   device (use `flushAllocation` on the written range, or the persistently
   `mapped` pointer from `getAllocationInfo`).

**Notes.** Don't assume the allocation is mappable — requirement 3 is the easy
miss (`try vma.mapMemory(...)` will surface the error union; propagate it). Flush
the range you wrote, not the whole allocation, when `offset > 0`.

---

## Issue 3 — `#include` resolution can recurse forever

The include resolver in `src/shaderc.zig` (`includeResolve`) ignores the
`include_depth` argument shaderc passes it (`_ = include_depth;`). A source whose
includes form a cycle (`a.glsl` includes `b.glsl`, `b.glsl` includes `a.glsl`)
recurses without bound. Guard it.

**Requirements** (gated on `shaderc.available`; `zig build test-tdd -Dshaderc`):

1. Compiling a source whose includer produces a **cyclic** include chain returns
   `error.ShaderCompilationFailed` with a non-empty `diagnostics.message` that
   references the include depth — and **terminates** (no hang, no stack
   overflow).
2. A **non-cyclic** include nested several levels deep (below the limit) still
   resolves and compiles successfully — the guard must not break legitimate
   nesting.

**Notes.** Use the `include_depth` parameter: past a sane cap (e.g. 32) return a
*failure* `shaderc_include_result` (empty `source_name`, with the error text in
`content`) rather than calling the user's resolver again. The off-by-one at the
limit is the easy miss — a file that includes exactly `limit` levels deep must
still succeed.
