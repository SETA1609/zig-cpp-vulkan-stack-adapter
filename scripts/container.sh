#!/usr/bin/env bash
# Run a devops subcommand against the Zig 0.17 toolchain container (needs uv and docker or podman).
# Output is timestamped and logged to cache/logs/. Usage: ./scripts/container.sh <subcommand> [args...]
#   ./scripts/container.sh image | build | test | zig | ci | tdd | shell | prune | clean
set -euo pipefail
exec uv run --project "$(dirname "$0")/../tools/devops" --locked --no-dev --quiet devops "$@"
