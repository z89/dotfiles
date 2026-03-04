#!/bin/bash
# PostToolUse hook for Skill tool.
# Creates a session marker when the /commit skill is loaded.

INPUT=$(cat)
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

if [[ "$SKILL" == "commit" && -n "$SESSION_ID" ]]; then
  touch "/tmp/claude-commit-skill-${SESSION_ID}"
fi
