//! Ladder step 8 — **`Instance` bootstrap helper** (`Instance.create` /
//! `deinit` / `toRaw` / `selectExtensions`). *(v0.7.0)* The create path needs a
//! Vulkan loader (`libvulkan`) at runtime; the policy + contract are checkable
//! in-process. Pinned here: the default Options, the **raw-first invariant**
//! (`selectExtensions` returns plain `[*:0]const u8` names a consumer feeds to
//! their own `vk.InstanceCreateInfo`), and that a consumer's required
//! extensions survive into the selected set. See `CONTRIBUTING.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const vk = @import("vulkan");
const h = @import("harness.zig");
const gate = h.gate;

const volk = vk_stack.volk;
const Instance = vk_stack.Instance;

const done = .{
    .create = false,
    .deinit = false,
    .toRaw = false,
    .selectExtensions = false,
};

// --- Options policy --------------------------------------------------------

// WHEN reading a default Options · GIVEN the Instance helper · THEN it targets Vulkan 1.3 and leaves validation off by default.
test "Options: defaults target 1.3 with validation off" {
    try gate(done.create);
    const o: Instance.Options = .{};
    try std.testing.expectEqual(@as(u32, @bitCast(vk.API_VERSION_1_3)), o.api_version);
    try std.testing.expectEqual(false, o.enable_validation);
}

// --- create / deinit -------------------------------------------------------

// WHEN creating an instance · GIVEN a Vulkan loader is present · THEN a non-null handle is returned with its dispatch loaded.
test "create: yields a non-null instance with loaded dispatch" {
    try gate(done.create);
    try volk.loadBase();
    const vkb = vk.BaseWrapper.load(volk.getInstanceProcAddr());
    var inst = try Instance.create(std.testing.allocator, vkb, .{});
    defer inst.deinit(std.testing.allocator);
    try std.testing.expect(inst.handle != .null_handle);
}

// WHEN deinit-ing then creating again · GIVEN a Vulkan loader · THEN a fresh instance is obtainable (clean teardown frees the owned slices).
test "deinit: an instance can be created again after teardown" {
    try gate(done.create and done.deinit);
    try volk.loadBase();
    const vkb = vk.BaseWrapper.load(volk.getInstanceProcAddr());
    var first = try Instance.create(std.testing.allocator, vkb, .{});
    first.deinit(std.testing.allocator);
    var second = try Instance.create(std.testing.allocator, vkb, .{});
    defer second.deinit(std.testing.allocator);
}

// --- toRaw (bridge) --------------------------------------------------------

// WHEN inspecting toRaw's type · GIVEN the bridge · THEN it returns the raw `vk.Instance`, not a wrapper (drop-to-raw invariant).
test "toRaw: returns the raw vk.Instance handle" {
    try gate(done.toRaw);
    const f: *const fn (Instance) vk.Instance = Instance.toRaw;
    _ = f;
}

// --- selectExtensions (pro tier) -------------------------------------------

// WHEN inspecting selectExtensions's type · GIVEN the pro-tier API · THEN it returns owned raw `[][*:0]const u8` names — feedable to a hand-built vk.InstanceCreateInfo, creating nothing.
test "selectExtensions: returns raw extension names (raw path never blocked)" {
    try gate(done.selectExtensions);
    const f: *const fn (std.mem.Allocator, Instance.Options) vk_stack.InstanceError![][*:0]const u8 = Instance.selectExtensions;
    _ = f;
}

// WHEN selecting extensions with a required name · GIVEN a consumer's required list · THEN the result contains that required extension.
test "selectExtensions: a required extension survives into the selected set" {
    try gate(done.selectExtensions);
    const required = [_][*:0]const u8{"VK_KHR_surface"};
    const exts = try Instance.selectExtensions(std.testing.allocator, .{ .required_extensions = &required });
    defer std.testing.allocator.free(exts);
    var found = false;
    for (exts) |e| {
        if (std.mem.eql(u8, std.mem.span(e), "VK_KHR_surface")) found = true;
    }
    try std.testing.expect(found);
}
