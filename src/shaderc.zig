//! GLSL → SPIR-V compilation (shaderc).
//!
//! shaderc ships a **C** API (`shaderc/shaderc.h`), so this wrapper is pure
//! Zig over that C entry point — no C++ bridge needed (unlike VMA). Consumers
//! that don't need *runtime* compilation can skip this entirely and embed
//! precompiled SPIR-V instead. *(since v0.4.0)*

const std = @import("std");

/// Which shader stage the source is compiled for — selects the SPIR-V
/// execution model and the built-ins available to the shader.
pub const Stage = enum(u8) {
    /// Vertex shader.
    vertex,
    /// Fragment / pixel shader.
    fragment,
    /// Compute shader.
    compute,
    /// Geometry shader.
    geometry,
    /// Tessellation control (hull) shader.
    tess_control,
    /// Tessellation evaluation (domain) shader.
    tess_eval,
};

/// SPIR-V optimization level applied during compilation.
pub const OptimizeLevel = enum(u8) {
    /// No optimization — fastest compile, most debuggable output.
    none,
    /// Optimize for smaller SPIR-V binary size.
    size,
    /// Optimize for runtime performance (default).
    performance,
};

/// Knobs for a single `compile` call.
pub const CompileOptions = struct {
    /// Optimization level for the emitted SPIR-V.
    optimize: OptimizeLevel = .performance,
    /// Emit OpLine/OpSource debug info (larger output; useful for tooling).
    debug_info: bool = false,
    /// Entry-point name to compile against.
    entry_point: [:0]const u8 = "main",
};

/// Errors `compile` can return.
pub const Error = error{
    /// The GLSL failed to compile; call `lastErrorMessage` for the diagnostic.
    ShaderCompilationFailed,
    /// Allocation of the result (or an internal buffer) failed.
    OutOfMemory,
};

/// Compile GLSL `source` for `stage` into SPIR-V **words** (`u32`). The
/// returned slice is allocated with `allocator` and owned by the caller —
/// free it with the same allocator. On failure, inspect `lastErrorMessage`.
/// *(since v0.4.0)*
pub fn compile(allocator: std.mem.Allocator, source: []const u8, stage: Stage, opts: CompileOptions) Error![]u32 {
    _ = allocator;
    _ = source;
    _ = stage;
    _ = opts;
    @panic("not implemented");
}

/// The human-readable diagnostic for the most recent failed `compile`
/// (compiler errors/warnings). Borrowed; valid until the next `compile`.
/// *(since v0.4.0)*
pub fn lastErrorMessage() []const u8 {
    @panic("not implemented");
}

test {
    std.testing.refAllDecls(@This());
}
