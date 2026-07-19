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
