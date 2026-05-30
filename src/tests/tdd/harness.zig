//! Shared helper for the ordered TDD suite (`src/tests/tdd/`).
//!
//! Every test calls `try gate(done.<fn>)` first: until you flip that function's
//! `done` flag to `true`, the test **skips**; once flipped it **must pass** (the
//! definition of done). See `CONTRIBUTING.md`.

/// Skip a test until the function it covers is implemented.
pub fn gate(implemented: bool) error{SkipZigTest}!void {
    if (!implemented) return error.SkipZigTest;
}
