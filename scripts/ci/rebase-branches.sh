#!/usr/bin/env bash
# Rebase all feature/* branches onto the target branch (default: dev).
# Runs on push to dev — keeps feature branches up to date.
# Branches with conflicts are SKIPPED (rebase aborted, not force-pushed).
set -euo pipefail

TARGET="${1:-dev}"

git fetch origin --prune

CURRENT=$(git rev-parse --abbrev-ref HEAD)

for branch in $(git branch -r | grep -E 'origin/feature/' | sed 's|origin/||'); do
    echo "==> Rebase: $branch onto $TARGET ..."

    git checkout -q "$branch" 2>/dev/null || git checkout -q -b "$branch" "origin/$branch"

    if git rebase "origin/$TARGET"; then
        git push origin "$branch" --force-with-lease 2>&1 | grep -v "Everything up-to-date" || true
        echo "  ✅ $branch rebased and pushed"
    else
        echo "  ❌ $branch has conflicts — aborting, branch left alone"
        git rebase --abort
    fi
done

git checkout -q "$CURRENT"
