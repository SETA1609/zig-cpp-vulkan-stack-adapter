//! Smoke demo for `zig build run`.
//!
//! Exercises the one piece that is real today — the `vk` re-export — and
//! prints status. It does NOT call the stubbed volk/VMA/shaderc/surface
//! bridges, so it runs to a clean exit. Not shipped to consumers (outside
//! `build.zig.zon` `.paths`).

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const vk = vk_stack.vk;

pub fn main() void {
    const api: u32 = @bitCast(vk.API_VERSION_1_3);
    std.debug.print(
        \\vulkan-stack-adapter
        \\  vk re-export   : live (vulkan-zig from vk.xml), API_VERSION_1_3 = {d}
        \\  volk/vma/shaderc/surface : @panic stubs until their milestones
        \\
    , .{api});
}
