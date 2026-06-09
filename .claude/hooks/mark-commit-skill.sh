#!/bin/bash
# Creates the /commit session marker that require-commit-skill.sh checks for.
# Wired to two events so BOTH ways of loading the skill unlock git:
#   - PostToolUse / Skill   : the model invokes the Skill tool (tool_input.skill == "commit")
#   - UserPromptSubmit      : the user types the /commit slash command (prompt starts with /commit)

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

[[ -z "$SESSION_ID" ]] && exit 0

if [[ "$SKILL" == "commit" ]] || [[ "$PROMPT" =~ ^[[:space:]]*/commit([[:space:]]|$) ]]; then
  touch "/tmp/claude-commit-skill-${SESSION_ID}"
fi
exit 0
