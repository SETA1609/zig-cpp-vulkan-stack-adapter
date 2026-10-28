from pathlib import Path

import pytest

from devops.exceptions import ZigCleanupRefusedError
from devops.zig_cleanup import (
    list_default_zig_cache_paths,
    measure_directory_size_bytes,
    select_zig_cache_paths_to_remove,
)


def write_file_of_size(file_path: Path, size_bytes: int) -> None:
    file_path.parent.mkdir(parents=True, exist_ok=True)
    file_path.write_bytes(b"x" * size_bytes)


def test_select_zig_cache_paths_to_remove_returns_the_existing_default_paths(tmp_path):
    (tmp_path / "zig-pkg").mkdir()
    (tmp_path / "zig-out").mkdir()
    (tmp_path / ".zig-cache").mkdir()
    selected_paths = select_zig_cache_paths_to_remove(
        tmp_path, list_default_zig_cache_paths(tmp_path)
    )
    assert selected_paths == [
        tmp_path.resolve() / "zig-out",
        tmp_path.resolve() / ".zig-cache",
        tmp_path.resolve() / "zig-pkg",
    ]


def test_select_zig_cache_paths_to_remove_skips_paths_that_do_not_exist(tmp_path):
    (tmp_path / ".zig-cache").mkdir()
    selected_paths = select_zig_cache_paths_to_remove(
        tmp_path, list_default_zig_cache_paths(tmp_path)
    )
    assert selected_paths == [tmp_path.resolve() / ".zig-cache"]


def test_select_zig_cache_paths_to_remove_refuses_a_path_outside_the_repository(tmp_path):
    repository_root = tmp_path / "repo"
    repository_root.mkdir()
    (tmp_path / "zig-out").mkdir()
    with pytest.raises(ZigCleanupRefusedError, match="not inside"):
        select_zig_cache_paths_to_remove(repository_root, [repository_root / ".." / "zig-out"])


def test_select_zig_cache_paths_to_remove_refuses_the_repository_root(tmp_path):
    with pytest.raises(ZigCleanupRefusedError, match="not inside"):
        select_zig_cache_paths_to_remove(tmp_path, [tmp_path / "sub" / ".."])


def test_select_zig_cache_paths_to_remove_refuses_a_path_reached_through_a_symlinked_parent(
    tmp_path,
):
    repository_root = tmp_path / "repo"
    outside_directory = tmp_path / "outside"
    (outside_directory / "zig-out").mkdir(parents=True)
    repository_root.mkdir()
    (repository_root / "linked").symlink_to(outside_directory)
    with pytest.raises(ZigCleanupRefusedError, match="not inside"):
        select_zig_cache_paths_to_remove(repository_root, [repository_root / "linked" / "zig-out"])


def test_select_zig_cache_paths_to_remove_refuses_a_symlink(tmp_path):
    (tmp_path / "real-cache").mkdir()
    (tmp_path / ".zig-cache").symlink_to(tmp_path / "real-cache")
    with pytest.raises(ZigCleanupRefusedError, match="symlink"):
        select_zig_cache_paths_to_remove(tmp_path, [tmp_path / ".zig-cache"])


@pytest.mark.parametrize("protected_path", [".git", ".git/objects", "cache/logs", "cache/logs/x"])
def test_select_zig_cache_paths_to_remove_refuses_protected_directories(tmp_path, protected_path):
    (tmp_path / protected_path).mkdir(parents=True)
    with pytest.raises(ZigCleanupRefusedError, match="never cleaned"):
        select_zig_cache_paths_to_remove(tmp_path, [tmp_path / protected_path])


def test_select_zig_cache_paths_to_remove_refuses_the_whole_set_when_one_path_is_unsafe(tmp_path):
    (tmp_path / "zig-out").mkdir()
    (tmp_path / ".git").mkdir()
    with pytest.raises(ZigCleanupRefusedError):
        select_zig_cache_paths_to_remove(tmp_path, [tmp_path / "zig-out", tmp_path / ".git"])


def test_measure_directory_size_bytes_sums_files_without_following_symlinks(tmp_path):
    write_file_of_size(tmp_path / "cache" / "a", 10)
    write_file_of_size(tmp_path / "cache" / "nested" / "b", 32)
    write_file_of_size(tmp_path / "big-outside", 4096)
    (tmp_path / "cache" / "link").symlink_to(tmp_path / "big-outside")
    link_size_bytes = (tmp_path / "cache" / "link").lstat().st_size
    assert measure_directory_size_bytes(tmp_path / "cache") == 42 + link_size_bytes
