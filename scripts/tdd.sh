#!/usr/bin/env bash
# Run the gated red→green TDD suite. Optional arg = --test-filter substring.
#   ./scripts/tdd.sh                  # whole suite
#   ./scripts/tdd.sh "createAllocator"  # just matching tests (full output, panics shown)
set -uo pipefail
cd "$(dirname "$0")/.."
if [ -n "${1:-}" ]; then
    zig build test-tdd --summary all -- --test-filter "$1" 2>&1
else
    zig build test-tdd --summary all 2>&1 | grep -iE "run test|build summary|error:|expected.*found|panic|failed:"
fi
