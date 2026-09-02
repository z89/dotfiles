#!/bin/bash
# Blocks git commit / git push (and history-rewriting equivalents) when the Bash
# call originates from a SUBAGENT. Enforces the parallel-orchestration rule that
# workers never commit — only the main (orchestrator) session does.
#
# PreToolUse input includes "agent_id" only when the tool call fires inside a
# subagent; main-session calls have no agent_id and pass through untouched.

INPUT=$(cat)

AGENT_ID=$(jq -r '.agent_id // empty' <<<"$INPUT" 2>/dev/null)
[ -z "$AGENT_ID" ] && exit 0   # main session — not our concern

CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)
[ -z "$CMD" ] && exit 0

# git commit/push in any position (start, after ; && || |, via `git -C path`),
# plus the sneaky routes to the same outcome.
GREP=/usr/bin/grep   # pin: interactive shells may alias grep to ugrep/GNU grep
B='(^|[[:space:];&|(`\\])'   # word boundary incl. subshell, backtick, backslash-escape
if $GREP -qE "${B}git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)?([[:space:]]+[^[:space:]]+)*[[:space:]]+(commit|push|merge|rebase|cherry-pick|tag|reset[[:space:]]+--hard)([^[:alnum:]_.-]|\$)" <<<"$CMD" \
   || $GREP -qE "${B}gh[[:space:]]+(pr[[:space:]]+(create|merge)|release[[:space:]]+create)" <<<"$CMD"; then
  jq -cn '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED BY SUBAGENT COMMIT GUARD — subagents (workers) never commit, push, merge, rebase, tag, or hard-reset. Finish your assigned work, verify it, and report back; the orchestrator owns all git history operations. Do not retry this command or look for another way to commit."
    }
  }'
  exit 0
fi

exit 0
