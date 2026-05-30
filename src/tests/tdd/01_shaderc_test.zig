//! Ladder step 1 — **shaderc** (`compile` / `lastErrorMessage`). *(v0.4.0)*
//!
//! Pure-CPU GLSL→SPIR-V — the only function family on this library provable in
//! process (no GPU/instance/device). Implement `compile` first; the
//! `lastErrorMessage` tests need a failed `compile` to populate the diagnostic,
//! so they gate on both. See `CONTRIBUTING.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const gate = @import("harness.zig").gate;

const shaderc = vk_stack.shaderc;

const done = .{
    .compile = false,
    .lastErrorMessage = false,
};

/// First word of any valid SPIR-V module (the magic number).
const spirv_magic: u32 = 0x07230203;

const vert_src =
    \\#version 450
    \\void main() { gl_Position = vec4(0.0, 0.0, 0.0, 1.0); }
;
const frag_src =
    \\#version 450
    \\layout(location = 0) out vec4 color;
    \\void main() { color = vec4(1.0, 0.0, 0.0, 1.0); }
;
const comp_src =
    \\#version 450
    \\layout(local_size_x = 1) in;
    \\void main() {}
;

// =============================================================================
// shaderc.compile
// =============================================================================

test "compile: a trivial vertex shader yields SPIR-V with the magic word" {
    try gate(done.compile);
    const spv = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{});
    defer std.testing.allocator.free(spv);
    try std.testing.expect(spv.len > 0);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

test "compile: a fragment shader compiles to SPIR-V" {
    try gate(done.compile);
    const spv = try shaderc.compile(std.testing.allocator, frag_src, .fragment, .{});
    defer std.testing.allocator.free(spv);
    try std.testing.expect(spv.len > 0);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

test "compile: a compute shader compiles to SPIR-V" {
    try gate(done.compile);
    const spv = try shaderc.compile(std.testing.allocator, comp_src, .compute, .{});
    defer std.testing.allocator.free(spv);
    try std.testing.expect(spv.len > 0);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

test "compile: optimize=.none produces valid SPIR-V" {
    try gate(done.compile);
    const spv = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{ .optimize = .none });
    defer std.testing.allocator.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

test "compile: optimize=.size produces valid SPIR-V" {
    try gate(done.compile);
    const spv = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{ .optimize = .size });
    defer std.testing.allocator.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

test "compile: debug_info=true produces valid SPIR-V no smaller than the stripped build" {
    try gate(done.compile);
    const dbg = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{ .optimize = .none, .debug_info = true });
    defer std.testing.allocator.free(dbg);
    const stripped = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{ .optimize = .none, .debug_info = false });
    defer std.testing.allocator.free(stripped);
    try std.testing.expectEqual(spirv_magic, dbg[0]);
    // Debug info (OpLine/OpSource) only adds instructions.
    try std.testing.expect(dbg.len >= stripped.len);
}

test "compile: invalid GLSL reports ShaderCompilationFailed" {
    try gate(done.compile);
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        shaderc.compile(std.testing.allocator, "this is not glsl", .vertex, .{}),
    );
}

// =============================================================================
// shaderc.lastErrorMessage
// =============================================================================

test "lastErrorMessage: is non-empty after a failed compile" {
    try gate(done.compile and done.lastErrorMessage);
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        shaderc.compile(std.testing.allocator, "void main() { syntax error }", .vertex, .{}),
    );
    try std.testing.expect(shaderc.lastErrorMessage().len > 0);
}

test "lastErrorMessage: is a borrowed, stable slice between compiles" {
    try gate(done.compile and done.lastErrorMessage);
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        shaderc.compile(std.testing.allocator, "#version 450\nvoid main() { undeclared_fn(); }", .vertex, .{}),
    );
    const a = shaderc.lastErrorMessage();
    const b = shaderc.lastErrorMessage();
    try std.testing.expectEqualStrings(a, b);
    try std.testing.expectEqual(a.ptr, b.ptr);
}

test "lastErrorMessage: distinguishes a fresh failure from a prior one" {
    try gate(done.compile and done.lastErrorMessage);
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        shaderc.compile(std.testing.allocator, "garbage one", .vertex, .{}),
    );
    const ok = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{});
    std.testing.allocator.free(ok);
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        shaderc.compile(std.testing.allocator, "garbage two", .vertex, .{}),
    );
    try std.testing.expect(shaderc.lastErrorMessage().len > 0);
}
