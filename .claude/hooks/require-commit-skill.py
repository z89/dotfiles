#!/usr/bin/env python3
"""PreToolUse guard: mutating git needs the /commit rules loaded first.

The rules that make a commit acceptable here — SSH signing, no Claude
attribution trailer, the `changelog:` format, never push without approval in the
current session — live in ~/.claude/skills/commit/SKILL.md. A model that has not
read them will still produce a commit; it will just produce the wrong one, and
an unsigned or mis-attributed commit is a thing you have to rewrite history to
remove. So the gate is: load the skill, then git will move.

This replaces a shell version with three problems.

  1. It shelled out to `jq` and treated failure as "no command", so on a machine
     without jq every mutating git command was silently allowed. A guard that
     fails open is worse than no guard, because you stop checking.
  2. It matched a regex against the raw command string, so `bash -c "git push
     --force"` was invisible to it: there was no shell separator in front of
     `git`, so the pattern never fired.
  3. Its list of mutating subcommands was missing `clean`, `revert`, `branch`,
     `am`, `worktree`, `update-ref`, `gc` and `reflog` — `git clean -fd` and
     `git branch -D` both delete work and both went straight through.

Now: no external dependency, quote-aware parsing shared with the other guards,
and an explicit read-only list with everything else gated. Read-only git is
untouched — `status`, `log`, `diff`, `show`, `blame`, `rev-parse` and the
listing forms of `branch`, `tag`, `stash` and `remote` never prompt for
anything.

Exit 0 with a JSON deny = blocked. Exit 0 with no output = allowed.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _cmdparse import invocations, subcommand  # noqa: E402
import _marker  # noqa: E402

# Subcommands that cannot change the repository, the working tree or a remote.
READ_ONLY = {
    "annotate", "archive", "bisect", "blame", "bugreport", "bundle",
    "cat-file", "check-attr", "check-ignore", "check-mailmap",
    "check-ref-format", "cherry", "column", "count-objects", "describe",
    "diff", "diff-files", "diff-index", "diff-tree", "difftool", "fetch",
    "for-each-ref", "for-each-repo", "format-patch", "fsck",
    "get-tar-commit-id", "grep", "help", "interpret-trailers", "log",
    "ls-files", "ls-remote", "ls-tree", "mailinfo", "mailsplit", "merge-base",
    "merge-tree", "name-rev", "patch-id", "range-diff", "request-pull",
    "rev-list", "rev-parse", "shortlog", "show", "show-branch", "show-index",
    "show-ref", "status", "stripspace", "var", "verify-commit", "verify-pack",
    "verify-tag", "version", "whatchanged",
}

# Subcommands that are read-only only in some forms. Maps subcommand to the set
# of second words that are safe; anything else under them is gated. An empty
# string means the bare form lists rather than acts — true of `git remote` and
# `git notes`, but emphatically not of `git stash`, which is `stash push`.
READ_ONLY_UNDER = {
    "stash": {"list", "show"},
    "remote": {"", "show", "get-url"},
    "submodule": {"", "status", "summary"},
    "worktree": {"list"},
    "notes": {"", "list", "show"},
    "reflog": {"", "show"},
    "rerere": {"status", "diff", "remaining"},
    "sparse-checkout": {"list"},
    "lfs": {"ls-files", "status", "env", "version", "locks"},
    "maintenance": set(),
}

# `tag` and `branch` list far more often than they mutate, but they mutate
# destructively (`branch -D`, `tag -f`). Safe only with an explicit listing flag.
LISTING_FLAGS = {
    "-l", "--list", "-a", "--all", "-r", "--remotes", "-v", "-vv", "--verbose",
    "-n", "--contains", "--no-contains", "--merged", "--no-merged",
    "--points-at", "--sort", "--format", "--show-current", "-i",
    "--ignore-case", "--column", "--omit-empty",
}

# `git config` reads with one argument and writes with two, so the flags alone
# do not settle it. These force a write whatever else is on the line.
CONFIG_WRITE_FLAGS = {
    "--add", "--unset", "--unset-all", "--replace-all", "--set-all",
    "--edit", "-e", "--rename-section", "--remove-section",
}

# Applied only to inline code handed to a non-shell interpreter.
CODE_PATTERN = re.compile(
    r"\bgit\b[\s'\"\,\]\[)(-]{0,10}"
    r"(commit|push|reset|rebase|clean|checkout|revert|filter-branch|"
    r"filter-repo|update-ref|cherry-pick|merge|tag|branch|am|apply|stash|gc)\b",
    re.I,
)

DENY_TEMPLATE = (
    "Mutating git is gated: {situation}\n\n"
    "Blocked: `git {subcommand}`\n\n"
    "Load the commit rules first — invoke the Skill tool with skill=\"commit\" "
    "(or the user types /commit) — then retry. The rules cover SSH signing, the "
    "changelog message format, and the standing rule that nothing is pushed "
    "without the user's approval in this session.\n\n"
    "Read-only git is not gated and never needs this: status, log, diff, show, "
    "blame, rev-parse, fetch, and the listing forms of branch, tag, stash and "
    "remote."
)


def deny(situation, sub):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": DENY_TEMPLATE.format(
                situation=situation, subcommand=sub),
        }
    }))
    sys.exit(0)


def is_mutating(args):
    """Return the subcommand if this git invocation changes something."""
    sub, rest = subcommand(strip_global_options(args))
    if sub is None:
        return None  # bare `git`, or `git --version`

    if sub in READ_ONLY:
        return None

    if sub in READ_ONLY_UNDER:
        head = rest[0] if rest else ""
        if head in READ_ONLY_UNDER[sub]:
            return None
        return "{} {}".format(sub, head).strip()

    if sub in ("tag", "branch"):
        flags = [a for a in args if a.startswith("-")]
        if not rest and not [f for f in flags if f not in LISTING_FLAGS]:
            return None  # bare `git branch` / `git tag`, or listing flags only
        if any(f in LISTING_FLAGS or f.split("=")[0] in LISTING_FLAGS
               for f in flags):
            return None
        return sub

    if sub == "config":
        flags = [a.split("=")[0] for a in args if a.startswith("-")]
        if any(f in CONFIG_WRITE_FLAGS for f in flags):
            return "config"
        # `git config user.email` reads; `git config user.email x@y` writes.
        return "config" if len(rest) >= 2 else None

    return sub


def strip_global_options(args):
    """Drop `git`'s own options so the subcommand is found, not `-C`."""
    value_flags = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                   "--exec-path", "--super-prefix"}
    out, index = [], 0
    while index < len(args):
        token = args[index]
        if token in value_flags:
            index += 2
            continue
        if token.startswith("-"):
            index += 1
            continue
        out.extend(args[index:])
        break
    return out


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    if data.get("tool_name", "") != "Bash":
        sys.exit(0)

    command = (data.get("tool_input", {}) or {}).get("command", "") or ""
    if not command or not re.search(r"\bgit\b", command):
        sys.exit(0)

    found, code_blobs, _ = invocations(command)

    hit = None
    for base, args in found:
        if base != "git":
            continue
        sub = is_mutating(args)
        if sub:
            hit = sub
            break

    if hit is None:
        for blob in code_blobs:
            match = CODE_PATTERN.search(blob)
            if match:
                hit = match.group(1)
                break

    if hit is None:
        sys.exit(0)

    session = data.get("session_id") or os.environ.get("CLAUDE_CODE_SESSION_ID") or ""
    if not session:
        deny("this session has no id, so the gate cannot verify the skill was "
             "loaded, and it fails closed rather than guessing.", hit)

    status, age = _marker.state(session)
    if status == "armed":
        sys.exit(0)
    if status == "expired":
        deny("the /commit rules were loaded {:.0f} hours ago and that has "
             "expired.".format(age / 3600.0), hit)
    deny("the /commit skill has not been loaded in this session.", hit)


if __name__ == "__main__":
    main()
