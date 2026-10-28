# devops

Host-side CLI that runs this adapter's Zig toolchain container (`vulkan-stack-adapter:zig-0.17.0`, built from the root `Dockerfile`) and logs every run. It is optional: `scripts/ci.sh` and `scripts/tdd.sh` still work with a local Zig 0.17.0. Use it when your host Zig is a different version, when you have no Vulkan device or no system shaderc, or when you want a log of a run. The image has lavapipe (software Vulkan) and `libshaderc-dev`.

The host needs only [uv](https://docs.astral.sh/uv/) and docker or podman. At runtime the CLI uses only the Python standard library. It is copied from [project-new-world](https://github.com/SETA1609/project-new-world/tree/main/tools/devops), which uses this adapter.

## Usage

Run it from the repo root through the shim, which calls `uv run --project tools/devops --locked --no-dev devops <subcommand>`:

```sh
./scripts/container.sh <subcommand> [args...]
```

| Subcommand | What it does |
| --- | --- |
| `image` | Checks that `.zig-version` matches `ARG ZIG_VERSION` in the `Dockerfile`, builds the image, prunes dangling images and unused build cache, prints the image id and size. |
| `build [args...]` | `zig build [args...]` in the container. |
| `test [args...]` | `zig build test [args...]` (the contract suite). |
| `zig [args...]` | Any zig command, for example `./scripts/container.sh zig version`. |
| `ci [gate]` | One gate of `scripts/ci.sh`: `check` (default: fmt, build, smoke demo, contract tests), `clang-format`, `shaderc`, or `device-tests`. |
| `tdd [args...]` | `zig build test-tdd [args...]` on lavapipe. Add `-Dshaderc` to run the shaderc tests too. |
| `shell` | Interactive bash in the container, with the repo at `/src`. |
| `prune` | Removes dangling images and unused build cache. The tagged image and the cache volume stay. |
| `clean` | End of work only: removes `zig-out/`, `.zig-cache/`, `zig-pkg/`, and the cache volume, then prunes. |

`build`, `test`, `zig`, `ci`, `tdd`, and `shell` build the image first if it is missing.

`clean` refuses any path outside the repo, symlinks, `.git/`, and `cache/logs/`.

### Zig cache

Without flags, the Zig global cache lives in the container's throwaway home and is gone when the container exits. The first build fetches vulkan-zig, Vulkan-Headers, and VMA, and generates the bindings. A leading `--keep-cache` stores the cache in the named volume `vulkan-stack-adapter-zig-cache`, which is kept until `clean`:

```sh
./scripts/container.sh ci --keep-cache check
./scripts/container.sh tdd --keep-cache -Dshaderc --summary all
```

Only a leading `--keep-cache` counts, so `./scripts/container.sh zig run x.zig -- --keep-cache` still passes the flag to the program.

### Environment

- `IMAGE` overrides the image tag.
- `CONTAINER_AS_ROOT=1` runs the container as root instead of the host user (`--user uid:gid`).

The CLI uses docker if its daemon answers, otherwise podman.

## Logs

Every line from the container is prefixed with an ISO-8601 UTC timestamp in milliseconds and a stream tag, on the terminal and in `cache/logs/<utc-timestamp>-<subcommand>.log`:

```text
2026-10-28T22:33:38.135Z out | ok: all green
2026-10-28T22:33:38.276Z run | exit code: 0, duration: 158.886 s
```

- `out`: the child's stdout.
- `err`: the child's stderr, or a devops error.
- `run`: devops bookkeeping (command lines, exit codes, durations).

The log ends with the command line, exit code, and duration. `shell` owns the terminal, so only its start, end, and exit code are logged. The CLI exits with the exit code of the last container command it ran. A child killed by signal N exits with 128 + N.

## Layout

```text
src/devops/
  cli.py          subcommands and main()
  container.py    repo root, docker/podman detection, container command lines
  run_log.py      timestamping, log files, running a child with logged output
  zig_cleanup.py  choosing and removing Zig cache paths for `clean`
  constants.py    constants (image, volume, paths, CI gate names)
  exceptions.py   exceptions
  models.py       custom types (dataclasses, type aliases) that keep parameter lists short
tests/            pytest
```

## Development

```sh
cd tools/devops
uv run pytest
uv run ruff check
uv run ruff format --check
```

Docstrings put `"""` on its own line, start the text on the next line, and have no blank lines inside. Function names are a verb plus an object, with words spelled out.
