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
from enum import StrEnum


class Platform(StrEnum):
    LINUX = "linux"
    MACOS = "darwin"
    WINDOWS = "win32"


LINUX_PACKAGES = [
    "xvfb",
    "mesa-utils",
    "libgl1-mesa-dri",
    "libglx-mesa0",
    "libvulkan1",
    "mesa-vulkan-drivers",
]


def detect_platform() -> str:
    if sys.platform == Platform.LINUX:
        return Platform.LINUX
    if sys.platform == Platform.MACOS:
        return Platform.MACOS
    if sys.platform in (Platform.WINDOWS, "cygwin"):
        return Platform.WINDOWS
    return sys.platform


def check_xvfb() -> bool:
    return shutil.which("xvfb-run") is not None


def check_vulkan_icd() -> bool:
    if shutil.which("vulkaninfo"):
        result = subprocess.run(
            ["vulkaninfo", "--summary"],
            capture_output=True,
            text=True,
        )
        return result.returncode == 0
    if sys.platform == Platform.LINUX:
        return shutil.which("libvulkan.so.1") is not None or any(
            os.path.exists(p)
            for p in [
                "/usr/lib/x86_64-linux-gnu/libvulkan.so.1",
                "/usr/lib/aarch64-linux-gnu/libvulkan.so.1",
            ]
        )
    return False


def install_linux(packages: list[str] | None = None) -> bool:
    if packages is None:
        packages = LINUX_PACKAGES
    if os.geteuid() != 0:
        sudo = ["sudo"]
    else:
        sudo = []

    update_cmd = sudo + ["apt-get", "update", "-qq"]
    print(f"== {' '.join(update_cmd)} ==")
    if subprocess.run(update_cmd).returncode != 0:
        print("warning: apt-get update failed, continuing")

    install_cmd = sudo + ["apt-get", "install", "-y", "-qq"] + packages
    print(f"== {' '.join(install_cmd)} ==")
    return subprocess.run(install_cmd).returncode == 0


def install_macos() -> bool:
    if shutil.which("vulkaninfo"):
        print("ok: Vulkan SDK already available (vulkaninfo found)")
        return True
    if shutil.which("brew"):
        print("info: Vulkan SDK not found, attempting brew install molten-vk")
        result = subprocess.run(["brew", "install", "molten-vk"])
        if result.returncode != 0:
            print("warning: brew install molten-vk failed")
            return False
        print("ok: MoltenVK installed")
        return True
    print("note: no Vulkan SDK and no Homebrew; display tests skipped on this runner")
    return True


def install_windows() -> bool:
    print("note: Windows CI uses native display server; no display deps needed")
    return True


def check_only() -> int:
    plat = detect_platform()

    if plat == Platform.LINUX:
        ok = True
        if not check_xvfb():
            print("missing: xvfb-run")
            ok = False
        if not check_vulkan_icd():
            print("missing: Vulkan ICD")
            ok = False
        return 0 if ok else 1

    if plat == Platform.MACOS:
        if not check_vulkan_icd():
            print("note: no Vulkan ICD found (display tests may be skipped)")
        return 0

    return 0


def main():
    check_only_mode = "--check-only" in sys.argv
    vulkan_only = "--vulkan-only" in sys.argv

    plat = detect_platform()

    if check_only_mode:
        print(f"platform: {plat}")
        sys.exit(check_only())

    print(f"platform: {plat}")

    if plat == Platform.LINUX:
        pkgs = (
            ["libvulkan1", "mesa-vulkan-drivers", "vulkan-tools"]
            if vulkan_only
            else LINUX_PACKAGES
        )
        if not install_linux(pkgs):
            print("error: failed to install display dependencies", file=sys.stderr)
            sys.exit(1)
        if not vulkan_only:
            if not check_xvfb():
                print("error: xvfb-run still not found after install", file=sys.stderr)
                sys.exit(1)
        print("ok: display dependencies installed")

    elif plat == Platform.MACOS:
        if not install_macos():
            print("warning: Vulkan SDK setup incomplete, display tests may fail")

    elif plat == Platform.WINDOWS:
        install_windows()

    else:
        print(f"warning: unknown platform '{plat}', no display deps installed")

    print("ok: display-deps")


if __name__ == "__main__":
    main()
