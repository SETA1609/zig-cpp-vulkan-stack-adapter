//! Aggregator for the ordered TDD suite — `zig build test-tdd` runs every file
//! referenced here. Only shaderc is unit-testable in-process; the volk / VMA /
//! surface-creator functions need a live Vulkan device and are verified by the
//! e2e procedures in `docs/manual-testing.md`. See `CONTRIBUTING.md`.
//!
//! All tests skip by default and turn on per-function via the `done` flags at
//! the top of each file — so this step is **green (all skipped)** until a
//! contributor implements a function and flips its flag.

test {
    _ = @import("01_shaderc_test.zig");
    _ = @import("02_volk_test.zig");
    _ = @import("03_vma_test.zig");
    _ = @import("04_vma_advanced_test.zig");
    _ = @import("05_shaderc_advanced_test.zig");
}
