---
name: check-workflows
description: >-
  Validate GitHub Actions workflow YAML for safety and correctness — YAML
  validity, required structure (on/jobs/runs-on/steps), and common
  supply-chain / script-injection / least-privilege footguns. Use whenever the
  user asks to check, validate, lint, audit, or "is it safe" about
  .github/workflows files or CI pipelines.
allowed-tools: Bash, Read, Edit
---

# Check Workflows

A heuristic safety + correctness linter for GitHub Actions workflows, vendored
into this repo (`.claude/skills/check-workflows/validate_workflows.py`) so it's
committed, shared, and run by CI itself (the `lint-workflows` job). It
complements `actionlint` (use that too when available) but needs only Python +
PyYAML, so it runs anywhere.

## How to run

```sh
# Lint every workflow this repo owns (skips vendored/cached deps automatically):
python3 .claude/skills/check-workflows/validate_workflows.py

# A specific file:
python3 .claude/skills/check-workflows/validate_workflows.py .github/workflows/build.yml

# Fail on warnings too (CI runs this — default fails only on ERROR):
python3 .claude/skills/check-workflows/validate_workflows.py --strict
```

If PyYAML is missing: `python3 -m pip install --quiet pyyaml`.

Exit code is `1` when any **ERROR** is found (`--strict` also fails on **WARN**),
else `0`. The repo's CI runs it `--strict` in the `lint-workflows` job.

## What it checks

- **structure** (ERROR): YAML parses; `on:` + `jobs:` present; each job has
  `runs-on` + `steps`; each step has exactly one of `uses:` / `run:`. (Handles
  the YAML 1.1 gotcha where the bare key `on:` parses as the boolean `True`.)
- **supply-chain** (WARN): third-party actions pinned to a version tag or full
  SHA, not a moving branch (`@main`/`@latest`); no `curl … | bash`.
- **injection** (WARN): no untrusted `${{ github.event.* }}` / `head_ref` /
  `inputs.*` / `actor` interpolated straight into a `run:` shell.
- **secrets** (WARN): `secrets.*` not referenced inline in `run:` (map via `env:`).
- **least-privilege** (WARN): a `permissions:` block is declared.
- **cross-OS** (WARN): a `.sh`/bash step on a Windows runner has `shell: bash`
  in scope (step, job, or workflow `defaults.run.shell`).

By default it ignores vendored/build-cache trees (`vendor/`, `zig-pkg/`,
`.zig-cache/`, `node_modules/`, …) so it lints only workflows the repo owns;
pass an explicit file path to lint one regardless.

## Acting on findings

Report the findings, then offer to fix the actionable ones (pin an action to a
tag/SHA, add `permissions:\n  contents: read`, move a secret into `env:`, add
`shell: bash`). Re-run the script after edits to confirm it's clean.
