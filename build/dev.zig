//! Development-step wiring for the vulkan-stack adapter.
//!
//! Creates a smoke demo executable (`demo/main.zig`) that imports the vulkan_stack
//! module as a downstream consumer would, and registers:
//! - `zig build run` — build + run the smoke demo
//! - `zig build pipeline` — build the static library (default step)

const std = @import("std");
const Modules = @import("modules.zig").Modules;
const TestSteps = @import("tests.zig").TestSteps;

pub fn create(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, m: Modules, _: TestSteps) void {
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("demo/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    demo_mod.addImport("vulkan_stack", m.vulkan_stack_mod);
    demo_mod.linkLibrary(m.vulkan_stack_lib);
    const demo = b.addExecutable(.{ .name = "smoke", .root_module = demo_mod });
    b.installArtifact(demo);
    const run_cmd = b.addRunArtifact(demo);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Build + run the smoke demo").dependOn(&run_cmd.step);

    const pipeline = b.step("pipeline", "Build the vulkan-stack adapter library");
    pipeline.dependOn(b.getInstallStep());
    b.default_step = pipeline;
}
