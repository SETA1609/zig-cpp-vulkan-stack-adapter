const std = @import("std");

pub const Modules = struct {
    vulkan_stack_mod: *std.Build.Module,
    vulkan_stack_lib: *std.Build.Step.Compile,
    vk_mod: *std.Build.Module,
    vk_headers: *std.Build.Dependency,
    vma_bridge_lib: *std.Build.Step.Compile,
    have_shaderc: bool,
};

pub fn create(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Modules {
    const vk_mod = b.dependency("vulkan", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
    }).module("vulkan-zig");

    const vulkan_stack_mod = b.addModule("vulkan_stack", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    vulkan_stack_mod.addImport("vulkan", vk_mod);

    const vk_headers = b.dependency("vulkan_headers", .{});
    const vma = b.dependency("vma", .{});
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

    const enable_shaderc = b.option(bool, "shaderc", "Build runtime GLSL→SPIR-V (fetches + builds shaderc from source)") orelse false;
    var have_shaderc = false;
    if (enable_shaderc) {
        if (b.lazyDependency("shaderc_zig", .{ .target = target, .optimize = optimize })) |shaderc_dep| {
            vulkan_stack_mod.linkLibrary(shaderc_dep.artifact("shaderc"));
            vulkan_stack_mod.link_libcpp = true;
            have_shaderc = true;
        }
    }
    const build_config = b.addOptions();
    build_config.addOption(bool, "have_shaderc", have_shaderc);
    vulkan_stack_mod.addOptions("build_config", build_config);

    const vulkan_stack_lib = b.addLibrary(.{
        .name = "vulkan_stack",
        .linkage = .static,
        .root_module = vulkan_stack_mod,
    });
    b.installArtifact(vulkan_stack_lib);

    return .{
        .vulkan_stack_mod = vulkan_stack_mod,
        .vulkan_stack_lib = vulkan_stack_lib,
        .vk_mod = vk_mod,
        .vk_headers = vk_headers,
        .vma_bridge_lib = vma_bridge_lib,
        .have_shaderc = have_shaderc,
    };
}
