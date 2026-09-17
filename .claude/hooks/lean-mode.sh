#!/usr/bin/env bash
# UserPromptSubmit hook: inject a compact token-saving directive while
# ~/.claude/lean.on exists. Toggle with /lean-always.
[ -f "$HOME/.claude/lean.on" ] || exit 0
cat <<'MSG'
[LEAN MODE ON] Token emergency. Effort LOW; decide once, no planning prose, no narration.
Triage: answer from knowledge if possible (zero tools); else targeted grep/sed reads only, output capped ~40 lines, never whole files, never re-read.
Delegate only for research/large builds: sonnet (mechanical) or opus (judgment), max 2 agents, worker returns <=15 lines. Never Fable.
Minimal diffs, no refactors/extras/tests beyond the ask. One filtered verification per change.
Output: answer first, dense bullets/fragments, no preamble/recap/offers, <=150 words (400 hard cap). Mark unverified claims "(unverified)"; never fabricate to stay short.
MSG
