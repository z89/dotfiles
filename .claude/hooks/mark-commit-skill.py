#!/usr/bin/env python3
"""Arms the session marker that require-commit-skill.py checks for.

Wired to two events, because there are two ways the commit rules get loaded:

  PostToolUse / Skill  the model invokes the Skill tool with skill="commit"
  UserPromptSubmit     the user types the /commit slash command

Either one means the rules are now in context, so either one opens the gate.

Replaces a shell version that depended on `jq`; if jq were missing it exited
silently without arming, and the gate would then refuse every git command in the
session with no way to satisfy it. Nothing here can fail that way.

Also sweeps markers old enough that no live session could still want them, so
the runtime directory does not accumulate one file per session indefinitely.

Always exits 0 and prints nothing. A hook on UserPromptSubmit that writes to
stdout injects that text into the conversation, and this one has nothing to say.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _marker  # noqa: E402

SLASH_COMMIT = re.compile(r"^\s*/commit(?:\s|$)")


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    session = data.get("session_id") or os.environ.get("CLAUDE_CODE_SESSION_ID") or ""
    if not session:
        sys.exit(0)

    tool_input = data.get("tool_input") or {}
    skill = ""
    if isinstance(tool_input, dict):
        skill = (tool_input.get("skill") or "").strip().lower()

    prompt = data.get("prompt") or ""

    # `Skill(commit)` and `Skill(commit:args)` both name the same skill.
    armed = skill == "commit" or skill.startswith("commit:")
    armed = armed or bool(SLASH_COMMIT.match(prompt))

    if armed:
        try:
            _marker.arm(session)
        except OSError:
            pass

    _marker.sweep()
    sys.exit(0)


if __name__ == "__main__":
    main()
