#!/usr/bin/env bash
# The CI gates, runnable locally — the same checks .github/workflows/build.yml
# runs (it installs the toolchain / clang-format-18 / Vulkan ICD, then calls
# this with the matching command).
#   ./scripts/ci.sh                # fmt + build + smoke demo + contract tests
#   ./scripts/ci.sh clang-format   # C++ bridge style (src/c) — needs clang-format-18
#   ./scripts/ci.sh shaderc        # build with -Dshaderc (lazy glslang from source)
#   ./scripts/ci.sh device-tests   # test-tdd -Dshaderc (needs a Vulkan ICD; lavapipe in CI)
set -uo pipefail
cd "$(dirname "$0")/.."

case "${1:-check}" in
  check)
    echo "== zig fmt --check =="; zig fmt --check build.zig build.zig.zon src demo || exit 1
    echo "== zig build =="; zig build || exit 1
    echo "== zig build run (pure-data smoke demo) =="; zig build run || exit 1
    echo "== zig build test (contract) =="; zig build test || exit 1
    ;;
  clang-format)
    cf="${CLANG_FORMAT:-clang-format-18}"
    command -v "$cf" >/dev/null 2>&1 || cf=clang-format
    echo "== $cf --dry-run -Werror src/c =="
    "$cf" --dry-run -Werror src/c/*.h src/c/*.cpp || exit 1
    ;;
  shaderc)
    echo "== zig build -Dshaderc (builds shaderc + glslang from source) =="
    zig build -Dshaderc || exit 1
    ;;
  device-tests)
    echo "== zig build test-tdd -Dshaderc (needs a Vulkan ICD — lavapipe in CI) =="
    zig build test-tdd -Dshaderc || exit 1
    ;;
  *)
    echo "unknown command: $1 (try: check | clang-format | shaderc | device-tests)" >&2
    exit 2
    ;;
esac
echo "ok: ${1:-check}"
