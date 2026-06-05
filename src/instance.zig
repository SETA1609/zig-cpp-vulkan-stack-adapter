//! **Opt-in `Instance` bootstrap helper** (v0.7.0) — the first of the
//! `vk-bootstrap`-style setup helpers. Folds the instance-creation boilerplate
//! (api version, merging the consumer's required surface extensions with the
//! validation / debug-utils / portability-enumeration ones, enabling layers in
//! debug, then loading the instance dispatch) behind one opt-in call.
//!
//! Raw `vk` is **never blocked**: a consumer can build their own
//! `vk.InstanceCreateInfo` and call `vkb.createInstance` directly, with this
//! module unreferenced and tree-shaken out. The escape hatch is
//! `selectExtensions` — it computes the exact extension list `create` would use
//! **without** creating anything, so a consumer drives Vulkan themselves.
//!
//! Boundary rule: no helper type appears in a raw signature; the required
//! surface extensions come in as raw `[*:0]const u8` names (e.g. from the
//! platform adapter's `requiredVulkanInstanceExtensions()`), so no windowing
//! type is imported here. All bodies `@panic` until v0.7.0 lands — see
//! `docs/ROADMAP.md`.

const std = @import("std");
const vk = @import("vulkan");

/// Errors `Instance` operations can return — explicit and exhaustively
/// `switch`-able, like the rest of this library's public surface.
pub const Error = error{
    OutOfHostMemory,
    OutOfDeviceMemory,
    InitializationFailed,
    LayerNotPresent,
    ExtensionNotPresent,
    IncompatibleDriver,
    OutOfMemory,
};

pub const Instance = struct {
    handle: vk.Instance,
    /// The Vulkan API version actually requested (e.g. 1.3).
    api_version: u32,
    /// Owned. The full extension set enabled (required + the options' implied ones).
    enabled_extensions: [][*:0]const u8,
    /// Owned. The layers enabled (validation, when requested).
    enabled_layers: [][*:0]const u8,
    /// The loaded instance-level dispatch for `handle`.
    vki: vk.InstanceWrapper,

    /// Consumer preferences. Defaults target a debug-friendly 1.3 instance.
    pub const Options = struct {
        application_name: [*:0]const u8 = "vulkan-stack app",
        application_version: u32 = 0,
        engine_name: [*:0]const u8 = "vulkan-stack",
        engine_version: u32 = 0,
        /// Minimum Vulkan version to request — 1.3 matches what volk/VMA expect.
        api_version: u32 = @bitCast(vk.API_VERSION_1_3),
        /// Surface/platform extensions the consumer requires — raw names, e.g.
        /// from the platform adapter's `requiredVulkanInstanceExtensions()`.
        /// No windowing type crosses here.
        required_extensions: []const [*:0]const u8 = &.{},
        /// Enable the Khronos validation layer + `VK_EXT_debug_utils`.
        enable_validation: bool = false,
        /// Extra layers beyond validation.
        extra_layers: []const [*:0]const u8 = &.{},
    };

    /// **Beginner tier.** Merge `required_extensions` with the options' implied
    /// extensions (debug-utils when validating; portability-enumeration where
    /// the loader needs it), create the instance, and load its dispatch. Caller
    /// owns it — release with `deinit`. *(since v0.7.0)*
    pub fn create(gpa: std.mem.Allocator, vkb: vk.BaseWrapper, options: Options) Error!Instance {
        _ = gpa;
        _ = vkb;
        _ = options;
        @panic("not implemented");
    }

    /// Destroy the instance and free the owned extension/layer slices.
    /// *(since v0.7.0)*
    pub fn deinit(self: *Instance, gpa: std.mem.Allocator) void {
        _ = self;
        _ = gpa;
        @panic("not implemented");
    }

    /// **Bridge.** The raw `vk.Instance` handle, for driving Vulkan directly
    /// (the loaded dispatch is the `vki` field). *(since v0.7.0)*
    pub fn toRaw(self: Instance) vk.Instance {
        _ = self;
        @panic("not implemented");
    }

    /// **Pro tier.** Compute the exact extension list `create` would enable
    /// (required + validation/debug/portability), owned by `gpa` — the consumer
    /// builds its own `vk.InstanceCreateInfo` and calls `vkb.createInstance`.
    /// Creates no instance. *(since v0.7.0)*
    pub fn selectExtensions(gpa: std.mem.Allocator, options: Options) Error![][*:0]const u8 {
        _ = gpa;
        _ = options;
        @panic("not implemented");
    }
};
