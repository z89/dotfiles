#!/usr/bin/env python3
"""Stable provider entrypoint; resolve one complete release for each invocation."""
from __future__ import annotations

import importlib
import json
from pathlib import Path
import sys

BASE = Path.home() / ".local/lib/desktop-guard"


def launch(provider: str, base: Path = BASE) -> None:
    # Read the event before importing the replaceable implementation so even an
    # unavailable release produces the correct provider output shape.
    payload = None
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            raise ValueError("hook input must be an object")
        release = (base / "current").resolve(strict=True)
        if release.parent != (base / "releases").resolve(strict=True):
            raise RuntimeError("active release is outside the release directory")
        sys.dont_write_bytecode = True
        sys.path.insert(0, str(release))
        core = importlib.import_module("core")
        result = core.handle(payload, provider)
    except Exception as exc:
        message = (
            f"DESKTOP GUARD UNAVAILABLE: {type(exc).__name__}: {exc}. "
            "This action has not been approved. The operator can inspect "
            "~/.local/bin/desktop-guard status or recover the previous tested "
            "release with ~/.local/bin/desktop-guard rollback. "
            "No provider or desktop restart is needed."
        )
        event = payload.get("hook_event_name") if isinstance(payload, dict) else None
        if event == "UserPromptSubmit":
            result = {"hookSpecificOutput": {
                "hookEventName": event, "additionalContext": message,
            }}
        elif isinstance(payload, dict) and payload.get("tool_name") in {
            "Read", "Glob", "Grep", "Search", "ListMcpResources", "ReadMcpResource",
        }:
            result = None
        else:
            result = {"systemMessage": message, "hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": message,
            }}
    if result is not None:
        print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    provider = "claude" if ".claude" in Path(__file__).parts else "codex"
    launch(provider)
