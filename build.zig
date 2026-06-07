//! Build script for zig-cpp-vulkan-stack-adapter.
//!
//! Produces two things downstream consumes (the libs-first / link-the-artifact
//! model — see ../README.md):
//!   1. A Zig module named "vulkan_stack" (the public API in src/root.zig).
//!   2. A static-library artifact named "vulkan_stack" that will bundle the
//!      compiled Zig glue plus the C/C++ from volk/VMA/shaderc as those land.
//!
//! The one piece that is *real* today is the `vk` re-export: vulkan-zig's
//! generator turns Khronos' `vk.xml` registry into Zig bindings at build time,
//! and we expose that as the `vulkan` module which src/root.zig re-exports.
//! Everything else in the module is a panic-on-call stub (see docs/completion-plan.md).

const std = @import("std");

pub fn build(b: *std.Build) void {
    // Target triple (CPU/OS/ABI) and optimization mode. Default to the host
    // / Debug; override with `-Dtarget=...` / `-Doptimize=...`.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- vk bindings: generate from vk.xml ----------------------------------
    // vulkan-zig exposes a generator that reads the Vulkan XML registry and
    // emits typed Zig bindings. We hand it the `registry/vk.xml` shipped by
    // the Vulkan-Headers dependency, and take back the generated `vulkan-zig`
    // module. This is the documented package-manager wiring (vulkan-zig
    // README § "Generating bindings directly from Vulkan-Headers").
    const vk_mod = b.dependency("vulkan", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");

    // --- Public Zig API module ----------------------------------------------
    // `addModule` registers it under "vulkan_stack" so downstream
    // `b.dependency("vulkan_stack", ...).module("vulkan_stack")` resolves it.
    const vulkan_stack_mod = b.addModule("vulkan_stack", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        // libc for the loader / surface creators (volk, vkCreate*SurfaceKHR)
        // once they land. libcpp gets switched on with the VMA C++ bridge at
        // v0.3.0 (it has no C entry point) — left off until there's C++ to link.
        .link_libc = true,
    });
    // src/root.zig does `pub const vk = @import("vulkan");`.
    vulkan_stack_mod.addImport("vulkan", vk_mod);

    // --- VMA C++ bridge -----------------------------------------------------
    // VMA is header-only C++, so it compiles in its OWN static lib (the only
    // C++ translation unit) which the vulkan_stack artifact links — keeping the
    // C++ out of every consumer's compile. Vulkan headers come from the same
    // pinned Vulkan-Headers dep used for vk.xml; VMA loads Vulkan entry points
    // dynamically (we don't hard-link libvulkan — see the volk loader).
    const vk_headers = b.dependency("vulkan_headers", .{});
    const vma = b.dependency("vma", .{}); // header-only VMA, pinned in build.zig.zon (no submodule)
    const vma_bridge_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    vma_bridge_mod.link_libcpp = true;
    vma_bridge_mod.addIncludePath(b.path("src/c"));
    vma_bridge_mod.addIncludePath(vma.path("include"));
    vma_bridge_mod.addIncludePath(vk_headers.path("include"));
    vma_bridge_mod.addCSourceFile(.{
        .file = b.path("src/c/vma_bridge.cpp"),
        .flags = &.{ "-std=c++23", "-DVK_NO_PROTOTYPES" },
    });
    const vma_bridge_lib = b.addLibrary(.{
        .name = "vma_bridge",
        .linkage = .static,
        .root_module = vma_bridge_mod,
    });
    vulkan_stack_mod.linkLibrary(vma_bridge_lib);

    // --- shaderc (optional, lazy) -------------------------------------------
    // GLSL→SPIR-V via tiawl/shaderc.zig, which builds shaderc + glslang +
    // SPIRV-Tools from source (no system SDK, cross-compiles). OFF by default so
    // consumers who embed precompiled SPIR-V don't pay the glslang build; enable
    // with `-Dshaderc`. See docs/shaderc-distribution.md.
    const enable_shaderc = b.option(bool, "shaderc", "Build runtime GLSL→SPIR-V (fetches + builds shaderc from source)") orelse false;
    var have_shaderc = false;
    if (enable_shaderc) {
        if (b.lazyDependency("shaderc_zig", .{ .target = target, .optimize = optimize })) |shaderc_dep| {
            vulkan_stack_mod.linkLibrary(shaderc_dep.artifact("shaderc"));
            vulkan_stack_mod.link_libcpp = true; // glslang / SPIRV-Tools are C++
            have_shaderc = true;
        }
    }
    // Expose `have_shaderc` to the source (shaderc.zig) and the TDD suite (to
    // gate the shaderc tests) via an importable `build_config`.
    const build_config = b.addOptions();
    build_config.addOption(bool, "have_shaderc", have_shaderc);
    vulkan_stack_mod.addOptions("build_config", build_config);

    // --- Static-library artifact --------------------------------------------
    // Downstream `linkLibrary` on this pulls in the compiled Zig glue and
    // (later) volk/VMA/shaderc. Today it is a thin lib over the generated `vk`.
    const vulkan_stack_lib = b.addLibrary(.{
        .name = "vulkan_stack",
        .linkage = .static,
        .root_module = vulkan_stack_mod,
    });
    b.installArtifact(vulkan_stack_lib);

    // --- `zig build run` ----------------------------------------------------
    // A smoke demo that imports the module as a consumer would. Exercises the
    // real `vk` re-export and prints status (see demo/main.zig).
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("demo/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    demo_mod.addImport("vulkan_stack", vulkan_stack_mod);
    demo_mod.linkLibrary(vulkan_stack_lib);
    const demo = b.addExecutable(.{ .name = "smoke", .root_module = demo_mod });
    b.installArtifact(demo);
    const run_cmd = b.addRunArtifact(demo);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Build + run the smoke demo").dependOn(&run_cmd.step);

    // --- `zig build test` ---------------------------------------------------
    // Unit tests for the public surface (src/tests/api_test.zig, which pulls in
    // root.zig and its siblings). Data/contract tests run today — including the
    // real `vk` re-export; the bridge behavioral tests are skipped until
    // implemented. CI gates merges to `main` on this step.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/api_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Consume the public module exactly as a downstream app would, plus `vulkan`
    // for the few tests that touch the `vk` re-export directly.
    test_mod.addImport("vulkan_stack", vulkan_stack_mod);
    test_mod.addImport("vulkan", vk_mod);
    const tests = b.addTest(.{ .root_module = test_mod });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run the vulkan_stack unit tests")
        .dependOn(&run_tests.step);

    // --- `zig build test-tdd` -----------------------------------------------
    // Ordered red→green TDD suite (src/tests/tdd/). Every test calls a real
    // function and asserts its result, but is gated behind a per-function
    // `done` flag so it SKIPS until implemented — so this step is green (all
    // skipped) today and a contributor flips one flag, makes that function
    // pass, and PRs it (see CONTRIBUTING.md). Kept off CI's `test` step. Scope
    // is shaderc only — the GPU/instance/surface functions are e2e (see
    // docs/manual-testing.md). Focus with `-- --test-filter <name>`.
    const tdd_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/tdd/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tdd_mod.addImport("vulkan_stack", vulkan_stack_mod);
    tdd_mod.addImport("vulkan", vk_mod);
    const tdd_tests = b.addTest(.{ .root_module = tdd_mod });
    const run_tdd_tests = b.addRunArtifact(tdd_tests);
    b.step("test-tdd", "Run the red→green TDD suite (fails until the backends are implemented)")
        .dependOn(&run_tdd_tests.step);
}
