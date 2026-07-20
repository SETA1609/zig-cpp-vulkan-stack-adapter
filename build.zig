//! Root build entry point for the **vulkan-stack adapter**.
//!
//! Delegates to `build/modules.zig` (module + library + VMA bridge + optional
//! shaderc), `build/tests.zig` (unit + TDD test steps), and `build/dev.zig`
//! (smoke demo + pipeline step).
//!
//! ## Build steps
//!
//! | Command | Target |
//! |---------|--------|
//! | `zig build` | `pipeline` — build the static library |
//! | `zig build test` | Run the contract unit tests |
//! | `zig build test-tdd` | Run the red→green TDD suite |
//! | `zig build run` | Build + run the smoke demo |
//!
//! ## Flags
//!
//! - `-Dtarget=<triple>` — cross-compile target (default: host)
//! - `-Doptimize=<mode>` — Debug / ReleaseFast / ReleaseSafe / ReleaseSmall
//! - `-Dshaderc` — include runtime GLSL→SPIR-V compilation (fetches + builds shaderc from source)

const std = @import("std");

const modules = @import("build/modules.zig");
const tests = @import("build/tests.zig");
const dev = @import("build/dev.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const m = modules.create(b, target, optimize);
    const t = tests.create(b, target, optimize, m);
    dev.create(b, target, optimize, m, t);
}
