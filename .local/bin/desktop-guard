#!/usr/bin/env python3
"""Operator recovery entrypoint; rollback does not import the active release."""
from __future__ import annotations

import importlib
import json
import os
from pathlib import Path
import secrets
import sys

BASE = Path.home() / ".local/lib/desktop-guard"


def release_path(base: Path, name: str) -> Path:
    resolved = (base / name).resolve(strict=True)
    if resolved.parent != (base / "releases").resolve(strict=True):
        raise RuntimeError(f"{name} is not a local tested release")
    if not (resolved / "core.py").is_file():
        raise RuntimeError(f"{name} is missing its core")
    return resolved


def rollback(base: Path) -> None:
    previous = release_path(base, "previous")
    current = (base / "current").resolve()
    if previous == current:
        print(f"Already using previous release {previous.name}")
        return
    temporary = base / (".current-" + secrets.token_hex(6))
    try:
        temporary.symlink_to(Path("releases") / previous.name)
        os.replace(temporary, base / "current")
    finally:
        temporary.unlink(missing_ok=True)
    if previous.name.endswith("-recovery"):
        print(f"Selected first-install repair copy {previous.name}; this repairs replacement files, "
              "not a rollback to the original guard. Sessions and desktop were not restarted.")
    else:
        print(f"Restored tested release {previous.name}; sessions and desktop were not restarted.")


def main() -> None:
    try:
        if sys.argv[1:] == ["rollback"]:
            rollback(BASE)
            return
        release = release_path(BASE, "current")
        sys.dont_write_bytecode = True
        sys.path.insert(0, str(release))
        if sys.argv[1:] == ["version"]:
            print(json.dumps({"release": release.name, "path": str(release)}))
            return
        importlib.import_module("core").cli()
    except Exception as exc:
        print(f"Desktop guard recovery: {type(exc).__name__}: {exc}", file=sys.stderr)
        print("No desktop action was executed. Inspect the saved installation backup if no previous release exists.", file=sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
