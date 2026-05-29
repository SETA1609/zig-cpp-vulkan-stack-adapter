//! Unit tests for the `vulkan_stack` public API.
//!
//! Two tiers:
//!  * **Data / contract tests** run today: the `vk` re-export is real, and the
//!    wrapper enums / option defaults are pure data. These must stay green.
//!  * **Behavioral tests** assert how the real bridges (volk / VMA / shaderc /
//!    surface creators) must behave. They are written against the live API (so
//!    they stay type-checked) but **skipped** until each bridge lands — flip
//!    `impl_ready` to `true` (or drop a test's guard) to run them.
//!
//! `zig build test` builds and runs this; CI gates merges to `main` on it.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const vk = @import("vulkan");

/// Flip to `true` once the volk/VMA/shaderc/surface bridges are implemented
/// (or drop the guard per feature as it ships). Container `var` so guarded
/// assertions stay type-checked rather than comptime-eliminated.
var impl_ready: bool = false;

fn skipUntilImplemented() error{SkipZigTest}!void {
    if (!impl_ready) return error.SkipZigTest;
}

// Vulkan 1.3 packed into a u32: (major << 22) | (minor << 12) == (1<<22)|(3<<12).
const api_1_3: u32 = (1 << 22) | (3 << 12);

// =============================================================================
// Data / contract tests — active now (the `vk` re-export is real)
// =============================================================================

test "vk re-export exposes the typed Vulkan API" {
    try std.testing.expect(@hasDecl(vk, "Instance"));
    try std.testing.expect(@hasDecl(vk, "Device"));
    try std.testing.expect(@hasDecl(vk, "SurfaceKHR"));
    // Dispatch wrappers vulkan-zig generates from vk.xml.
    try std.testing.expect(@hasDecl(vk, "BaseWrapper"));
    try std.testing.expect(@hasDecl(vk, "InstanceWrapper"));
    try std.testing.expect(@hasDecl(vk, "DeviceWrapper"));
}

test "vk.API_VERSION_1_3 encodes to the expected u32" {
    try std.testing.expectEqual(api_1_3, @as(u32, @bitCast(vk.API_VERSION_1_3)));
}

test "root re-exports the four bundled namespaces" {
    try std.testing.expect(@TypeOf(vk_stack.vk) == @TypeOf(vk));
    // volk / vma / shaderc are namespaces (structs) exposed at module root.
    try std.testing.expect(@hasDecl(vk_stack.vma, "createBuffer"));
    try std.testing.expect(@hasDecl(vk_stack.shaderc, "compile"));
    try std.testing.expect(@hasDecl(vk_stack.volk, "loadBase"));
}

test "enum values: shaderc.Stage (match enum-values.md)" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(vk_stack.shaderc.Stage.vertex));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(vk_stack.shaderc.Stage.fragment));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(vk_stack.shaderc.Stage.compute));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(vk_stack.shaderc.Stage.tess_eval));
}

test "enum values: shaderc.OptimizeLevel + vma.Usage" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(vk_stack.shaderc.OptimizeLevel.none));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(vk_stack.shaderc.OptimizeLevel.performance));
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(vk_stack.vma.Usage.auto));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(vk_stack.vma.Usage.gpu_only));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(vk_stack.vma.Usage.cpu_to_gpu));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(vk_stack.vma.Usage.gpu_to_cpu));
}

test "shaderc.CompileOptions defaults" {
    const o: vk_stack.shaderc.CompileOptions = .{};
    try std.testing.expectEqual(vk_stack.shaderc.OptimizeLevel.performance, o.optimize);
    try std.testing.expect(!o.debug_info);
    try std.testing.expectEqualStrings("main", o.entry_point);
}

test "vma.AllocatorCreateInfo defaults to Vulkan 1.3" {
    const info: vk_stack.vma.AllocatorCreateInfo = .{
        .physical_device = .null_handle,
        .device = .null_handle,
        .instance = .null_handle,
    };
    try std.testing.expectEqual(api_1_3, info.api_version);
}

test "every public declaration type-checks (incl. unreferenced stubs)" {
    // Forces semantic analysis of every decl/body without calling them, so a
    // signature drift in an otherwise-untested stub is still caught.
    std.testing.refAllDecls(vk_stack); // surface creators + namespaces
    std.testing.refAllDecls(vk_stack.vma);
    std.testing.refAllDecls(vk_stack.volk);
    std.testing.refAllDecls(vk_stack.shaderc);
}

// =============================================================================
// Behavioral tests — skipped until the bridges are implemented
// =============================================================================

test "shaderc: a trivial vertex shader compiles to SPIR-V" {
    try skipUntilImplemented();
    const src =
        \\#version 450
        \\void main() { gl_Position = vec4(0.0); }
    ;
    const spv = try vk_stack.shaderc.compile(std.testing.allocator, src, .vertex, .{});
    defer std.testing.allocator.free(spv);
    try std.testing.expect(spv.len > 0);
    // SPIR-V magic number is the first word.
    try std.testing.expectEqual(@as(u32, 0x07230203), spv[0]);
}

test "shaderc: invalid GLSL reports a diagnostic" {
    try skipUntilImplemented();
    const bad = "this is not glsl";
    try std.testing.expectError(
        error.ShaderCompilationFailed,
        vk_stack.shaderc.compile(std.testing.allocator, bad, .vertex, .{}),
    );
    try std.testing.expect(vk_stack.shaderc.lastErrorMessage().len > 0);
}

test "vma: allocator lifecycle round-trips (needs a real device)" {
    try skipUntilImplemented();
    const allocator = try vk_stack.vma.createAllocator(.{
        .physical_device = .null_handle,
        .device = .null_handle,
        .instance = .null_handle,
    });
    defer vk_stack.vma.destroyAllocator(allocator);
}

test "surface: X11 creator returns a non-null surface (needs a real instance)" {
    try skipUntilImplemented();
    const dummy: *anyopaque = @ptrFromInt(@alignOf(usize));
    const surface = try vk_stack.createX11Surface(.null_handle, dummy, 0);
    try std.testing.expect(surface != .null_handle);
}
