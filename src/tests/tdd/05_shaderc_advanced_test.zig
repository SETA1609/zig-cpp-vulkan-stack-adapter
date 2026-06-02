//! Ladder — **shaderc depth** (macro definitions, target SPIR-V/Vulkan
//! version, `#include` resolution, and the ray-tracing / mesh `Stage`s).
//! *(v0.4.x)* Pure-CPU like `01_shaderc_test.zig`; gates on `shaderc.available`,
//! so it auto-skips unless built with `-Dshaderc`. See
//! `docs/shaderc-distribution.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const gate = @import("harness.zig").gate;

const shaderc = vk_stack.shaderc;
const alloc = std.testing.allocator;

const spirv_magic: u32 = 0x07230203;

const done = .{
    .macros = true,
    .target = true,
    .includes = true,
    .stages = true,
};

// =============================================================================
// Macro definitions
// =============================================================================

// Only compiles when ENABLE is defined (otherwise the #else branch is garbage).
const macro_guarded =
    \\#version 450
    \\void main() {
    \\#ifndef ENABLE
    \\  this is not glsl
    \\#endif
    \\}
;

// WHEN compiling source guarded by #ifndef ENABLE with the ENABLE macro defined · GIVEN shaderc available · THEN the valid branch is selected and the SPIR-V begins with the magic word.
test "macros: a defined macro selects the valid #ifdef branch" {
    try gate(shaderc.available and done.macros);
    const spv = try shaderc.compile(alloc, macro_guarded, .vertex, .{
        .macros = &.{.{ .name = "ENABLE" }},
    }, null);
    defer alloc.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

// WHEN compiling the macro-guarded source with no macros defined · GIVEN shaderc available · THEN the garbage #else branch is hit and compile returns error.ShaderCompilationFailed.
test "macros: without the macro the same source fails to compile" {
    try gate(shaderc.available and done.macros);
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        shaderc.compile(alloc, macro_guarded, .vertex, .{}, null),
    );
}

// WHEN compiling source that uses VALUE with a valued macro VALUE=1.0 defined · GIVEN shaderc available · THEN substitution succeeds and the SPIR-V begins with the magic word.
test "macros: a valued macro is substituted into the source" {
    try gate(shaderc.available and done.macros);
    const src =
        \\#version 450
        \\void main() { gl_Position = vec4(VALUE); }
    ;
    const spv = try shaderc.compile(alloc, src, .vertex, .{
        .macros = &.{.{ .name = "VALUE", .value = "1.0" }},
    }, null);
    defer alloc.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

// =============================================================================
// Target SPIR-V / Vulkan version
// =============================================================================

const vert_src =
    \\#version 450
    \\void main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); }
;

// WHEN compiling a vertex shader with target=.vulkan_1_3 · GIVEN shaderc available · THEN the emitted SPIR-V begins with the magic word.
test "target: vulkan_1_3 yields valid SPIR-V" {
    try gate(shaderc.available and done.target);
    const spv = try shaderc.compile(alloc, vert_src, .vertex, .{ .target = .vulkan_1_3 }, null);
    defer alloc.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

// WHEN compiling the same shader at target .vulkan_1_0 versus .vulkan_1_3 · GIVEN shaderc available · THEN the 1.3 build's SPIR-V version word (spv[1]) is greater than the 1.0 build's.
test "target: a higher Vulkan target emits a higher SPIR-V version word" {
    try gate(shaderc.available and done.target);
    // spv[1] is the SPIR-V version word; Vulkan 1.0→SPIR-V 1.0, 1.3→SPIR-V 1.6.
    const lo = try shaderc.compile(alloc, vert_src, .vertex, .{ .target = .vulkan_1_0 }, null);
    defer alloc.free(lo);
    const hi = try shaderc.compile(alloc, vert_src, .vertex, .{ .target = .vulkan_1_3 }, null);
    defer alloc.free(hi);
    try std.testing.expect(hi[1] > lo[1]);
}

// =============================================================================
// #include resolution
// =============================================================================

const Includes = struct {
    fn resolve(ctx: ?*anyopaque, requested: []const u8, requesting: []const u8) ?shaderc.IncludeResult {
        _ = ctx;
        _ = requesting;
        if (std.mem.eql(u8, requested, "common.glsl"))
            return .{ .name = "common.glsl", .content = "float value() { return 1.0; }\n" };
        return null;
    }
};

const includer_src =
    \\#version 450
    \\#include "common.glsl"
    \\void main() { gl_Position = vec4(value(), 0.0, 0.0, 1.0); }
;

// WHEN compiling source with #include "common.glsl" and an includer that resolves it · GIVEN shaderc available · THEN the include is pulled in and the SPIR-V begins with the magic word.
test "includes: a resolved #include is pulled into the compilation" {
    try gate(shaderc.available and done.includes);
    const spv = try shaderc.compile(alloc, includer_src, .vertex, .{
        .includer = .{ .resolve = Includes.resolve },
    }, null);
    defer alloc.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

// WHEN compiling source that #includes "missing.glsl" the includer cannot resolve · GIVEN shaderc available and a Diagnostics sink · THEN compile returns error.ShaderCompilationFailed and the diagnostic message is non-empty.
test "includes: an unresolved #include fails with a diagnostic" {
    try gate(shaderc.available and done.includes);
    const src =
        \\#version 450
        \\#include "missing.glsl"
        \\void main() {}
    ;
    var diag: shaderc.Diagnostics = .{};
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        shaderc.compile(alloc, src, .vertex, .{ .includer = .{ .resolve = Includes.resolve } }, &diag),
    );
    defer if (diag.message.len > 0) alloc.free(diag.message);
    try std.testing.expect(diag.message.len > 0);
}

// WHEN compiling source containing an #include with no includer configured · GIVEN shaderc available · THEN compile returns error.ShaderCompilationFailed.
test "includes: an #include with no includer set fails" {
    try gate(shaderc.available and done.includes);
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        shaderc.compile(alloc, includer_src, .vertex, .{}, null),
    );
}

// =============================================================================
// New stages — ray tracing & mesh
// =============================================================================

// WHEN compiling a GL_EXT_ray_tracing raygen shader in the .raygen stage with target .vulkan_1_2 · GIVEN shaderc available · THEN the SPIR-V begins with the magic word.
test "stages: a raygen shader compiles under a Vulkan 1.2 target" {
    try gate(shaderc.available and done.stages);
    const src =
        \\#version 460
        \\#extension GL_EXT_ray_tracing : require
        \\void main() {}
    ;
    const spv = try shaderc.compile(alloc, src, .raygen, .{ .target = .vulkan_1_2 }, null);
    defer alloc.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

// WHEN compiling a GL_EXT_mesh_shader mesh shader in the .mesh stage with target .vulkan_1_3 · GIVEN shaderc available · THEN the SPIR-V begins with the magic word.
test "stages: a mesh shader compiles under a Vulkan 1.3 target" {
    try gate(shaderc.available and done.stages);
    const src =
        \\#version 450
        \\#extension GL_EXT_mesh_shader : require
        \\layout(local_size_x = 1) in;
        \\layout(triangles, max_vertices = 3, max_primitives = 1) out;
        \\void main() { SetMeshOutputsEXT(0, 0); }
    ;
    const spv = try shaderc.compile(alloc, src, .mesh, .{ .target = .vulkan_1_3 }, null);
    defer alloc.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}
