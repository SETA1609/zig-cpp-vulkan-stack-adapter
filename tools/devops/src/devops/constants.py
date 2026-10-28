"""
Constants shared by the devops CLI modules.
"""

from __future__ import annotations

import re
from pathlib import Path

# Container
DEFAULT_CONTAINER_IMAGE = "vulkan-stack-adapter:zig-0.17.0"
DOCKERFILE_RELATIVE_PATH = Path("Dockerfile")
CONTAINER_HOME_DIRECTORY = "/tmp/zig-home"
CONTAINER_ZIG_GLOBAL_CACHE_DIRECTORY = f"{CONTAINER_HOME_DIRECTORY}/cache"
CONTAINER_REPOSITORY_MOUNT = "/src"
CONTAINER_KEPT_ZIG_CACHE_MOUNT = "/zig-global-cache"
ZIG_GLOBAL_CACHE_VOLUME_NAME = "vulkan-stack-adapter-zig-cache"
KEEP_ZIG_CACHE_FLAG = "--keep-cache"
SUPPORTED_CONTAINER_BINARIES = ("docker", "podman")
DOCKERFILE_ZIG_VERSION_PATTERN = re.compile(r"^ARG ZIG_VERSION=(\S+)\s*$", re.MULTILINE)

# Zig cache cleanup
ZIG_BUILD_CACHE_DIRECTORY_NAMES = ("zig-out", ".zig-cache", "zig-pkg")
PROTECTED_RELATIVE_DIRECTORIES = (Path(".git"), Path("cache/logs"))

# Device test suite: lavapipe is the only Vulkan ICD in the image, so it runs headless
TDD_COMMAND_PREFIX: tuple[str, ...] = ()
CI_GATE_NAMES = ("check", "clang-format", "shaderc", "device-tests")

# Run log
EXIT_CODE_PROGRAM_NOT_FOUND = 127
EXIT_CODE_SIGNAL_BASE = 128

# CLI exit codes
EXIT_CODE_SETUP_ERROR = 1
EXIT_CODE_USAGE_ERROR = 2
