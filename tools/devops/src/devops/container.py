"""
The Zig toolchain container: finding the repo, the runtime, and building docker/podman calls.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from collections.abc import Callable, Sequence
from pathlib import Path

from devops.constants import (
    CONTAINER_HOME_DIRECTORY,
    CONTAINER_KEPT_ZIG_CACHE_MOUNT,
    CONTAINER_REPOSITORY_MOUNT,
    CONTAINER_ZIG_GLOBAL_CACHE_DIRECTORY,
    DEFAULT_CONTAINER_IMAGE,
    DOCKERFILE_RELATIVE_PATH,
    DOCKERFILE_ZIG_VERSION_PATTERN,
    KEEP_ZIG_CACHE_FLAG,
    SUPPORTED_CONTAINER_BINARIES,
    ZIG_GLOBAL_CACHE_VOLUME_NAME,
)
from devops.exceptions import ContainerSetupError
from devops.models import ContainerRunSettings


def find_repository_root(start_directory: Path) -> Path:
    """
    Walk up from `start_directory` to the directory holding `.zig-version` and the Dockerfile.
    """
    for candidate_directory in [start_directory, *start_directory.parents]:
        has_zig_pin = (candidate_directory / ".zig-version").is_file()
        has_dockerfile = (candidate_directory / DOCKERFILE_RELATIVE_PATH).is_file()
        if has_zig_pin and has_dockerfile:
            return candidate_directory
    raise ContainerSetupError(
        f"no repository root above {start_directory}: "
        f"expected .zig-version and {DOCKERFILE_RELATIVE_PATH}"
    )


def get_dockerfile_path(repository_root: Path) -> Path:
    return repository_root / DOCKERFILE_RELATIVE_PATH


def check_zig_version_matches_dockerfile(repository_root: Path) -> str:
    """
    Return the pinned Zig version; fail if the Dockerfile's first `ARG ZIG_VERSION=` differs.
    """
    pinned_version = (repository_root / ".zig-version").read_text(encoding="utf-8").strip()
    dockerfile_path = get_dockerfile_path(repository_root)
    dockerfile_text = dockerfile_path.read_text(encoding="utf-8")
    version_match = DOCKERFILE_ZIG_VERSION_PATTERN.search(dockerfile_text)
    if version_match is None:
        raise ContainerSetupError(f"{dockerfile_path} has no ARG ZIG_VERSION= line")
    dockerfile_version = version_match.group(1)
    if dockerfile_version != pinned_version:
        raise ContainerSetupError(
            f".zig-version is {pinned_version} but {dockerfile_path} pins {dockerfile_version}"
        )
    return pinned_version


def is_container_daemon_reachable(container_binary: str) -> bool:
    if shutil.which(container_binary) is None:
        return False
    info_result = subprocess.run(
        [container_binary, "info"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return info_result.returncode == 0


def detect_container_binary(
    check_daemon_reachable: Callable[[str], bool] = is_container_daemon_reachable,
) -> str:
    """
    Docker if its daemon answers, else podman.
    """
    for container_binary in SUPPORTED_CONTAINER_BINARIES:
        if check_daemon_reachable(container_binary):
            return container_binary
    raise ContainerSetupError("docker or podman is required and the daemon must be running")


def get_container_image() -> str:
    return os.environ.get("IMAGE", DEFAULT_CONTAINER_IMAGE)


def get_host_user_and_group_ids() -> tuple[int, int] | None:
    """
    Run as the host user so files under the repo stay theirs. `CONTAINER_AS_ROOT=1` opts out.
    """
    if os.environ.get("CONTAINER_AS_ROOT"):
        return None
    return (os.getuid(), os.getgid())


def is_container_image_present(container_binary: str, image: str) -> bool:
    inspect_result = subprocess.run(
        [container_binary, "image", "inspect", image],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return inspect_result.returncode == 0


def build_image_build_arguments(
    container_binary: str, repository_root: Path, image: str, zig_version: str
) -> list[str]:
    return [
        container_binary, "build",
        "--file", str(get_dockerfile_path(repository_root)),
        "--build-arg", f"ZIG_VERSION={zig_version}",
        "--tag", image,
        str(repository_root),
    ]  # fmt: skip


def build_prune_dangling_images_arguments(container_binary: str) -> list[str]:
    return [container_binary, "image", "prune", "-f"]


def build_prune_build_cache_arguments(container_binary: str) -> list[str]:
    return [container_binary, "builder", "prune", "-f"]


def build_image_summary_arguments(container_binary: str, image: str) -> list[str]:
    return [container_binary, "image", "inspect", image, "--format", "id={{.Id}} size={{.Size}}"]


def build_container_run_arguments(
    run_settings: ContainerRunSettings,
    command_in_container: Sequence[str],
    keep_stdin_open: bool = False,
    allocate_terminal: bool = False,
) -> list[str]:
    """
    `<binary> run --rm` with the repo mounted at /src and a throwaway Zig home.
    With `keep_zig_cache`, the Zig global cache lives in the named volume instead of the
    throwaway home, so it survives the run. Without it, nothing outside the repo is kept.
    """
    user_arguments: list[str] = []
    if run_settings.user_and_group_ids is not None:
        user_id, group_id = run_settings.user_and_group_ids
        user_arguments = ["--user", f"{user_id}:{group_id}"]
    terminal_arguments = (["-i"] if keep_stdin_open else []) + (["-t"] if allocate_terminal else [])
    zig_cache_arguments = ["-e", f"ZIG_GLOBAL_CACHE_DIR={CONTAINER_ZIG_GLOBAL_CACHE_DIRECTORY}"]
    if run_settings.keep_zig_cache:
        zig_cache_arguments = [
            "-e", f"ZIG_GLOBAL_CACHE_DIR={CONTAINER_KEPT_ZIG_CACHE_MOUNT}",
            "-v", f"{ZIG_GLOBAL_CACHE_VOLUME_NAME}:{CONTAINER_KEPT_ZIG_CACHE_MOUNT}",
        ]  # fmt: skip
    return [
        run_settings.container_binary, "run", "--rm", "--init",
        *terminal_arguments,
        *user_arguments,
        "-e", f"HOME={CONTAINER_HOME_DIRECTORY}",
        *zig_cache_arguments,
        "-v", f"{run_settings.repository_root}:{CONTAINER_REPOSITORY_MOUNT}",
        "-w", CONTAINER_REPOSITORY_MOUNT,
        run_settings.image,
        *command_in_container,
    ]  # fmt: skip


def split_keep_zig_cache_flag(extra_arguments: Sequence[str]) -> tuple[bool, list[str]]:
    """
    Take a leading `--keep-cache` off the arguments; everything after it goes to zig.
    Only a leading flag counts, so `zig run x.zig -- --keep-cache` still reaches the program.
    """
    remaining_arguments = list(extra_arguments)
    keep_zig_cache = False
    while remaining_arguments and remaining_arguments[0] == KEEP_ZIG_CACHE_FLAG:
        keep_zig_cache = True
        remaining_arguments.pop(0)
    return keep_zig_cache, remaining_arguments


def is_zig_cache_volume_present(container_binary: str) -> bool:
    inspect_result = subprocess.run(
        [container_binary, "volume", "inspect", ZIG_GLOBAL_CACHE_VOLUME_NAME],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return inspect_result.returncode == 0


def build_zig_cache_volume_create_arguments(container_binary: str) -> list[str]:
    return [container_binary, "volume", "create", ZIG_GLOBAL_CACHE_VOLUME_NAME]


def build_zig_cache_volume_remove_arguments(container_binary: str) -> list[str]:
    return [container_binary, "volume", "rm", ZIG_GLOBAL_CACHE_VOLUME_NAME]


def build_zig_cache_volume_chown_arguments(
    container_binary: str, image: str, user_and_group_ids: tuple[int, int]
) -> list[str]:
    """
    A new volume is root-owned; hand it to the host user once, as root, so zig can write.
    """
    user_id, group_id = user_and_group_ids
    return [
        container_binary, "run", "--rm",
        "--user", "0:0",
        "-v", f"{ZIG_GLOBAL_CACHE_VOLUME_NAME}:{CONTAINER_KEPT_ZIG_CACHE_MOUNT}",
        "--entrypoint", "chown",
        image,
        f"{user_id}:{group_id}", CONTAINER_KEPT_ZIG_CACHE_MOUNT,
    ]  # fmt: skip


def build_zig_cache_volume_size_arguments(container_binary: str, image: str) -> list[str]:
    """
    `du -sb` over the volume; prints `<bytes>\t<path>`.
    """
    return [
        container_binary, "run", "--rm",
        "-v", f"{ZIG_GLOBAL_CACHE_VOLUME_NAME}:{CONTAINER_KEPT_ZIG_CACHE_MOUNT}",
        "--entrypoint", "du",
        image,
        "-sb", CONTAINER_KEPT_ZIG_CACHE_MOUNT,
    ]  # fmt: skip


def measure_zig_cache_volume_size_bytes(container_binary: str, image: str) -> int | None:
    """
    Bytes in the volume, or None when it cannot be measured (no image, no volume).
    """
    size_result = subprocess.run(
        build_zig_cache_volume_size_arguments(container_binary, image),
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        check=False,
    )
    if size_result.returncode != 0:
        return None
    try:
        return int(size_result.stdout.split()[0])
    except (IndexError, ValueError):
        return None
