#!/usr/bin/env bash
# Accident guard for direct git/gh commands run by subagents; it is not a shell sandbox.
exec python3 - 3<&0 <<'PY'
import json, os, re, shlex, sys

BLOCKED = {"commit", "push", "pull", "merge", "rebase", "cherry-pick", "am", "tag", "reset",
           "revert", "stash", "clean", "checkout", "switch", "restore", "update-ref"}
GH_BLOCKED = (["pr", "create"], ["pr", "merge"], ["release", "create"])
VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--exec-path"}
PREFIXES = {"env", "command", "exec", "nohup", "time", "{", "!", "if", "then", "else", "elif",
            "do", "while", "until"}
SEPS = set(";&|()`\n")
ASSIGN = re.compile(r"[A-Za-z_]\w*=")
# Fallback when shlex cannot parse (for example an unbalanced apostrophe in a heredoc body).
RX_GIT = re.compile(r"^\s*(?:(?:env|command|exec|nohup|time|[{!])\s+|[A-Za-z_]\w*=\S*\s+)*"
                    r"[\"']?(?:\S*/)?git[\"']?(?:\s+(?:-C|-c|--git-dir|--work-tree|--namespace|"
                    r"--config-env|--exec-path)\s+\S+|\s+-\S+)*\s+[\"']?(%s)[\"']?(?=\s|$)"
                    % "|".join(map(re.escape, sorted(BLOCKED))))
RX_GH = re.compile(r"^\s*(?:\S*/)?gh\s+(?:pr\s+(?:create|merge)|release\s+create)(?=\s|$)")

def deny():
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": "Workers never change git history or discard, stash or "
            "switch files in the shared checkout. Report to the orchestrator; do not retry another way."}}))
    sys.exit(0)

def blocked_at(tokens, i):
    """tokens[i] is in command position; skip prefixes, then test git/gh."""
    while i < len(tokens) and (tokens[i] in PREFIXES or ASSIGN.match(tokens[i])
                               or (i and tokens[i - 1] == "env" and tokens[i].startswith("-"))):
        i += 1
    if i >= len(tokens):
        return False
    name, j = os.path.basename(tokens[i]), i + 1
    if name == "gh":
        return tokens[j:j + 2] in GH_BLOCKED
    if name != "git":
        return False
    while j < len(tokens) and tokens[j].startswith("-"):
        if tokens[j] in ("--help", "--version"):
            return False
        j += 2 if tokens[j] in VALUE_OPTS else 1  # unknown options count as plain flags
    return j < len(tokens) and tokens[j] in BLOCKED

try:
    with os.fdopen(3) as stream:
        data = json.load(stream)
    command = data["tool_input"]["command"]
except Exception:
    sys.exit(0)  # invalid or unexpected input: never block unrelated tools
if not data.get("agent_id") or not isinstance(command, str):
    sys.exit(0)
if "git" not in command and "gh" not in command:
    sys.exit(0)
try:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()`\n")
    lexer.whitespace, lexer.whitespace_split = " \t\r", True
    tokens = list(lexer)
except ValueError:
    if any(RX_GIT.match(s) or RX_GH.match(s) for s in re.split(r"[;&|()`\n]", command)):
        deny()
    sys.exit(0)
for i, tok in enumerate(tokens):
    if tok and not set(tok) <= SEPS and (i == 0 or (tokens[i - 1] and set(tokens[i - 1]) <= SEPS)):
        if blocked_at(tokens, i):
            deny()
PY
