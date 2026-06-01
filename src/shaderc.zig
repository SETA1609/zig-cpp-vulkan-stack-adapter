//! GLSL → SPIR-V compilation (shaderc).
//!
//! shaderc ships a **C** API, so this is a pure-Zig `@cImport` wrapper — no C++
//! bridge (unlike VMA). shaderc + glslang + SPIRV-Tools are built from source by
//! the `tiawl/shaderc.zig` package and linked **only** when you build with
//! `-Dshaderc` (a lazy dependency). Without it, the stack stays lean and
//! `compile` traps — embed precompiled SPIR-V (`@embedFile`) instead. See
//! `docs/shaderc-distribution.md`. *(since v0.4.0)*

const std = @import("std");

/// `true` when the library was built with `-Dshaderc` (shaderc linked in).
/// Branch on this to choose runtime compilation vs. embedded SPIR-V.
pub const available = @import("build_config").have_shaderc;

/// Which shader stage the source is compiled for.
pub const Stage = enum(u8) { vertex, fragment, compute, geometry, tess_control, tess_eval };

/// SPIR-V optimization level applied during compilation.
pub const OptimizeLevel = enum(u8) { none, size, performance };

/// Knobs for a single `compile` call.
pub const CompileOptions = struct {
    optimize: OptimizeLevel = .performance,
    debug_info: bool = false,
    entry_point: [:0]const u8 = "main",
};

/// Errors `compile` can return.
pub const Error = error{
    /// The GLSL failed to compile; pass a `*Diagnostics` to `compile` for the log.
    ShaderCompilationFailed,
    /// Allocation of the result (or an internal buffer) failed.
    OutOfMemory,
};

/// On a failed `compile`, the compiler's error/warning log. Pass a pointer to
/// receive it — `message` is **allocator-owned** (free it with the same
/// allocator) — or pass `null` to ignore it. Replaces a global "last error".
pub const Diagnostics = struct { message: []u8 = &.{} };

/// Compile GLSL `source` for `stage` into SPIR-V **words** (`u32`), allocated
/// with `allocator` and owned by the caller (free it). On
/// `error.ShaderCompilationFailed`, if `diagnostics` is non-null its `message`
/// is filled with the compiler log. *(since v0.4.0)*
pub fn compile(
    allocator: std.mem.Allocator,
    source: []const u8,
    stage: Stage,
    opts: CompileOptions,
    diagnostics: ?*Diagnostics,
) Error![]u32 {
    return backend.compile(allocator, source, stage, opts, diagnostics);
}

const backend = if (available) struct {
    const c = @cImport({
        @cInclude("shaderc/shaderc.h");
    });

    fn compile(allocator: std.mem.Allocator, source: []const u8, stage: Stage, opts: CompileOptions, diagnostics: ?*Diagnostics) Error![]u32 {
        const compiler = c.shaderc_compiler_initialize() orelse return Error.OutOfMemory;
        defer c.shaderc_compiler_release(compiler);
        const options = c.shaderc_compile_options_initialize() orelse return Error.OutOfMemory;
        defer c.shaderc_compile_options_release(options);

        c.shaderc_compile_options_set_optimization_level(options, switch (opts.optimize) {
            .none => c.shaderc_optimization_level_zero,
            .size => c.shaderc_optimization_level_size,
            .performance => c.shaderc_optimization_level_performance,
        });
        if (opts.debug_info) c.shaderc_compile_options_set_generate_debug_info(options);

        const kind = switch (stage) {
            .vertex => c.shaderc_glsl_vertex_shader,
            .fragment => c.shaderc_glsl_fragment_shader,
            .compute => c.shaderc_glsl_compute_shader,
            .geometry => c.shaderc_glsl_geometry_shader,
            .tess_control => c.shaderc_glsl_tess_control_shader,
            .tess_eval => c.shaderc_glsl_tess_evaluation_shader,
        };

        const result = c.shaderc_compile_into_spv(
            compiler,
            source.ptr,
            source.len,
            @intCast(kind),
            "input",
            opts.entry_point.ptr,
            options,
        ) orelse return Error.OutOfMemory;
        defer c.shaderc_result_release(result);

        if (c.shaderc_result_get_compilation_status(result) != c.shaderc_compilation_status_success) {
            if (diagnostics) |d| {
                const msg = std.mem.span(c.shaderc_result_get_error_message(result));
                d.message = try allocator.dupe(u8, msg);
            }
            return Error.ShaderCompilationFailed;
        }

        const len = c.shaderc_result_get_length(result);
        const bytes = c.shaderc_result_get_bytes(result);
        const out = try allocator.alloc(u32, len / 4);
        @memcpy(std.mem.sliceAsBytes(out), bytes[0..len]);
        return out;
    }
} else struct {
    fn compile(allocator: std.mem.Allocator, source: []const u8, stage: Stage, opts: CompileOptions, diagnostics: ?*Diagnostics) Error![]u32 {
        _ = .{ allocator, source, stage, opts, diagnostics };
        @panic("shaderc not built — rebuild with `-Dshaderc` (see docs/shaderc-distribution.md)");
    }
};

test {
    std.testing.refAllDecls(@This());
}
