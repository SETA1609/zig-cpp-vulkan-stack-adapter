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

/// Which shader stage the source is compiled for. The ray-tracing and mesh
/// stages need a `target` of at least `.vulkan_1_2` / `.vulkan_1_3` and the
/// matching GLSL extension in the source.
pub const Stage = enum(u8) {
    vertex,
    fragment,
    compute,
    geometry,
    tess_control,
    tess_eval,
    // ray tracing (since v0.4.x)
    raygen,
    any_hit,
    closest_hit,
    miss,
    intersection,
    callable,
    // mesh pipeline (since v0.4.x)
    task,
    mesh,
};

/// SPIR-V optimization level applied during compilation.
pub const OptimizeLevel = enum(u8) { none, size, performance };

/// The Vulkan environment to target — selects the emitted SPIR-V version and
/// which features (ray tracing, mesh shaders) the compiler accepts.
pub const SpirvVersion = enum(u8) { vulkan_1_0, vulkan_1_1, vulkan_1_2, vulkan_1_3 };

/// A preprocessor macro definition (`-D`). `value == null` defines it with no
/// replacement (a bare `#define NAME`).
pub const Macro = struct { name: []const u8, value: ?[]const u8 = null };

/// The contents of a resolved `#include`, returned by an `Includer`.
pub const IncludeResult = struct {
    /// A name for the included source (e.g. its path) — used to resolve nested
    /// includes and to label errors. Borrowed for the duration of the compile.
    name: []const u8,
    /// The included GLSL. Borrowed for the duration of the compile.
    content: []const u8,
};

/// Resolves `#include` directives. `resolve` returns the included source, or
/// `null` if it can't be found (the compile then fails with a diagnostic).
pub const Includer = struct {
    /// Opaque caller context handed back to `resolve` (e.g. an include map).
    ctx: ?*anyopaque = null,
    /// `requested` is the text inside the `#include`; `requesting` is the name
    /// of the file doing the including (for relative resolution).
    resolve: *const fn (ctx: ?*anyopaque, requested: []const u8, requesting: []const u8) ?IncludeResult,
};

/// Knobs for a single `compile` call.
pub const CompileOptions = struct {
    optimize: OptimizeLevel = .performance,
    debug_info: bool = false,
    entry_point: [:0]const u8 = "main",
    /// Vulkan environment to target (drives the SPIR-V version). *(since v0.4.x)*
    target: SpirvVersion = .vulkan_1_3,
    /// Preprocessor macros to define before compiling. *(since v0.4.x)*
    macros: []const Macro = &.{},
    /// Resolver for `#include` directives, or `null` to reject all includes.
    /// *(since v0.4.x)*
    includer: ?Includer = null,
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

    // Per-compile context for the include callbacks (shaderc hands back one
    // `void*`). Lives on `compile`'s stack — valid for the whole synchronous call.
    const IncludeCtx = struct { includer: Includer, allocator: std.mem.Allocator };

    // One resolved include + its owned strings, so the release callback can free.
    const ResultBox = struct {
        res: c.shaderc_include_result,
        name: []u8,
        content: []u8,
        allocator: std.mem.Allocator,
    };

    const oom_msg = "shaderc include resolver: out of memory";
    var oom_result = c.shaderc_include_result{
        .source_name = "",
        .source_name_length = 0,
        .content = oom_msg,
        .content_length = oom_msg.len,
        .user_data = null,
    };

    fn includeResolve(
        user_data: ?*anyopaque,
        requested_source: [*c]const u8,
        include_type: c_int,
        requesting_source: [*c]const u8,
        include_depth: usize,
    ) callconv(.c) [*c]c.shaderc_include_result {
        _ = include_type;
        _ = include_depth;
        const ictx: *IncludeCtx = @ptrCast(@alignCast(user_data.?));
        const requested = std.mem.span(requested_source);
        const requesting = std.mem.span(requesting_source);

        const box = ictx.allocator.create(ResultBox) catch return &oom_result;
        box.allocator = ictx.allocator;
        if (ictx.includer.resolve(ictx.includer.ctx, requested, requesting)) |inc| {
            box.name = ictx.allocator.dupe(u8, inc.name) catch {
                ictx.allocator.destroy(box);
                return &oom_result;
            };
            box.content = ictx.allocator.dupe(u8, inc.content) catch {
                ictx.allocator.free(box.name);
                ictx.allocator.destroy(box);
                return &oom_result;
            };
        } else {
            // Empty source_name signals "not found"; content carries the error.
            box.name = ictx.allocator.dupe(u8, "") catch {
                ictx.allocator.destroy(box);
                return &oom_result;
            };
            box.content = std.fmt.allocPrint(ictx.allocator, "'{s}': include not found", .{requested}) catch {
                ictx.allocator.free(box.name);
                ictx.allocator.destroy(box);
                return &oom_result;
            };
        }
        box.res = .{
            .source_name = box.name.ptr,
            .source_name_length = box.name.len,
            .content = box.content.ptr,
            .content_length = box.content.len,
            .user_data = box,
        };
        return &box.res;
    }

    fn includeRelease(user_data: ?*anyopaque, include_result: [*c]c.shaderc_include_result) callconv(.c) void {
        _ = user_data;
        if (@intFromPtr(include_result) == @intFromPtr(&oom_result)) return;
        const box: *ResultBox = @ptrCast(@alignCast(include_result.*.user_data.?));
        box.allocator.free(box.name);
        box.allocator.free(box.content);
        box.allocator.destroy(box);
    }

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

        c.shaderc_compile_options_set_target_env(options, c.shaderc_target_env_vulkan, switch (opts.target) {
            .vulkan_1_0 => c.shaderc_env_version_vulkan_1_0,
            .vulkan_1_1 => c.shaderc_env_version_vulkan_1_1,
            .vulkan_1_2 => c.shaderc_env_version_vulkan_1_2,
            .vulkan_1_3 => c.shaderc_env_version_vulkan_1_3,
        });

        for (opts.macros) |m| {
            const v = if (m.value) |val| val.ptr else null;
            const vlen = if (m.value) |val| val.len else 0;
            c.shaderc_compile_options_add_macro_definition(options, m.name.ptr, m.name.len, v, vlen);
        }

        var include_ctx: IncludeCtx = undefined;
        if (opts.includer) |inc| {
            include_ctx = .{ .includer = inc, .allocator = allocator };
            c.shaderc_compile_options_set_include_callbacks(options, includeResolve, includeRelease, &include_ctx);
        }

        const kind = switch (stage) {
            .vertex => c.shaderc_glsl_vertex_shader,
            .fragment => c.shaderc_glsl_fragment_shader,
            .compute => c.shaderc_glsl_compute_shader,
            .geometry => c.shaderc_glsl_geometry_shader,
            .tess_control => c.shaderc_glsl_tess_control_shader,
            .tess_eval => c.shaderc_glsl_tess_evaluation_shader,
            .raygen => c.shaderc_glsl_raygen_shader,
            .any_hit => c.shaderc_glsl_anyhit_shader,
            .closest_hit => c.shaderc_glsl_closesthit_shader,
            .miss => c.shaderc_glsl_miss_shader,
            .intersection => c.shaderc_glsl_intersection_shader,
            .callable => c.shaderc_glsl_callable_shader,
            .task => c.shaderc_glsl_task_shader,
            .mesh => c.shaderc_glsl_mesh_shader,
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
