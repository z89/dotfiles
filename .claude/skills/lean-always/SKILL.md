---
name: lean-always
description: Toggle persistent lean mode. A hook then injects a compact token-saving directive on every prompt in every session until turned off. Use when the user invokes /lean-always, /lean-always on, /lean-always off, or /lean-always status.
argument-hint: [on|off|status]
allowed-tools: Bash
---

# /lean-always

Flag file: `~/.claude/lean.on`. Hook: `~/.claude/hooks/lean-mode.sh` (UserPromptSubmit).

Run exactly one command based on `$ARGUMENTS` (default: `on`), then reply in one line.

- `on`: `touch ~/.claude/lean.on` → reply `lean mode ON (every prompt, all sessions). /lean-always off to disable.`
- `off`: `rm -f ~/.claude/lean.on` → reply `lean mode OFF.`
- `status`: `test -f ~/.claude/lean.on && echo ON || echo OFF` → reply with the result.

While the flag is on, this very turn is already lean: obey the injected directive. No other output.
