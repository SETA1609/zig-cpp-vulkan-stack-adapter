"""
End-of-work cleanup of Zig build caches inside the repo.
Only `devops clean` uses this, and only when the user asks for it or says the work is finished.
"""

from __future__ import annotations

import os
import shutil
from collections.abc import Sequence
from pathlib import Path

from devops.constants import (
    PROTECTED_RELATIVE_DIRECTORIES,
    ZIG_BUILD_CACHE_DIRECTORY_NAMES,
)
from devops.exceptions import ZigCleanupRefusedError


def list_default_zig_cache_paths(repository_root: Path) -> list[Path]:
    return [repository_root / directory_name for directory_name in ZIG_BUILD_CACHE_DIRECTORY_NAMES]


def select_zig_cache_paths_to_remove(
    repository_root: Path, candidate_paths: Sequence[Path]
) -> list[Path]:
    """
    Return the candidates that exist, in order. Refuse the whole set if any is unsafe.
    Unsafe: outside the repo (after resolving `..` and symlinks in parent directories), the
    repo root itself, a symlink, or inside `.git/` or `cache/logs/`.
    """
    resolved_root = repository_root.resolve()
    selected_paths: list[Path] = []
    for candidate_path in candidate_paths:
        # Resolve the parent but keep the last component, so a symlinked cache dir is caught
        # below instead of being followed. `.` and `..` have no last component to keep.
        if candidate_path.name in ("", ".", ".."):
            resolved_candidate = candidate_path.resolve()
        else:
            resolved_candidate = candidate_path.parent.resolve() / candidate_path.name
        if (
            not resolved_candidate.is_relative_to(resolved_root)
            or resolved_candidate == resolved_root
        ):
            raise ZigCleanupRefusedError(f"refusing {candidate_path}: not inside {resolved_root}")
        relative_candidate = resolved_candidate.relative_to(resolved_root)
        for protected_directory in PROTECTED_RELATIVE_DIRECTORIES:
            if relative_candidate.is_relative_to(protected_directory):
                raise ZigCleanupRefusedError(
                    f"refusing {candidate_path}: {protected_directory}/ is never cleaned"
                )
        if resolved_candidate.is_symlink():
            raise ZigCleanupRefusedError(f"refusing {candidate_path}: it is a symlink")
        if resolved_candidate.exists():
            selected_paths.append(resolved_candidate)
    return selected_paths


def measure_directory_size_bytes(directory_path: Path) -> int:
    """
    Sum of file sizes under `directory_path`, not following symlinks.
    """
    total_bytes = 0
    for walk_root, _, file_names in os.walk(directory_path):
        for file_name in file_names:
            total_bytes += (Path(walk_root) / file_name).lstat().st_size
    return total_bytes


def remove_directory_tree(directory_path: Path) -> None:
    shutil.rmtree(directory_path)
