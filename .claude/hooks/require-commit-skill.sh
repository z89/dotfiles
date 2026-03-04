#!/bin/bash
# PreToolUse hook for Bash tool.
# Blocks mutating git commands unless the /commit skill has been loaded.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Skip if no git command present
echo "$COMMAND" | grep -qE '(^|&&|\|\||;|`|\$\()\s*git\s' || exit 0

# Allow read-only git commands (unless combined with a mutating one below)
MUTATING='(commit|push|add|reset|checkout|merge|rebase|cherry-pick|tag|stash|rm|mv|restore|switch|pull|fetch|clone|init|remote\s+(add|remove|rename|set-url))'

echo "$COMMAND" | grep -qE "(^|&&|\|\||;|\`|\\\$\()\s*git\s+${MUTATING}\b" || exit 0

# Allow if /commit skill has been loaded in this session
if [[ -n "$SESSION_ID" && -f "/tmp/claude-commit-skill-${SESSION_ID}" ]]; then
  exit 0
fi

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Mutating git commands require the /commit skill context. Run the /commit skill first (Skill tool with skill=\"commit\"), then retry."
  }
}'
exit 0
