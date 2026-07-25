#!/usr/bin/env python3
import subprocess
import sys


def main():
    cmd = ["zig", "build", "test-tdd", "-Dshaderc", "--summary", "all"]
    if len(sys.argv) > 1:
        cmd.extend(["--", "--test-filter", sys.argv[1]])
    result = subprocess.run(cmd)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
