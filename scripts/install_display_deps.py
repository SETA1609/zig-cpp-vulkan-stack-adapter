#!/usr/bin/env python3
"""Cross-platform display dependency installer for CI.

Installs Xvfb + Mesa software Vulkan/GL drivers on Linux (the common headless
CI case), and validates availability on macOS/Windows without sudo gating.

Usage:
  python scripts/install_display_deps.py              # install + verify
  python scripts/install_display_deps.py --check-only  # verify only, no install
  python scripts/install_display_deps.py --vulkan-only # just Vulkan loader + ICD

Exit codes:
  0 — deps available (or platform has native display, no install needed)
  1 — install failed or deps missing after install
"""

import os
import shutil
import subprocess
import sys
from enum import IntEnum, StrEnum


class Exit(IntEnum):
    OK = 0
    FAIL = 1


class Flag(StrEnum):
    CHECK_ONLY = "--check-only"
    VULKAN_ONLY = "--vulkan-only"


class Platform(StrEnum):
    LINUX = "linux"
    MACOS = "darwin"
    WINDOWS = "win32"
    CYGWIN = "cygwin"


class Tool(StrEnum):
    XVFB_RUN = "xvfb-run"
    VULKANINFO = "vulkaninfo"
    LIBVULKAN_SO = "libvulkan.so.1"
    SUDO = "sudo"
    APT_GET = "apt-get"
    BREW = "brew"


class Apt(StrEnum):
    UPDATE = "update"
    INSTALL = "install"
    FLAG_QUIET = "-qq"
    FLAG_YES = "-y"


class VulkanInfo(StrEnum):
    SUMMARY = "--summary"


class Brew(StrEnum):
    INSTALL = "install"
    MOLTEN_VK = "molten-vk"


class Msg(StrEnum):
    XVFB_MISSING = "missing: xvfb-run"
    ICD_MISSING = "missing: Vulkan ICD"
    ICD_MISSING_MACOS = "note: no Vulkan ICD found (display tests may be skipped)"
    SUDO_NOT_ROOT = "info: not root, attempting install with sudo"
    APT_FAILED = "warning: apt-get update failed, continuing"
    INSTALL_FAILED = "error: failed to install display dependencies"
    XVFB_STILL_MISSING = "error: xvfb-run still not found after install"
    INSTALL_OK = "ok: display dependencies installed"
    VULKAN_SDK_FOUND = "ok: Vulkan SDK already available (vulkaninfo found)"
    BREW_INSTALLING = "info: Vulkan SDK not found, attempting brew install molten-vk"
    BREW_FAILED = "warning: brew install molten-vk failed"
    MOLTENVK_OK = "ok: MoltenVK installed"
    NO_BREW = "note: no Vulkan SDK and no Homebrew; display tests skipped on this runner"
    WINDOWS_SKIP = "note: Windows CI uses native display server; no display deps needed"
    VULKAN_SKIP = "warning: Vulkan SDK setup incomplete, display tests may fail"
    UNKNOWN_PLATFORM = "warning: unknown platform '{}', no display deps installed"
    DONE = "ok: display-deps"


LIBVULKAN_PATHS = [
    "/usr/lib/x86_64-linux-gnu/libvulkan.so.1",
    "/usr/lib/aarch64-linux-gnu/libvulkan.so.1",
]

LINUX_DISPLAY_PACKAGES = [
    "xvfb",
    "mesa-utils",
    "libgl1-mesa-dri",
    "libglx-mesa0",
    "libvulkan1",
    "mesa-vulkan-drivers",
]

LINUX_VULKAN_PACKAGES = [
    "libvulkan1",
    "mesa-vulkan-drivers",
    "vulkan-tools",
]


def detect_platform() -> str:
    if sys.platform == Platform.LINUX:
        return Platform.LINUX
    if sys.platform == Platform.MACOS:
        return Platform.MACOS
    if sys.platform in (Platform.WINDOWS, Platform.CYGWIN):
        return Platform.WINDOWS
    return sys.platform


def _tool(name: str) -> str | None:
    return shutil.which(name)


def _run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, **kwargs)


def check_xvfb() -> bool:
    return _tool(Tool.XVFB_RUN) is not None


def check_vulkan_icd() -> bool:
    if _tool(Tool.VULKANINFO):
        result = _run([Tool.VULKANINFO, VulkanInfo.SUMMARY], capture_output=True, text=True)
        return result.returncode == Exit.OK
    if sys.platform == Platform.LINUX:
        return _tool(Tool.LIBVULKAN_SO) is not None or any(
            os.path.exists(p) for p in LIBVULKAN_PATHS
        )
    return False


def _apt(packages: list[str]) -> bool:
    sudo = [Tool.SUDO] if os.geteuid() != 0 else []

    update_cmd = [*sudo, Tool.APT_GET, Apt.UPDATE, Apt.FLAG_QUIET]
    print(f"== {' '.join(update_cmd)} ==")
    if _run(update_cmd).returncode != Exit.OK:
        print(Msg.APT_FAILED)

    install_cmd = [*sudo, Tool.APT_GET, Apt.INSTALL, Apt.FLAG_YES, Apt.FLAG_QUIET, *packages]
    print(f"== {' '.join(install_cmd)} ==")
    return _run(install_cmd).returncode == Exit.OK


def install_linux(packages: list[str] | None = None) -> bool:
    return _apt(packages or LINUX_DISPLAY_PACKAGES)


def install_macos() -> bool:
    if _tool(Tool.VULKANINFO):
        print(Msg.VULKAN_SDK_FOUND)
        return True
    if _tool(Tool.BREW):
        print(Msg.BREW_INSTALLING)
        result = _run([Tool.BREW, Brew.INSTALL, Brew.MOLTEN_VK])
        if result.returncode != Exit.OK:
            print(Msg.BREW_FAILED)
            return False
        print(Msg.MOLTENVK_OK)
        return True
    print(Msg.NO_BREW)
    return True


def install_windows() -> bool:
    print(Msg.WINDOWS_SKIP)
    return True


def check_only() -> int:
    plat = detect_platform()

    if plat == Platform.LINUX:
        ok = True
        if not check_xvfb():
            print(Msg.XVFB_MISSING)
            ok = False
        if not check_vulkan_icd():
            print(Msg.ICD_MISSING)
            ok = False
        return Exit.OK if ok else Exit.FAIL

    if plat == Platform.MACOS:
        if not check_vulkan_icd():
            print(Msg.ICD_MISSING_MACOS)
        return Exit.OK

    return Exit.OK


def main():
    flags = set(sys.argv[1:])
    check_only_mode = Flag.CHECK_ONLY in flags
    vulkan_only = Flag.VULKAN_ONLY in flags

    plat = detect_platform()

    if check_only_mode:
        print(f"platform: {plat}")
        sys.exit(check_only())

    print(f"platform: {plat}")

    if plat == Platform.LINUX:
        pkgs = LINUX_VULKAN_PACKAGES if vulkan_only else LINUX_DISPLAY_PACKAGES
        if not install_linux(pkgs):
            print(Msg.INSTALL_FAILED, file=sys.stderr)
            sys.exit(Exit.FAIL)
        if not vulkan_only and not check_xvfb():
            print(Msg.XVFB_STILL_MISSING, file=sys.stderr)
            sys.exit(Exit.FAIL)
        print(Msg.INSTALL_OK)

    elif plat == Platform.MACOS:
        if not install_macos():
            print(Msg.VULKAN_SKIP)

    elif plat == Platform.WINDOWS:
        install_windows()

    else:
        print(Msg.UNKNOWN_PLATFORM.format(plat))

    print(Msg.DONE)


if __name__ == "__main__":
    main()
