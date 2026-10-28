from pathlib import Path

import pytest

from devops.constants import (
    ZIG_GLOBAL_CACHE_VOLUME_NAME,
)
from devops.container import (
    build_container_run_arguments,
    build_image_build_arguments,
    build_zig_cache_volume_chown_arguments,
    check_zig_version_matches_dockerfile,
    detect_container_binary,
    find_repository_root,
    split_keep_zig_cache_flag,
)
from devops.exceptions import ContainerSetupError
from devops.models import ContainerRunSettings


def write_fake_repository(root: Path, pinned_version: str, dockerfile_version: str | None) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    (root / ".zig-version").write_text(f"{pinned_version}\n")
    dockerfile_lines = ["FROM ubuntu:24.04 AS zig"]
    if dockerfile_version is not None:
        dockerfile_lines.append(f"ARG ZIG_VERSION={dockerfile_version}")
        dockerfile_lines.append("ARG ZIG_VERSION=9.9.9")
    (root / "Dockerfile").write_text("\n".join(dockerfile_lines) + "\n")
    return root


def test_check_zig_version_matches_dockerfile_returns_the_pinned_version(tmp_path):
    root = write_fake_repository(tmp_path, "0.17.0", "0.17.0")
    assert check_zig_version_matches_dockerfile(root) == "0.17.0"


def test_check_zig_version_matches_dockerfile_rejects_a_mismatch(tmp_path):
    root = write_fake_repository(tmp_path, "0.17.0", "0.16.0")
    expected_message = r"\.zig-version is 0\.17\.0 but .* pins 0\.16\.0"
    with pytest.raises(ContainerSetupError, match=expected_message):
        check_zig_version_matches_dockerfile(root)


def test_check_zig_version_matches_dockerfile_rejects_a_dockerfile_without_the_arg(tmp_path):
    root = write_fake_repository(tmp_path, "0.17.0", None)
    with pytest.raises(ContainerSetupError, match="no ARG ZIG_VERSION="):
        check_zig_version_matches_dockerfile(root)


def test_find_repository_root_walks_up_to_the_directory_with_the_toolchain_pin(tmp_path):
    root = write_fake_repository(tmp_path, "0.17.0", "0.17.0")
    nested_directory = root / "tools" / "devops" / "src" / "devops"
    nested_directory.mkdir(parents=True)
    assert find_repository_root(nested_directory) == root


def test_find_repository_root_fails_outside_the_repository(tmp_path):
    with pytest.raises(ContainerSetupError, match="repository root"):
        find_repository_root(tmp_path)


def test_detect_container_binary_prefers_docker():
    assert detect_container_binary(lambda binary: True) == "docker"


def test_detect_container_binary_falls_back_to_podman():
    assert detect_container_binary(lambda binary: binary == "podman") == "podman"


def test_detect_container_binary_fails_when_no_daemon_is_reachable():
    with pytest.raises(ContainerSetupError, match="docker or podman"):
        detect_container_binary(lambda binary: False)


def test_build_container_run_arguments_mounts_the_repository_as_the_host_user():
    arguments = build_container_run_arguments(
        ContainerRunSettings(
            container_binary="docker",
            repository_root=Path("/home/user/project"),
            image="vulkan-stack-adapter:zig-0.17.0",
            user_and_group_ids=(1000, 1000),
        ),
        ["zig", "build", "-Doptimize=ReleaseSafe"],
    )
    assert arguments == [
        "docker", "run", "--rm", "--init",
        "--user", "1000:1000",
        "-e", "HOME=/tmp/zig-home",
        "-e", "ZIG_GLOBAL_CACHE_DIR=/tmp/zig-home/cache",
        "-v", "/home/user/project:/src",
        "-w", "/src",
        "vulkan-stack-adapter:zig-0.17.0",
        "zig", "build", "-Doptimize=ReleaseSafe",
    ]  # fmt: skip


def test_build_container_run_arguments_runs_as_root_without_user_ids():
    arguments = build_container_run_arguments(
        ContainerRunSettings(
            container_binary="podman",
            repository_root=Path("/repo"),
            image="image:tag",
            user_and_group_ids=None,
        ),
        ["zig", "version"],
    )
    assert "--user" not in arguments
    assert arguments[:3] == ["podman", "run", "--rm"]


def test_build_image_build_arguments_passes_the_pinned_version():
    arguments = build_image_build_arguments(
        container_binary="docker",
        repository_root=Path("/repo"),
        image="vulkan-stack-adapter:zig-0.17.0",
        zig_version="0.17.0",
    )
    assert arguments == [
        "docker", "build",
        "--file", "/repo/Dockerfile",
        "--build-arg", "ZIG_VERSION=0.17.0",
        "--tag", "vulkan-stack-adapter:zig-0.17.0",
        "/repo",
    ]  # fmt: skip


def test_build_container_run_arguments_keeps_the_zig_cache_in_the_named_volume():
    arguments = build_container_run_arguments(
        ContainerRunSettings(
            container_binary="docker",
            repository_root=Path("/repo"),
            image="image:tag",
            user_and_group_ids=(1000, 1000),
            keep_zig_cache=True,
        ),
        ["zig", "build"],
    )
    assert arguments == [
        "docker", "run", "--rm", "--init",
        "--user", "1000:1000",
        "-e", "HOME=/tmp/zig-home",
        "-e", "ZIG_GLOBAL_CACHE_DIR=/zig-global-cache",
        "-v", "vulkan-stack-adapter-zig-cache:/zig-global-cache",
        "-v", "/repo:/src",
        "-w", "/src",
        "image:tag",
        "zig", "build",
    ]  # fmt: skip


def test_build_container_run_arguments_mounts_no_volume_without_keep_zig_cache():
    arguments = build_container_run_arguments(
        ContainerRunSettings(
            container_binary="docker",
            repository_root=Path("/repo"),
            image="image:tag",
            user_and_group_ids=None,
        ),
        ["zig", "build"],
    )
    assert not any(ZIG_GLOBAL_CACHE_VOLUME_NAME in argument for argument in arguments)


@pytest.mark.parametrize(
    ("allocate_terminal", "expected_terminal_arguments"),
    [(True, ["-i", "-t"]), (False, ["-i"])],
)
def test_build_container_run_arguments_keeps_stdin_open_for_the_shell(
    allocate_terminal, expected_terminal_arguments
):
    arguments = build_container_run_arguments(
        ContainerRunSettings(
            container_binary="docker",
            repository_root=Path("/repo"),
            image="image:tag",
            user_and_group_ids=None,
        ),
        ["bash"],
        keep_stdin_open=True,
        allocate_terminal=allocate_terminal,
    )
    expected_prefix = ["docker", "run", "--rm", "--init", *expected_terminal_arguments, "-e"]
    assert arguments[: len(expected_prefix)] == expected_prefix


@pytest.mark.parametrize(
    ("extra_arguments", "expected_keep", "expected_rest"),
    [
        ([], False, []),
        (["--keep-cache"], True, []),
        (["--keep-cache", "-Doptimize=ReleaseSafe"], True, ["-Doptimize=ReleaseSafe"]),
        (["--keep-cache", "--keep-cache", "test"], True, ["test"]),
        (["run", "x.zig", "--", "--keep-cache"], False, ["run", "x.zig", "--", "--keep-cache"]),
    ],
)
def test_split_keep_zig_cache_flag_takes_only_a_leading_flag(
    extra_arguments, expected_keep, expected_rest
):
    assert split_keep_zig_cache_flag(extra_arguments) == (expected_keep, expected_rest)


def test_build_zig_cache_volume_chown_arguments_runs_as_root_and_hands_over_the_volume():
    arguments = build_zig_cache_volume_chown_arguments("docker", "image:tag", (1000, 1001))
    assert arguments == [
        "docker", "run", "--rm",
        "--user", "0:0",
        "-v", "vulkan-stack-adapter-zig-cache:/zig-global-cache",
        "--entrypoint", "chown",
        "image:tag",
        "1000:1001", "/zig-global-cache",
    ]  # fmt: skip
