"""
`devops <subcommand> [args...]`: run the Zig toolchain container with logged, timestamped output.
Each run writes `cache/logs/<utc-timestamp>-<subcommand>.log`. The CLI exits with the
exit code of the last container command it ran.
"""

from __future__ import annotations

import shlex
import subprocess
import sys
import time
from collections.abc import Sequence
from pathlib import Path

from devops.constants import (
    CI_GATE_NAMES,
    EXIT_CODE_SETUP_ERROR,
    EXIT_CODE_USAGE_ERROR,
    KEEP_ZIG_CACHE_FLAG,
    TDD_COMMAND_PREFIX,
    ZIG_GLOBAL_CACHE_VOLUME_NAME,
)
from devops.container import (
    build_container_run_arguments,
    build_image_build_arguments,
    build_image_summary_arguments,
    build_prune_build_cache_arguments,
    build_prune_dangling_images_arguments,
    build_zig_cache_volume_chown_arguments,
    build_zig_cache_volume_create_arguments,
    build_zig_cache_volume_remove_arguments,
    check_zig_version_matches_dockerfile,
    detect_container_binary,
    find_repository_root,
    get_container_image,
    get_host_user_and_group_ids,
    is_container_image_present,
    is_zig_cache_volume_present,
    measure_zig_cache_volume_size_bytes,
    split_keep_zig_cache_flag,
)
from devops.exceptions import ContainerSetupError, ZigCleanupRefusedError
from devops.models import ContainerRunSettings, SubcommandFunction
from devops.run_log import (
    RunLog,
    get_current_utc_time,
    open_run_log_file,
    run_command_with_timestamped_output,
)
from devops.zig_cleanup import (
    list_default_zig_cache_paths,
    measure_directory_size_bytes,
    remove_directory_tree,
    select_zig_cache_paths_to_remove,
)


def build_container_image(repository_root: Path, container_binary: str, run_log: RunLog) -> int:
    zig_version = check_zig_version_matches_dockerfile(repository_root)
    image = get_container_image()
    run_log.write_line("run", f"building {image} (zig {zig_version})")
    return run_command_with_timestamped_output(
        build_image_build_arguments(container_binary, repository_root, image, zig_version), run_log
    )


def build_container_image_if_missing(
    repository_root: Path, container_binary: str, run_log: RunLog
) -> int:
    if is_container_image_present(container_binary, get_container_image()):
        return 0
    return build_container_image(repository_root, container_binary, run_log)


def prepare_kept_zig_cache_volume(container_binary: str, run_log: RunLog) -> int:
    """
    Create the cache volume on first use and hand it to the host user. Reuse it after.
    """
    if is_zig_cache_volume_present(container_binary):
        run_log.write_line(
            "run", f"zig global cache: reusing volume {ZIG_GLOBAL_CACHE_VOLUME_NAME}"
        )
        return 0
    run_log.write_line("run", f"zig global cache: creating volume {ZIG_GLOBAL_CACHE_VOLUME_NAME}")
    create_exit_code = run_command_with_timestamped_output(
        build_zig_cache_volume_create_arguments(container_binary), run_log
    )
    user_and_group_ids = get_host_user_and_group_ids()
    if create_exit_code != 0 or user_and_group_ids is None:
        return create_exit_code
    return run_command_with_timestamped_output(
        build_zig_cache_volume_chown_arguments(
            container_binary, get_container_image(), user_and_group_ids
        ),
        run_log,
    )


def prepare_container_run(
    repository_root: Path, keep_zig_cache: bool, run_log: RunLog
) -> tuple[ContainerRunSettings, int]:
    """
    Find the runtime, build the image if missing, set up the cache. Return (settings, code).
    """
    run_settings = ContainerRunSettings(
        container_binary=detect_container_binary(),
        repository_root=repository_root,
        image=get_container_image(),
        user_and_group_ids=get_host_user_and_group_ids(),
        keep_zig_cache=keep_zig_cache,
    )
    image_exit_code = build_container_image_if_missing(
        repository_root, run_settings.container_binary, run_log
    )
    if image_exit_code != 0:
        return run_settings, image_exit_code
    if not keep_zig_cache:
        run_log.write_line("run", "zig global cache: throwaway (pass --keep-cache to keep it)")
        return run_settings, 0
    return run_settings, prepare_kept_zig_cache_volume(run_settings.container_binary, run_log)


def run_command_in_container(
    repository_root: Path,
    command_in_container: Sequence[str],
    keep_zig_cache: bool,
    run_log: RunLog,
) -> int:
    run_settings, setup_exit_code = prepare_container_run(repository_root, keep_zig_cache, run_log)
    if setup_exit_code != 0:
        return setup_exit_code
    return run_command_with_timestamped_output(
        build_container_run_arguments(run_settings, command_in_container), run_log
    )


def run_zig_in_container(
    repository_root: Path, zig_arguments: Sequence[str], keep_zig_cache: bool, run_log: RunLog
) -> int:
    return run_command_in_container(
        repository_root, ["zig", *zig_arguments], keep_zig_cache, run_log
    )


def prune_container_images_and_build_cache(container_binary: str, run_log: RunLog) -> int:
    """
    Remove dangling images and unused build cache. Tagged images and volumes stay.
    """
    run_log.write_line("run", "pruning dangling images and unused build cache")
    for prune_arguments in (
        build_prune_dangling_images_arguments(container_binary),
        build_prune_build_cache_arguments(container_binary),
    ):
        prune_exit_code = run_command_with_timestamped_output(prune_arguments, run_log)
        if prune_exit_code != 0:
            return prune_exit_code
    return 0


def run_image_subcommand(
    repository_root: Path, extra_arguments: Sequence[str], run_log: RunLog
) -> int:
    """
    Build the image, prune dangling layers and build cache, print the image id and size.
    """
    if extra_arguments:
        run_log.write_line("err", f"image takes no arguments, got: {shlex.join(extra_arguments)}")
        return EXIT_CODE_USAGE_ERROR
    container_binary = detect_container_binary()
    image = get_container_image()
    build_exit_code = build_container_image(repository_root, container_binary, run_log)
    if build_exit_code != 0:
        return build_exit_code
    prune_exit_code = prune_container_images_and_build_cache(container_binary, run_log)
    if prune_exit_code != 0:
        return prune_exit_code
    run_log.write_line("run", f"{image} is ready")
    return run_command_with_timestamped_output(
        build_image_summary_arguments(container_binary, image), run_log
    )


def run_build_subcommand(
    repository_root: Path, extra_arguments: Sequence[str], run_log: RunLog
) -> int:
    keep_zig_cache, zig_arguments = split_keep_zig_cache_flag(extra_arguments)
    return run_zig_in_container(repository_root, ["build", *zig_arguments], keep_zig_cache, run_log)


def run_test_subcommand(
    repository_root: Path, extra_arguments: Sequence[str], run_log: RunLog
) -> int:
    keep_zig_cache, zig_arguments = split_keep_zig_cache_flag(extra_arguments)
    return run_zig_in_container(
        repository_root, ["build", "test", *zig_arguments], keep_zig_cache, run_log
    )


def run_zig_subcommand(
    repository_root: Path, extra_arguments: Sequence[str], run_log: RunLog
) -> int:
    keep_zig_cache, zig_arguments = split_keep_zig_cache_flag(extra_arguments)
    return run_zig_in_container(repository_root, zig_arguments, keep_zig_cache, run_log)


def run_ci_subcommand(
    repository_root: Path, extra_arguments: Sequence[str], run_log: RunLog
) -> int:
    """
    One CI gate (`scripts/ci.sh [check|clang-format|shaderc|device-tests]`) in the container.
    """
    keep_zig_cache, ci_arguments = split_keep_zig_cache_flag(extra_arguments)
    if len(ci_arguments) > 1 or (ci_arguments and ci_arguments[0] not in CI_GATE_NAMES):
        run_log.write_line(
            "err",
            f"ci takes one of {', '.join(CI_GATE_NAMES)}, got: {shlex.join(ci_arguments)}",
        )
        return EXIT_CODE_USAGE_ERROR
    return run_command_in_container(
        repository_root, ["bash", "scripts/ci.sh", *ci_arguments], keep_zig_cache, run_log
    )


def run_tdd_subcommand(
    repository_root: Path, extra_arguments: Sequence[str], run_log: RunLog
) -> int:
    """
    The device suite (`zig build test-tdd [args...]`) on lavapipe; add `-Dshaderc` for shaderc.
    """
    keep_zig_cache, zig_arguments = split_keep_zig_cache_flag(extra_arguments)
    return run_command_in_container(
        repository_root,
        [*TDD_COMMAND_PREFIX, "zig", "build", "test-tdd", *zig_arguments],
        keep_zig_cache,
        run_log,
    )


def open_interactive_container_shell(
    repository_root: Path, extra_arguments: Sequence[str], run_log: RunLog
) -> int:
    """
    Interactive bash in the container. It owns the terminal, so only start and end are logged.
    """
    keep_zig_cache, shell_arguments = split_keep_zig_cache_flag(extra_arguments)
    if shell_arguments:
        run_log.write_line(
            "err",
            f"shell takes only {KEEP_ZIG_CACHE_FLAG}, got: {shlex.join(shell_arguments)}",
        )
        return EXIT_CODE_USAGE_ERROR
    run_settings, setup_exit_code = prepare_container_run(repository_root, keep_zig_cache, run_log)
    if setup_exit_code != 0:
        return setup_exit_code
    shell_command = build_container_run_arguments(
        run_settings,
        ["bash"],
        keep_stdin_open=True,
        allocate_terminal=sys.stdin.isatty(),
    )
    run_log.write_line("run", f"shell started: {shlex.join(shell_command)}")
    shell_result = subprocess.run(shell_command, check=False)
    run_log.write_line("run", f"shell ended, exit code: {shell_result.returncode}")
    return shell_result.returncode


def run_prune_subcommand(
    repository_root: Path, extra_arguments: Sequence[str], run_log: RunLog
) -> int:
    if extra_arguments:
        run_log.write_line("err", f"prune takes no arguments, got: {shlex.join(extra_arguments)}")
        return EXIT_CODE_USAGE_ERROR
    return prune_container_images_and_build_cache(detect_container_binary(), run_log)


def remove_zig_build_caches(
    repository_root: Path, extra_arguments: Sequence[str], run_log: RunLog
) -> int:
    """
    End-of-work cleanup: `zig-out/`, `.zig-cache/`, the cache volume, then prune.
    Runs only when the user asks or says the work is finished. Nothing else calls it.
    """
    if extra_arguments:
        run_log.write_line("err", f"clean takes no arguments, got: {shlex.join(extra_arguments)}")
        return EXIT_CODE_USAGE_ERROR
    try:
        selected_paths = select_zig_cache_paths_to_remove(
            repository_root, list_default_zig_cache_paths(repository_root)
        )
    except ZigCleanupRefusedError as refused_error:
        run_log.write_line("err", str(refused_error))
        return EXIT_CODE_SETUP_ERROR
    total_freed_bytes = 0
    for selected_path in selected_paths:
        freed_bytes = measure_directory_size_bytes(selected_path)
        try:
            remove_directory_tree(selected_path)
        except OSError as remove_error:
            run_log.write_line("err", f"could not remove {selected_path}: {remove_error}")
            return EXIT_CODE_SETUP_ERROR
        total_freed_bytes += freed_bytes
        relative_path = selected_path.relative_to(repository_root.resolve())
        run_log.write_line("run", f"removed {relative_path}/: {freed_bytes} bytes")
    container_binary = detect_container_binary()
    if is_zig_cache_volume_present(container_binary):
        volume_bytes = measure_zig_cache_volume_size_bytes(container_binary, get_container_image())
        remove_exit_code = run_command_with_timestamped_output(
            build_zig_cache_volume_remove_arguments(container_binary), run_log
        )
        if remove_exit_code != 0:
            return remove_exit_code
        volume_size_text = "size unknown" if volume_bytes is None else f"{volume_bytes} bytes"
        total_freed_bytes += volume_bytes or 0
        run_log.write_line(
            "run", f"removed volume {ZIG_GLOBAL_CACHE_VOLUME_NAME}: {volume_size_text}"
        )
    else:
        run_log.write_line("run", f"volume {ZIG_GLOBAL_CACHE_VOLUME_NAME} is not present")
    prune_exit_code = prune_container_images_and_build_cache(container_binary, run_log)
    run_log.write_line("run", f"freed {total_freed_bytes} bytes of Zig caches")
    return prune_exit_code


SUBCOMMANDS: dict[str, tuple[SubcommandFunction, str]] = {
    "image": (run_image_subcommand, "build the toolchain image, then prune dangling layers"),
    "build": (run_build_subcommand, "run `zig build [args...]` in the container"),
    "test": (run_test_subcommand, "run `zig build test [args...]` in the container"),
    "zig": (run_zig_subcommand, "run `zig [args...]` in the container"),
    "ci": (run_ci_subcommand, "run a CI gate: ci [check|clang-format|shaderc|device-tests]"),
    "tdd": (run_tdd_subcommand, "run `zig build test-tdd [args...]` on lavapipe"),
    "shell": (open_interactive_container_shell, "open an interactive bash in the container"),
    "prune": (run_prune_subcommand, "remove dangling images and unused build cache"),
    "clean": (
        remove_zig_build_caches,
        "end of work only: remove zig-out/, .zig-cache/, the cache volume; prune",
    ),
}


def format_usage_text() -> str:
    subcommand_lines = [
        f"  {name:<7} {description}" for name, (_, description) in SUBCOMMANDS.items()
    ]
    return "\n".join(
        [
            "usage: devops <subcommand> [args...]",
            "",
            *subcommand_lines,
            "",
            f"build, test, zig, ci, tdd, shell: a leading {KEEP_ZIG_CACHE_FLAG} keeps the cache",
            f"in the volume {ZIG_GLOBAL_CACHE_VOLUME_NAME} until `clean`. Without it the cache",
            "is thrown away with the container.",
            "",
            "Output is timestamped and logged to cache/logs/.",
            "Environment: IMAGE overrides the image tag; CONTAINER_AS_ROOT=1 skips --user.",
        ]
    )


def main(argv: Sequence[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    if not arguments or arguments[0] in ("-h", "--help"):
        print(format_usage_text(), file=sys.stdout if arguments else sys.stderr)
        return 0 if arguments else EXIT_CODE_USAGE_ERROR
    subcommand, extra_arguments = arguments[0], arguments[1:]
    if subcommand not in SUBCOMMANDS:
        print(f"unknown subcommand: {subcommand}\n\n{format_usage_text()}", file=sys.stderr)
        return EXIT_CODE_USAGE_ERROR
    subcommand_function, _ = SUBCOMMANDS[subcommand]

    try:
        repository_root = find_repository_root(Path(__file__).resolve().parent)
    except ContainerSetupError as setup_error:
        print(f"devops: {setup_error}", file=sys.stderr)
        return EXIT_CODE_SETUP_ERROR

    log_directory = repository_root / "cache" / "logs"
    start_seconds = time.monotonic()
    with open_run_log_file(log_directory, subcommand, get_current_utc_time()) as log_file:
        run_log = RunLog(log_file, sys.stdout, sys.stderr)
        run_log.write_line("run", f"log: {Path(log_file.name).relative_to(repository_root)}")
        try:
            exit_code = subcommand_function(repository_root, extra_arguments, run_log)
        except ContainerSetupError as setup_error:
            run_log.write_line("err", str(setup_error))
            exit_code = EXIT_CODE_SETUP_ERROR
        duration_seconds = time.monotonic() - start_seconds
        run_log.write_line("run", f"finished: devops {shlex.join(arguments)}")
        run_log.write_line("run", f"exit code: {exit_code}, duration: {duration_seconds:.3f} s")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
