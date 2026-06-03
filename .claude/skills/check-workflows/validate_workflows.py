#!/usr/bin/env python3
"""Validate GitHub Actions workflow YAML for safety + correctness.

Usage:
    python3 validate_workflows.py [PATH ...]

With no PATH, discovers every `.github/workflows/*.yml|*.yaml` under the current
directory (submodules included). Exits non-zero if any ERROR is found; pass
`--strict` to also fail on WARN.

Checks (heuristic — complements, not replaces, `actionlint`):
  structure   YAML parses; `on` + `jobs` present; each job has `runs-on` + `steps`;
              each step has exactly one of `uses` / `run`.
  supply-chain  third-party actions pinned to a tag/SHA (not a moving branch);
                no `curl … | bash`.
  injection   no untrusted `${{ github.event.* }}` / `head_ref` interpolated
              straight into a `run` shell.
  secrets     `secrets.*` not referenced inline in `run` (map via `env:`).
  least-priv  a `permissions:` block is declared (default token is broad).
  cross-OS    a `.sh`/bash step on a Windows runner has `shell: bash` in scope.
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit("error: PyYAML is required — install it with `pip install pyyaml`")

ERROR, WARN = "ERROR", "WARN"

# A `uses:` ref is considered pinned if it's a version tag (v1, v1.2.3) or a full
# 40-char commit SHA. Anything else (main, master, a branch) is a moving target.
_PINNED = re.compile(r"^(v\d+(\.\d+){0,2}|[0-9a-fA-F]{40})$")
# Untrusted context interpolated into a shell — classic script-injection vector.
_INJECT = re.compile(r"\$\{\{\s*(github\.event\b|github\.head_ref\b|github\.actor\b|inputs\.)")
_PIPE_SHELL = re.compile(r"\b(curl|wget)\b[^\n|]*\|\s*(sudo\s+)?(bash|sh)\b")
_SECRET = re.compile(r"\bsecrets\.[A-Za-z_]")
_SH_INVOKE = re.compile(r"(^|\s|/)(bash|sh)\s+\S+\.sh\b|(^|\s)\./\S+\.sh\b")


# Vendored deps / build caches carry their own (third-party) workflows — skip
# them so a default run only lints the workflows this repo actually owns.
_SKIP_DIRS = {"zig-pkg", "vendor", ".zig-cache", ".git", "node_modules", "zig-out", "_deps"}


def _owned(path):
    return not any(part in _SKIP_DIRS for part in path.split(os.sep))


def discover(paths):
    if paths:
        files = []
        for p in paths:
            if os.path.isdir(p):
                for ext in ("yml", "yaml"):
                    files += [f for f in glob.glob(os.path.join(p, f"**/.github/workflows/*.{ext}"), recursive=True) if _owned(f)]
            else:
                files.append(p)  # explicit file: lint it even if vendored
        return sorted(set(files))
    files = []
    for ext in ("yml", "yaml"):
        files += [f for f in glob.glob(f"**/.github/workflows/*.{ext}", recursive=True) if _owned(f)]
    return sorted(set(files))


def _flatten(value):
    if isinstance(value, dict):
        for v in value.values():
            yield from _flatten(v)
    elif isinstance(value, list):
        for v in value:
            yield from _flatten(v)
    else:
        yield value


def _default_shell(doc, job):
    for scope in (job, doc):
        if isinstance(scope, dict):
            d = scope.get("defaults")
            if isinstance(d, dict) and isinstance(d.get("run"), dict):
                sh = d["run"].get("shell")
                if sh:
                    return sh
    return None


def check_uses(file, where, uses, out):
    if not isinstance(uses, str):
        out.append((ERROR, file, f"{where}: `uses` must be a string"))
        return
    if uses.startswith(("./", "docker://")):
        return  # local composite action / docker image
    if "@" not in uses:
        out.append((WARN, file, f"{where}: action `{uses}` is unpinned (no @ref) — pin to a tag or full SHA"))
        return
    ref = uses.split("@", 1)[1]
    if not _PINNED.match(ref):
        out.append((WARN, file, f"{where}: action `{uses}` pinned to moving ref `{ref}` — use a version tag or full SHA"))


def check_run(file, where, step, doc, job, win, out):
    run = step.get("run")
    if not isinstance(run, str):
        return
    if _INJECT.search(run):
        out.append((WARN, file, f"{where}: `run` interpolates untrusted input (github.event.*/head_ref/inputs/actor) "
                                 "into the shell — script-injection risk; pass it via an `env:` var instead"))
    if _SECRET.search(run):
        out.append((WARN, file, f"{where}: `run` references `secrets.*` inline — map it to an `env:` var to avoid log leakage"))
    if _PIPE_SHELL.search(run):
        out.append((WARN, file, f"{where}: pipes a download straight into a shell (`curl … | bash`) — supply-chain risk"))
    if win and _SH_INVOKE.search(run):
        shell = step.get("shell") or _default_shell(doc, job)
        if shell != "bash":
            out.append((WARN, file, f"{where}: runs a shell script on a Windows runner without `shell: bash` in scope "
                                     "(step/job/workflow `defaults.run.shell`) — it will fail on windows-*"))


def check_step(file, jobname, idx, step, doc, job, win, out):
    where = f"job `{jobname}` step[{idx}]"
    if not isinstance(step, dict):
        out.append((ERROR, file, f"{where}: not a mapping"))
        return
    has_uses, has_run = "uses" in step, "run" in step
    if has_uses == has_run:
        out.append((ERROR, file, f"{where}: must have exactly one of `uses:` or `run:`"))
    if has_uses:
        check_uses(file, where, step["uses"], out)
    if has_run:
        check_run(file, where, step, doc, job, win, out)


def check_doc(file, doc, out):
    if not isinstance(doc, dict):
        out.append((ERROR, file, "top-level YAML is not a mapping"))
        return
    # PyYAML parses the bare key `on:` as the boolean True (YAML 1.1) — accept both.
    on = doc.get("on", doc.get(True))
    if on is None:
        out.append((ERROR, file, "missing `on:` trigger"))
    triggers = list(on.keys()) if isinstance(on, dict) else (on if isinstance(on, list) else [on])
    if "pull_request_target" in triggers:
        out.append((WARN, file, "uses `pull_request_target` — runs with repo secrets in the context of untrusted PR "
                                "code; never check out & build the PR head under it"))
    if "workflow_run" in triggers:
        out.append((WARN, file, "uses `workflow_run` — runs with a write-capable token; review what it executes"))

    jobs = doc.get("jobs")
    if not isinstance(jobs, dict) or not jobs:
        out.append((ERROR, file, "missing or empty `jobs:`"))
        return

    top_perms = "permissions" in doc
    all_jobs_perms = all(isinstance(j, dict) and "permissions" in j for j in jobs.values())
    if not top_perms and not all_jobs_perms:
        out.append((WARN, file, "no `permissions:` block — the default GITHUB_TOKEN is broad; declare least privilege "
                                "(e.g. `permissions:\\n  contents: read`)"))

    for name, job in jobs.items():
        if not isinstance(job, dict):
            out.append((ERROR, file, f"job `{name}`: not a mapping"))
            continue
        if "uses" in job:
            continue  # reusable-workflow call — different shape
        if "runs-on" not in job:
            out.append((ERROR, file, f"job `{name}`: missing `runs-on`"))
        runs_on = str(job.get("runs-on", ""))
        matrix = job.get("strategy", {}).get("matrix", {}) if isinstance(job.get("strategy"), dict) else {}
        win = "windows" in runs_on or any("windows" in str(v) for v in _flatten(matrix))
        steps = job.get("steps")
        if not isinstance(steps, list):
            out.append((ERROR, file, f"job `{name}`: missing `steps:`"))
            continue
        for i, step in enumerate(steps):
            check_step(file, name, i, step, doc, job, win, out)


def main():
    ap = argparse.ArgumentParser(description="Validate GitHub Actions workflow YAML for safety + correctness.")
    ap.add_argument("paths", nargs="*", help="workflow files or repo dirs (default: discover under cwd)")
    ap.add_argument("--strict", action="store_true", help="exit non-zero on warnings too")
    args = ap.parse_args()

    files = discover(args.paths)
    if not files:
        print("no workflow files found (.github/workflows/*.yml)")
        return 0

    findings = []
    for f in files:
        try:
            with open(f, "r", encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except yaml.YAMLError as e:
            findings.append((ERROR, f, f"YAML parse error: {e}"))
            continue
        check_doc(f, doc, findings)

    errors = [x for x in findings if x[0] == ERROR]
    warns = [x for x in findings if x[0] == WARN]
    by_file = {}
    for level, f, msg in findings:
        by_file.setdefault(f, []).append((level, msg))

    for f in files:
        items = by_file.get(f, [])
        mark = "✗" if any(l == ERROR for l, _ in items) else ("!" if items else "✓")
        print(f"{mark} {f}" + ("" if items else "  (clean)"))
        for level, msg in items:
            print(f"    [{level}] {msg}")

    print(f"\n{len(files)} file(s) · {len(errors)} error(s) · {len(warns)} warning(s)")
    if errors or (args.strict and warns):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
