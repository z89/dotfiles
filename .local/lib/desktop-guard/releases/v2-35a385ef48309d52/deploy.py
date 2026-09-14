#!/usr/bin/env python3
"""Prepare, check and atomically install this complete, tested guard release.

Only the enumerated hook/helper/instruction files are replaced. Registration,
chat history, live desktop configuration and legacy approval state are untouched.
Every overwritten byte is backed up. Hash preconditions preserve concurrent edits.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile
import time

SOURCE = Path(__file__).resolve().parent
PLAN = SOURCE / "installation-plan.json"
PACKAGE = ("core.py", "policy.py", "shellparse.py", "bootstrap.py", "recovery.py",
           "test_core.py", "test_policy.py", "test_acceptance.py", "test_deploy.py",
           "run_shared_tests.py", "verify_install.py", "deploy.py", "desktop-rules.md", "README.md")
TARGETS = (".claude/hooks/desktop-control-gate.py", ".codex/hooks/desktop-control-gate.py",
           ".claude/CLAUDE.md", ".codex/AGENTS.md", ".local/bin/desktop-guard",
           ".claude/hooks/tests/test_desktop_gate.py", ".codex/hooks/test_desktop_control_gate.py", ".gitignore")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def content(path):
    return path.read_bytes() if path.exists() else None


def atomic(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=".desktop-guard-install-", dir=path.parent)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def link(path, target):
    temporary = path.with_name("." + path.name + "-" + str(time.time_ns()))
    try:
        temporary.symlink_to(target)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def checked_release(path, hashes):
    """An interrupted install may safely reuse only byte-identical release code."""
    for name, expected in hashes.items():
        data = content(path / name)
        if data is None or digest(data) != expected:
            raise RuntimeError(f"Existing release differs from the prepared candidate: {path / name}")


def restore_link(path, before, installed):
    # Preserve an independently changed pointer, just like independently edited files.
    if not path.is_symlink() or os.readlink(path) != str(installed):
        return
    if before is None:
        path.unlink()  # Only the exact symlink this activation created.
    else:
        link(path, before)


def replace_section(text, start, end, replacement):
    if text.count(start) != 1 or text.count(end) != 1:
        raise RuntimeError("instruction section markers changed; refusing a broad rewrite")
    begin = text.index(start)
    finish = text.index(end, begin)
    return text[:begin] + replacement.rstrip() + "\n\n" + text[finish:]


def staged_contents(home):
    rules = (SOURCE / "desktop-rules.md").read_text()
    claude = (home / ".claude/CLAUDE.md").read_text()
    codex = (home / ".codex/AGENTS.md").read_text()
    claude_marker = ("## Desktop Control Guard" if "## Desktop Control Guard" in claude
                     else "The desktop bullet is enforced, not just written down.")
    claude = replace_section(claude, claude_marker, "## Context discipline",
                             "## Desktop Control Guard\n\n" + rules)
    codex = replace_section(codex, "## Desktop Control Hard Gate", "## Communication",
                            "## Desktop Control Hard Gate\n\n" + rules)
    ignore = (home / ".gitignore").read_text()
    if "!.local/lib/desktop-guard/" not in ignore:
        ignore += ("\n# Shared desktop guard code; approval records stay in the runtime directory.\n"
                   "!.local/lib/\n.local/lib/*\n!.local/lib/desktop-guard/\n"
                   "!.local/bin/desktop-guard\n")
    return {
        TARGETS[0]: (SOURCE / "bootstrap.py").read_bytes(),
        TARGETS[1]: (SOURCE / "bootstrap.py").read_bytes(),
        TARGETS[2]: claude.encode(), TARGETS[3]: codex.encode(),
        TARGETS[4]: (SOURCE / "recovery.py").read_bytes(),
        TARGETS[5]: (SOURCE / "run_shared_tests.py").read_bytes(),
        TARGETS[6]: (SOURCE / "run_shared_tests.py").read_bytes(),
        TARGETS[7]: ignore.encode(),
    }


def legacy_requests():
    uid = os.getuid()
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{uid}")
    roots = {runtime / "claude-guards/desktop-gate", Path(f"/run/user/{uid}/codex-desktop-control-gate"),
             Path(f"/tmp/codex-desktop-control-gate-{uid}")}
    outstanding = []
    for root in roots:
        for path in root.glob("*.json"):
            if path.name == "gui-commands.json":
                continue
            data = json.loads(path.read_text())
            if data.get("status") in {"pending", "approved"} and float(data.get("expires_at", 0)) > time.time():
                outstanding.append(str(data.get("request_id", path.name)))
    if outstanding:
        raise RuntimeError("Existing requests must remain usable; activation deferred until answered/expired: " + ", ".join(outstanding))


def prepare(home):
    original = {}
    for relative in TARGETS:
        path = home / relative
        data = content(path)
        original[relative] = {"sha256": digest(data) if data is not None else None,
                              "mode": stat.S_IMODE(path.stat().st_mode) if data is not None else 0o755}
    proposed = staged_contents(home)
    prepared = SOURCE / "prepared"
    prepared.mkdir(exist_ok=True)
    for relative, data in proposed.items():
        if relative.endswith(".py") or relative.endswith("/desktop-guard"):
            ast.parse(data.decode(), filename=relative)
        atomic(prepared / relative, data, original[relative]["mode"])
    hashes = {}
    for name in PACKAGE:
        data = (SOURCE / name).read_bytes()
        if name.endswith(".py"):
            ast.parse(data.decode(), filename=name)
        hashes[name] = digest(data)
    release = "v2-" + digest(json.dumps(hashes, sort_keys=True).encode())[:16]
    registrations = {name: digest((home / name).read_bytes()) for name in (".claude/settings.json", ".codex/config.toml")}
    plan = {"home": str(home), "release": release, "original": original,
            "proposed": {name: digest(data) for name, data in proposed.items()},
            "package": hashes, "registrations": registrations}
    atomic(PLAN, json.dumps(plan, indent=2).encode(), 0o600)
    print(f"Prepared {release}: {len(proposed)} exact file replacements; registrations unchanged.")
    return plan


def preflight(plan, check_legacy=True):
    home = Path(plan["home"])
    for relative, item in plan["original"].items():
        data = content(home / relative)
        if (digest(data) if data is not None else None) != item["sha256"]:
            raise RuntimeError(f"Concurrent edit preserved; re-prepare before replacing {relative}")
        if digest((SOURCE / "prepared" / relative).read_bytes()) != plan["proposed"][relative]:
            raise RuntimeError(f"Prepared replacement changed: {relative}")
    for relative, expected in plan["registrations"].items():
        if digest((home / relative).read_bytes()) != expected:
            raise RuntimeError(f"Hook registration changed; refusing activation: {relative}")
    for name, expected in plan["package"].items():
        if digest((SOURCE / name).read_bytes()) != expected:
            raise RuntimeError(f"Candidate changed after validation/preparation: {name}")
    if check_legacy:
        legacy_requests()


def apply(plan, check_legacy=True):
    preflight(plan, check_legacy)
    home = Path(plan["home"])
    base = home / ".local/lib/desktop-guard"
    release = base / "releases" / plan["release"]
    backup = home / ".local/state/desktop-guard/backups" / (str(time.time_ns()) + "-" + plan["release"])
    backup.mkdir(parents=True, mode=0o700)
    for relative in TARGETS:
        data = content(home / relative)
        if data is not None:
            atomic(backup / relative, data, plan["original"][relative]["mode"])
    atomic(backup / "manifest.json", json.dumps(plan, indent=2).encode(), 0o600)
    release.parent.mkdir(parents=True, exist_ok=True)
    if release.exists():
        checked_release(release, plan["package"])
    else:
        staging = Path(tempfile.mkdtemp(prefix=".candidate-", dir=release.parent))
        for name in PACKAGE:
            shutil.copyfile(SOURCE / name, staging / name)
            os.chmod(staging / name, 0o644)
        atomic(staging / "manifest.json", json.dumps({"release": plan["release"], "files": plan["package"]}, indent=2).encode())
        os.replace(staging, release)
    former = os.readlink(base / "current") if (base / "current").is_symlink() else None
    former_previous = os.readlink(base / "previous") if (base / "previous").is_symlink() else None
    if former:
        previous_target = former
    else:
        # Independent tested copy supports recovery even if the first current
        # release is later accidentally damaged. Nothing links to the broken v1.
        fallback = release.with_name(release.name + "-recovery")
        if fallback.exists():
            checked_release(fallback, plan["package"])
        else:
            shutil.copytree(release, fallback)
        previous_target = Path("releases") / fallback.name
    installed = []
    try:
        link(base / "previous", previous_target)
        link(base / "current", Path("releases") / release.name)
        for relative in TARGETS:
            target = home / relative
            data = content(target)
            expected = plan["original"][relative]["sha256"]
            if (digest(data) if data is not None else None) != expected:
                raise RuntimeError(f"Concurrent edit preserved during activation: {relative}")
            mode = 0o755 if relative == ".local/bin/desktop-guard" else plan["original"][relative]["mode"]
            atomic(target, (SOURCE / "prepared" / relative).read_bytes(), mode)
            installed.append(relative)
        atomic(base / ".gitignore", b"**/__pycache__/\n**/*.pyc\n.candidate-*\n.current-*\n.previous-*\n")
    except Exception:
        for relative in reversed(installed):
            target = home / relative
            current_data = content(target)
            if current_data is None or digest(current_data) != plan["proposed"][relative]:
                continue  # Never clobber a concurrent operator edit during recovery.
            original = backup / relative
            if original.exists():
                atomic(target, original.read_bytes(), plan["original"][relative]["mode"])
            else:
                destination = backup / "new-files" / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                os.replace(target, destination)
        restore_link(base / "current", former, Path("releases") / release.name)
        restore_link(base / "previous", former_previous, previous_target)
        raise
    print(json.dumps({"installed": str(release), "backup": str(backup), "sessions_restarted": False,
                      "registrations_changed": False, "files_replaced": list(TARGETS)}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("prepare", "check", "apply"))
    parser.add_argument("--home", type=Path, default=Path.home())
    args = parser.parse_args()
    if args.action == "prepare":
        prepare(args.home.resolve())
    else:
        plan = json.loads(PLAN.read_text())
        if args.action == "check":
            preflight(plan)
            print("Activation preflight passed; no files changed.")
        else:
            apply(plan)
