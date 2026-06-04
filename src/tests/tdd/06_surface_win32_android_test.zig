//! Ladder step 6 — **Win32 + Android surface creators** (`createWin32Surface` /
//! `createAndroidSurface`). *(v0.5.0)* The live "a real surface is created"
//! path needs the actual OS (`HWND` / `ANativeWindow*`) and so is a device e2e
//! in `docs/manual-testing.md`; the X11 + Wayland creators already cover the
//! behavioral path on Linux. What *is* provable here in-process — and what
//! these tests pin — is the **public contract**: each creator takes raw OS
//! primitives (no windowing type) and returns `SurfaceError!vk.SurfaceKHR`,
//! exhaustively `switch`-able. A signature drift fails to compile. See
//! `CONTRIBUTING.md`.

const std = @import("std");
const vk_stack = @import("vulkan_stack");
const vk = @import("vulkan");
const h = @import("harness.zig");
const gate = h.gate;

const SurfaceError = vk_stack.SurfaceError;

const done = .{
    .createWin32Surface = false,
    .createAndroidSurface = false,
};

// --- createWin32Surface ----------------------------------------------------

// WHEN inspecting createWin32Surface's type · GIVEN the surface API · THEN it is `fn (vk.Instance, *anyopaque hinstance, *anyopaque hwnd) SurfaceError!vk.SurfaceKHR` (raw primitives in, no windowing type).
test "createWin32Surface: takes raw HINSTANCE+HWND, returns SurfaceError!SurfaceKHR" {
    try gate(done.createWin32Surface);
    // Coercing to the expected function-pointer type pins the contract: any
    // drift in params or return type is a compile error.
    const expected: *const fn (vk.Instance, *anyopaque, *anyopaque) SurfaceError!vk.SurfaceKHR = vk_stack.createWin32Surface;
    _ = expected;
}

// WHEN exhaustively switching createWin32Surface's error set · GIVEN SurfaceError · THEN every member is handled (a new error would fail to compile).
test "createWin32Surface: error set is SurfaceError (exhaustively switchable)" {
    try gate(done.createWin32Surface);
    const err: SurfaceError = SurfaceError.SurfaceCreationFailed;
    switch (err) {
        SurfaceError.OutOfHostMemory,
        SurfaceError.OutOfDeviceMemory,
        SurfaceError.SurfaceCreationFailed,
        => {},
    }
}

// --- createAndroidSurface --------------------------------------------------

// WHEN inspecting createAndroidSurface's type · GIVEN the surface API · THEN it is `fn (vk.Instance, *anyopaque window) SurfaceError!vk.SurfaceKHR` (a raw `ANativeWindow*`).
test "createAndroidSurface: takes a raw ANativeWindow*, returns SurfaceError!SurfaceKHR" {
    try gate(done.createAndroidSurface);
    const expected: *const fn (vk.Instance, *anyopaque) SurfaceError!vk.SurfaceKHR = vk_stack.createAndroidSurface;
    _ = expected;
}
