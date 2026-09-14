#!/usr/bin/env python3
"""Exercise installed hook entrypoints with synthetic actions and private state.

Subprocesses run only Python hook scripts. Desktop commands are JSON data and
are never executed. No provider, desktop application, or service is launched.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def verify(home):
    with tempfile.TemporaryDirectory(prefix="desktop-guard-verify-") as runtime:
        env = dict(os.environ, XDG_RUNTIME_DIR=runtime, PYTHONDONTWRITEBYTECODE="1", HOME=str(home))
        for provider in ("claude", "codex"):
            script = home / f".{provider}/hooks/desktop-control-gate.py"
            def invoke(payload):
                process = subprocess.run([sys.executable, str(script)], input=json.dumps(payload),
                                         text=True, capture_output=True, env=env, cwd=str(home), timeout=10)
                if process.returncode:
                    raise AssertionError(f"{provider}: hook exited {process.returncode}: {process.stderr}")
                return json.loads(process.stdout) if process.stdout.strip() else None
            base = {"hook_event_name": "PreToolUse", "session_id": "offline-entrypoint-test",
                    "agent_id": "offline-test-actor", "transcript_path": str(Path(runtime) / "fixture.jsonl"),
                    "tool_name": "Bash", "cwd": str(home)}
            safe = {**base, "tool_input": {"command": "pwd"}}
            risky = {**base, "tool_input": {"command": "hyprctl dispatch workspace 2"}}
            assert invoke(safe) is None, provider
            result = invoke(risky)
            assert result["hookSpecificOutput"]["permissionDecision"] == "deny", provider
            assert "continue" not in result and "stopReason" not in result, provider
            code = re.search(r"YES (DSK-[0-9A-F]{6})", result["systemMessage"]).group(1)
            assert invoke(safe) is None, provider
            prompt = invoke({"hook_event_name": "UserPromptSubmit", "session_id": base["session_id"],
                             "prompt": f"YES {code}"})
            assert prompt["hookSpecificOutput"]["hookEventName"] == "UserPromptSubmit", provider
            assert invoke(safe) is None, provider
            assert invoke(risky) is None, provider
            assert invoke(risky)["hookSpecificOutput"]["permissionDecision"] == "deny", provider
            print(f"{provider}: installed entrypoint pass/read/deny/approve/one-use verified (synthetic actions only)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--home", type=Path, default=Path.home())
    verify(parser.parse_args().home.resolve())
