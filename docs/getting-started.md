# Getting started — vulkan adapter

A from-scratch walkthrough: add the dependency, wire the build, and bootstrap a
Vulkan instance + surface. For the API reference see [`api.md`](api.md); for how
Vulkan works see [`vulkan-cheat-sheet.md`](vulkan-cheat-sheet.md).

**Requires Zig 0.16+** and, at runtime, a Vulkan loader (`libvulkan`) + ICD.

## 1. Add the dependency

```sh
zig fetch --save git+https://github.com/SETA1609/zig-cpp-vulkan-stack-adapter.git#<tag>
```

```zig
.dependencies = .{
    .vulkan_stack = .{ .url = "git+https://github.com/SETA1609/zig-cpp-vulkan-stack-adapter.git#<tag>", .hash = "..." },
},
```

## 2. Wire the build

Import the **module** (`vulkan_stack`, which re-exports vulkan-zig's `vk`) and
link the **artifact**:

```zig
// build.zig
const vk_dep = b.dependency("vulkan_stack", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("vulkan_stack", vk_dep.module("vulkan_stack"));
exe.root_module.linkLibrary(vk_dep.artifact("vulkan_stack"));
```

## 3. Bootstrap loader → instance → surface

```zig
const std = @import("std");
const vk_stack = @import("vulkan_stack");
const vk = vk_stack.vk;       // full typed vulkan-zig API
const volk = vk_stack.volk;   // pure-Zig dynamic loader

pub fn run(x11_display: *anyopaque, x11_window: u64, exts: []const [*:0]const u8) !void {
    // 1. Open the Vulkan library and bootstrap vulkan-zig's typed dispatch.
    try volk.loadBase();
    const vkb = vk.BaseWrapper.load(volk.getInstanceProcAddr());

    // 2. Create the instance with the extensions your window source requires.
    const instance = try vkb.createInstance(&.{
        .enabled_extension_count = @intCast(exts.len),
        .pp_enabled_extension_names = exts.ptr,
    }, null);
    const vki = vk.InstanceWrapper.load(instance, volk.getInstanceProcAddr());
    defer vki.destroyInstance(instance, null);

    // 3. Turn a window's raw OS handle into a surface — no windowing import.
    const surface = try vk_stack.createX11Surface(instance, x11_display, x11_window);
    defer vki.destroySurfaceKHR(instance, surface, null);

    // ... pick a physical device, create a Device, swapchain, render ...
}
```

`x11_display` / `x11_window` / `exts` come from *any* window source — the
companion [platform adapter](https://github.com/SETA1609/zig-cpp-platform-stack-adapter)
(`getX11Handle` + `requiredVulkanInstanceExtensions`), SDL directly, or raw X11.
This library imports no windowing layer.

## 4. What works today vs. what traps

Real now: the **`vk`** re-export (full typed API — usable immediately), the
**`volk`** loader (`loadBase` / `getInstanceProcAddr`), and the **X11 + Wayland**
surface creators.

Still `@panic("not implemented")` — **don't call yet**: **VMA**
(`vma.createBuffer`/… — needs the C++ bridge), **shaderc** (`compile`/…), and
the **Win32 / Android** surface creators. See [`ROADMAP.md`](ROADMAP.md).

Until VMA lands you can allocate memory with raw `vk` calls; until shaderc lands,
embed precompiled SPIR-V (e.g. `@embedFile` a `.spv`).

## 5. Note on dispatch (volk × vulkan-zig)

`volk` only does the *loading* (dynamically open `libvulkan`, get
`vkGetInstanceProcAddr`). The *typed dispatch* is vulkan-zig's
`BaseWrapper`/`InstanceWrapper`/`DeviceWrapper` — build a `DeviceWrapper` for
hot paths so device calls skip the instance indirection. `volk.loadInstance` /
`loadDevice` are no-ops in this implementation (the wrappers own loading).

## Next

- [`api.md`](api.md) — full signatures + error sets · [`vulkan-cheat-sheet.md`](vulkan-cheat-sheet.md) — how Vulkan works
- [`manual-testing.md`](manual-testing.md) — e2e procedures (validation-clean) · [`CONTRIBUTING.md`](../CONTRIBUTING.md) — implementing the bridges
