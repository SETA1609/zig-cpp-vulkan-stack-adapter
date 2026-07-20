//! Test step wiring for the vulkan-stack adapter.
//!
//! Creates two test targets:
//! - `test` — contract unit tests (`src/tests/api_test.zig`)
//! - `test-tdd` — behavioural TDD suite (`src/tests/tdd/main.zig`)

const std = @import("std");
const Modules = @import("modules.zig").Modules;

pub const TestSteps = struct {
    unit: *std.Build.Step,
    tdd: *std.Build.Step,
};

pub fn create(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, m: Modules) TestSteps {
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/api_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("vulkan_stack", m.vulkan_stack_mod);
    test_mod.addImport("vulkan", m.vk_mod);
    const tests = b.addTest(.{ .root_module = test_mod });
    const unit = b.step("test", "Run the vulkan_stack unit tests");
    unit.dependOn(&b.addRunArtifact(tests).step);

    const tdd_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/tdd/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tdd_mod.addImport("vulkan_stack", m.vulkan_stack_mod);
    tdd_mod.addImport("vulkan", m.vk_mod);
    const tdd_tests = b.addTest(.{ .root_module = tdd_mod });
    const tdd = b.step("test-tdd", "Run the red→green TDD suite (fails until the backends are implemented)");
    tdd.dependOn(&b.addRunArtifact(tdd_tests).step);

    return .{ .unit = unit, .tdd = tdd };
}
