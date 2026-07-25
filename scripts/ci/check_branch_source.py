#!/usr/bin/env python3
import sys


def main():
    target = sys.argv[1]
    source = sys.argv[2]
    errors = 0

    if target == "main" and source != "dev":
        print(f"::error::PRs targeting 'main' must come from 'dev', not '{source}'")
        errors += 1

    if target == "dev" and source == "main":
        print("::error::PRs targeting 'dev' must not come from 'main'")
        errors += 1

    if errors:
        print("See the branching model docs for details.")
        sys.exit(1)

    print(f"\u2705 {source} \u2192 {target} is valid")


if __name__ == "__main__":
    main()
