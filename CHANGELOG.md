# Changelog

Last updated: 2026-10-28T23:28Z

Changes per issue, newest first. Each PR adds its entry and updates the timestamp above. Issue IDs prefixed `S0-` are from [project-new-world](https://github.com/SETA1609/project-new-world/tree/main/docs/stories), which uses this adapter as its `vk_stack` module. History before this file: `git log`.

## Unreleased

### S0-03 Port to Zig 0.17.0

Branch `s0-03-port-to-zig-0.17.0`.

- vulkan-zig `b496a6a` → `master` `91a3537` (2026-10-25), which targets 0.17. Its generated API changed: non-dispatchable handles use `.null` instead of `.null_handle`; `Instance`, `PhysicalDevice`, and `Device` are `*opaque {}` (optional `null`, `@intFromPtr`, `@ptrCast`); flag fields drop the `_bit` suffix (`.@"1_bit"` → `.@"1"`).
- shaderc: `-Dshaderc` now links the system shaderc library (`libshaderc-dev`, or the Vulkan SDK). The `tiawl/shaderc.zig` dependency is removed: it and its `spirv.zig`, `glslang.zig`, and `toolbox` 2.1.3 dependencies still target Zig 0.16, and 0.17 fetched it even without `-Dshaderc`, which broke every build. The default build needs no shaderc, as before.
- `@cImport` is removed in 0.17: `src/c/shaderc_c.h` is translated by `b.addTranslateC` into the `shaderc_c` module; without `-Dshaderc` an empty module stands in.
- std renames: `b.args` → `addPassthruArgs()`, enum `@typeInfo` `.fields` → `.field_names`/`.field_values`, `@intFromEnum`/`@enumFromInt` → `@backingInt`/`@fromBackingInt`.
- `minimum_zig_version`, the Dockerfile (with `libshaderc-dev` from universe), CI (Zig 0.17.0, `libshaderc-dev` in the shaderc and device-tests jobs), and the docs say 0.17.0. `docs/cheat_sheet.md` lists the port changes; `docs/shaderc-distribution.md` records the switch.
- Checked in the project-new-world Zig 0.17.0 container (lavapipe): `scripts/ci.sh check` passes; `zig build -Dshaderc` builds; `test-tdd -Dshaderc` passes 54 and skips 15 of 69, the same as `main` on Zig 0.16.0 with `tiawl/shaderc.zig`. Without `-Dshaderc`: 35 passed, 34 skipped on both.
