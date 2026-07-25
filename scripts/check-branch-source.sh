#!/usr/bin/env bash
set -euo pipefail

TARGET="$1"
SOURCE="$2"
errors=0

if [ "$TARGET" = "main" ] && [ "$SOURCE" != "dev" ]; then
    echo "::error::PRs targeting 'main' must come from 'dev', not '$SOURCE'"
    errors=$((errors + 1))
fi

if [ "$TARGET" = "dev" ] && [ "$SOURCE" = "main" ]; then
    echo "::error::PRs targeting 'dev' must not come from 'main'"
    errors=$((errors + 1))
fi

if [ "$errors" -gt 0 ]; then
    exit 1
fi

echo "✅ $SOURCE → $TARGET is valid"
