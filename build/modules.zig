//! Module and library creation for the vulkan-stack adapter.
//!
//! Creates the `vulkan_stack` Zig module (`src/root.zig`), wires the
//! vulkan-zig typed bindings, builds the VMA C++ bridge (`src/c/vma_bridge.cpp`),
//! and optionally imports `shaderc_zig` for runtime GLSL→SPIR-V under the
//! `-Dshaderc` flag. Produces a `vulkan_stack` static-link artifact.

const std = @import("std");

/// Target platforms for Vulkan surface creation.
/// Each variant maps to a `vkCreate*SurfaceKHR` extension.
pub const Platform = enum(u3) {
    x11,
    wayland,
    win32,
    android,
    metal,

    pub const all = [_]Platform{ .x11, .wayland, .win32, .android, .metal };
};

pub const Modules = struct {
    vulkan_stack_mod: *std.Build.Module,
    vulkan_stack_lib: *std.Build.Step.Compile,
    vk_mod: *std.Build.Module,
    vk_headers: *std.Build.Dependency,
    vma_bridge_lib: *std.Build.Step.Compile,
    have_shaderc: bool,
    platforms: []const Platform,
};

fn parsePlatforms(opt: []const u8, allocator: std.mem.Allocator) []const Platform {
    if (std.mem.eql(u8, opt, "all")) return allocator.dupe(Platform, &Platform.all) catch @panic("OOM");
    var list: std.ArrayList(Platform) = .empty;
    errdefer list.deinit(allocator);
    var it = std.mem.tokenizeScalar(u8, opt, ' ');
    while (it.next()) |token| {
        const p = std.meta.stringToEnum(Platform, token) orelse
            std.debug.panic("Unknown platform '{s}'. Valid: x11, wayland, win32, android, metal", .{token});
        list.append(allocator, p) catch @panic("OOM");
    }
    return list.toOwnedSlice(allocator) catch @panic("OOM");
}

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

    // --- Platform selection --------------------------------------------------
    const platform_opt = b.option([]const u8, "platforms",
        "Target Vulkan surface platforms: x11, wayland, win32, android, metal (space-separated, default: all)") orelse "all";
    const platforms = parsePlatforms(platform_opt, b.allocator);

    // --- Shaderc (optional) --------------------------------------------------
    const enable_shaderc = b.option(bool, "shaderc", "Build runtime GLSL→SPIR-V (fetches + builds shaderc from source)") orelse false;
    var have_shaderc = false;
    if (enable_shaderc) {
        if (b.lazyDependency("shaderc_zig", .{ .target = target, .optimize = optimize })) |shaderc_dep| {
            vulkan_stack_mod.linkLibrary(shaderc_dep.artifact("shaderc"));
            vulkan_stack_mod.link_libcpp = true;
            have_shaderc = true;
        }
    }

    // --- Build config options that source code can query --------------------
    const build_config = b.addOptions();
    inline for (@typeInfo(Platform).@"enum".fields) |field| {
        const p: Platform = @enumFromInt(field.value);
        const enabled = for (platforms) |ep| { if (ep == p) break true; } else false;
        build_config.addOption(bool, b.fmt("platform_{s}", .{field.name}), enabled);
    }
    build_config.addOption(bool, "have_shaderc", have_shaderc);
    vulkan_stack_mod.addOptions("build_config", build_config);

    // --- Static library artifact --------------------------------------------
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
        .platforms = platforms,
    };
}
