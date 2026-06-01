//! Ladder step 1 — **shaderc** (`compile`). *(v0.4.0)*
//!
//! Pure-CPU GLSL→SPIR-V — no GPU/instance/device. Built from source by
//! `tiawl/shaderc.zig` and linked only under `-Dshaderc`, so these tests gate on
//! `shaderc.available` and **auto-skip** unless you build with `-Dshaderc`
//! (`./scripts/tdd.sh` won't run them; `zig build test-tdd -Dshaderc` will).
//! See `docs/shaderc-distribution.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const gate = @import("harness.zig").gate;

const shaderc = vk_stack.shaderc;

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
// shaderc.compile — success paths
// =============================================================================

test "compile: a trivial vertex shader yields SPIR-V with the magic word" {
    try gate(shaderc.available);
    const spv = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{}, null);
    defer std.testing.allocator.free(spv);
    try std.testing.expect(spv.len > 0);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

test "compile: a fragment shader compiles to SPIR-V" {
    try gate(shaderc.available);
    const spv = try shaderc.compile(std.testing.allocator, frag_src, .fragment, .{}, null);
    defer std.testing.allocator.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

test "compile: a compute shader compiles to SPIR-V" {
    try gate(shaderc.available);
    const spv = try shaderc.compile(std.testing.allocator, comp_src, .compute, .{}, null);
    defer std.testing.allocator.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

test "compile: optimize=.none produces valid SPIR-V" {
    try gate(shaderc.available);
    const spv = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{ .optimize = .none }, null);
    defer std.testing.allocator.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

test "compile: optimize=.size produces valid SPIR-V" {
    try gate(shaderc.available);
    const spv = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{ .optimize = .size }, null);
    defer std.testing.allocator.free(spv);
    try std.testing.expectEqual(spirv_magic, spv[0]);
}

test "compile: debug_info=true is valid SPIR-V no smaller than the stripped build" {
    try gate(shaderc.available);
    const dbg = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{ .optimize = .none, .debug_info = true }, null);
    defer std.testing.allocator.free(dbg);
    const stripped = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{ .optimize = .none, .debug_info = false }, null);
    defer std.testing.allocator.free(stripped);
    try std.testing.expectEqual(spirv_magic, dbg[0]);
    try std.testing.expect(dbg.len >= stripped.len);
}

// =============================================================================
// shaderc.compile — failure path + Diagnostics
// =============================================================================

test "compile: invalid GLSL reports ShaderCompilationFailed" {
    try gate(shaderc.available);
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        shaderc.compile(std.testing.allocator, "this is not glsl", .vertex, .{}, null),
    );
}

test "compile: a failure fills Diagnostics with a non-empty message" {
    try gate(shaderc.available);
    var diag: shaderc.Diagnostics = .{};
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        shaderc.compile(std.testing.allocator, "#version 450\nvoid main() { undeclared_fn(); }", .vertex, .{}, &diag),
    );
    defer if (diag.message.len > 0) std.testing.allocator.free(diag.message);
    try std.testing.expect(diag.message.len > 0);
}

test "compile: success leaves a passed Diagnostics untouched" {
    try gate(shaderc.available);
    var diag: shaderc.Diagnostics = .{};
    const spv = try shaderc.compile(std.testing.allocator, vert_src, .vertex, .{}, &diag);
    defer std.testing.allocator.free(spv);
    try std.testing.expectEqual(@as(usize, 0), diag.message.len);
}
