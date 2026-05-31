//! Shared helpers for the ordered TDD suite (`src/tests/tdd/`).
//!
//! `gate` skips a test until its function's `done` flag is flipped. `VkCtx` is
//! a minimal **headless** Vulkan context (instance + physical device + logical
//! device, no surface/window) for the device-dependent volk/VMA unit tests —
//! built via volk's dynamic loader handing its `vkGetInstanceProcAddr` to
//! vulkan-zig's dispatch wrappers. See `CONTRIBUTING.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const vk = @import("vulkan");

const volk = vk_stack.volk;
const vma = vk_stack.vma;

/// Skip a test until the function it covers is implemented.
pub fn gate(implemented: bool) error{SkipZigTest}!void {
    if (!implemented) return error.SkipZigTest;
}

pub const VkCtx = struct {
    instance: vk.Instance,
    physical: vk.PhysicalDevice,
    device: vk.Device,
    vki: vk.InstanceWrapper,
    vkd: vk.DeviceWrapper,

    pub fn init() !VkCtx {
        try volk.loadBase();
        const gipa = volk.getInstanceProcAddr();
        const vkb = vk.BaseWrapper.load(gipa);

        const instance = try vkb.createInstance(&.{}, null);
        volk.loadInstance(instance);
        const vki = vk.InstanceWrapper.load(instance, gipa);

        // First physical device is enough for headless allocation tests.
        var count: u32 = 1;
        var physical: vk.PhysicalDevice = undefined;
        _ = try vki.enumeratePhysicalDevices(instance, &count, @ptrCast(&physical));

        // One queue from family 0 — VMA needs a device, not specific queues.
        const prio = [_]f32{1.0};
        const qci = [_]vk.DeviceQueueCreateInfo{.{
            .queue_family_index = 0,
            .queue_count = 1,
            .p_queue_priorities = &prio,
        }};
        const device = try vki.createDevice(physical, &.{
            .queue_create_info_count = 1,
            .p_queue_create_infos = &qci,
        }, null);
        volk.loadDevice(device);
        const vkd = vk.DeviceWrapper.load(device, vki.dispatch.vkGetDeviceProcAddr.?);

        return .{ .instance = instance, .physical = physical, .device = device, .vki = vki, .vkd = vkd };
    }

    pub fn deinit(self: *VkCtx) void {
        self.vkd.destroyDevice(self.device, null);
        self.vki.destroyInstance(self.instance, null);
    }

    /// The VMA allocator inputs for this context.
    pub fn allocInfo(self: VkCtx) vma.AllocatorCreateInfo {
        return .{ .physical_device = self.physical, .device = self.device, .instance = self.instance };
    }
};
