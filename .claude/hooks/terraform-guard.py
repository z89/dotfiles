#!/usr/bin/env python3
"""PreToolUse guard: no AI session runs a destructive terraform command.

One `terraform destroy` against a live profile deletes real infrastructure and
there is no undo. The permission deny-list in settings.json states the same rule
and is the layer that shows up in the permissions UI, but it matches on the
start of the command string, so `cd infra && terraform destroy` slips past it —
and `--dangerously-skip-permissions` ignores allow and deny entirely. PreToolUse
hooks still run in that mode. This file is the layer that holds when the others
have been bypassed.

WHAT IS BLOCKED
---------------
Commands that change infrastructure, rewrite state, or re-point where state
lives: apply, destroy, import, init, get, taint, untaint, refresh, test,
force-unlock, login, logout, the mutating halves of `state`, `workspace` and
`providers`, and any command carrying a flag that removes a safety check
(-auto-approve, -migrate-state, -force-copy, -reconfigure, -lock=false).

`init` is blocked despite looking like setup. It binds the directory to a
backend and rewrites `.terraform.lock.hcl`, and it is the only command that can
silently change *which state file the directory is talking to*. With
`-migrate-state` it copies state to a new backend; with `-reconfigure` it
re-points without copying, so the next `plan` reads an empty state and offers to
create everything that already exists. In a repository whose local state file is
the only record of a live AWS organization, that is the worst outcome available,
and it does not look destructive on the command line.

WHAT IS ALLOWED
---------------
`plan`, `validate`, `fmt`, `show`, `output`, `graph`, `console`, `version`,
`metadata`, `providers` and `providers schema`, `state list|show|pull`, and
`workspace list|show|select`. `terraform plan -destroy` is allowed: it is a
read-only preview and the safest way to see what a destroy would do.

`fmt` is allowed although it rewrites .tf files. Formatting is part of writing
terraform, it is idempotent, and it shows up in `git diff` like any other edit.

This is deliberately narrower than the default-deny policy it replaces, which
blocked every subcommand it had not heard of. The trade is stated plainly: a
destructive subcommand added by a future terraform release would not be
recognised here until this list is updated. The dangerous-flag rules below catch
most shapes such a command could take.

Blocking is unconditional. There is deliberately no environment-variable escape
hatch, because an escape hatch is the thing an agent reaches for when a command
fails. The operator runs these commands themselves, in their own terminal.

Exit 0 = allow, exit 2 = block (stderr is returned to Claude).
"""
import json
import os
import re
import sys

# Resolve siblings relative to this file, not to a fixed path, so the guard
# works unchanged whether it lives in ~/.claude/hooks or inside a plugin
# directory that moves on every update.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _cmdparse import invocations, subcommand  # noqa: E402

BINARIES = {"terraform", "tofu", "opentofu", "terragrunt"}

DESTRUCTIVE = {
    "apply": "creates, changes and deletes real infrastructure",
    "destroy": "deletes every resource recorded in the state",
    "import": "binds a live resource into state and rewrites it",
    "init": ("binds the directory to a backend and rewrites the provider lock "
             "file — it can migrate state to a different backend, or with "
             "-reconfigure re-point at an empty one and orphan what is there"),
    "get": "downloads modules into .terraform/, which is the module half of init",
    "taint": "marks a resource for destruction on the next apply",
    "untaint": "rewrites state to clear a replacement mark",
    "refresh": "rewrites state from live infrastructure",
    "test": "creates and then destroys real infrastructure to run assertions",
    "force-unlock": "removes a state lock another operation still holds",
    "login": "writes a credentials token to disk",
    "logout": "deletes a stored credentials token",
}

STATE_DESTRUCTIVE = {
    "mv": "moves a resource to a different address in state",
    "rm": "removes a resource from state, orphaning the real infrastructure",
    "push": "overwrites remote state wholesale",
    "replace-provider": "rewrites every provider reference in state",
}
STATE_READ_ONLY = {"list", "show", "pull"}

WORKSPACE_DESTRUCTIVE = {
    "new": "creates a new state",
    "delete": "deletes a workspace and its state",
}
WORKSPACE_READ_ONLY = {"list", "show", "select"}

PROVIDERS_DESTRUCTIVE = {
    "lock": "rewrites .terraform.lock.hcl, changing which provider builds are trusted",
    "mirror": "writes a local provider mirror to disk",
}
PROVIDERS_READ_ONLY = {"", "schema"}

# Flags that remove a safety check, whatever subcommand they are attached to.
# `-destroy` is absent on purpose: `terraform plan -destroy` is a read-only
# preview, and `terraform apply -destroy` is already caught by the subcommand.
DANGEROUS_FLAGS = [
    ("-auto-approve", "it removes the last human checkpoint"),
    ("-migrate-state", "it moves state to a different backend"),
    ("-force-copy", "it copies state between backends without confirmation"),
    ("-reconfigure", "it re-points the backend without migrating, orphaning the state"),
    ("-lock=false", "it disables state locking, which corrupts concurrent state"),
]

# Applied only to inline code handed to a non-shell interpreter, where proper
# tokenization is impossible. Confined there so it cannot fire on prose.
CODE_PATTERN = re.compile(
    r"\b(?:terraform|tofu|opentofu|terragrunt)\b[\s'\"\,\]\[)(]{0,8}"
    r"(apply|destroy|import|taint|force-unlock)\b",
    re.I,
)


def block(reason, detail=""):
    sys.stderr.write(
        "BLOCKED by terraform-guard: {}\n\n"
        "No AI session may run a destructive terraform command. This is a hard "
        "block with no override flag — mutating or deleting live infrastructure "
        "is not a risk that gets delegated to an agent.\n\n"
        "{}"
        "`plan`, `validate`, `fmt`, `show`, `output`, `graph` and the read-only "
        "halves of `state`, `workspace` and `providers` are all allowed. Use "
        "`terraform plan` (or `plan -destroy`) and read the diff.\n\n"
        "`init` is blocked too: it re-points which state file this directory "
        "talks to. If a directory needs initialising, the operator runs `init` "
        "themselves, once, and then `plan` works here.\n".format(
            reason, (detail + "\n\n") if detail else ""
        )
    )
    sys.exit(2)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    if data.get("tool_name", "") != "Bash":
        sys.exit(0)

    command = (data.get("tool_input", {}) or {}).get("command", "") or ""
    if not command:
        sys.exit(0)

    # Cheap pre-filter: no governed binary named anywhere, not our business.
    if not re.search(r"\b(?:terraform|tofu|opentofu|terragrunt)\b", command, re.I):
        sys.exit(0)

    found, code_blobs, _ = invocations(command)

    for blob in code_blobs:
        match = CODE_PATTERN.search(blob)
        if match:
            block(
                "inline code passed to an interpreter runs `{}`.".format(
                    " ".join(match.group(0).split())
                ),
                "Wrapping a terraform command in another language does not make "
                "it a different command.",
            )

    for base, args in found:
        if base not in BINARIES:
            continue

        joined = " ".join(args).lower()
        for flag, why in DANGEROUS_FLAGS:
            if flag in joined:
                block("`{}` — {}.".format(flag, why),
                      "Command: {}".format(command.strip()))

        sub, rest = subcommand(args)
        if sub is None:
            continue  # bare `terraform`, or global flags only

        # terragrunt fans a subcommand out across every unit.
        if base == "terragrunt" and sub in ("run-all", "run"):
            sub = rest[0] if rest else None
            rest = rest[1:]
            if sub is None:
                continue

        if sub in DESTRUCTIVE:
            block("`{} {}` {}.".format(base, sub, DESTRUCTIVE[sub]),
                  "Command: {}".format(command.strip()))

        if sub == "state":
            head = rest[0] if rest else None
            if head in STATE_READ_ONLY:
                continue
            if head in STATE_DESTRUCTIVE:
                block("`{} state {}` {}.".format(base, head, STATE_DESTRUCTIVE[head]),
                      "Command: {}".format(command.strip()))
            block("`{} state {}` is not a read-only state command.".format(
                base, head or "<none>"),
                "Read-only: {}.".format(", ".join(sorted(STATE_READ_ONLY))))

        if sub == "workspace":
            head = rest[0] if rest else None
            if head in WORKSPACE_READ_ONLY:
                continue
            if head in WORKSPACE_DESTRUCTIVE:
                block("`{} workspace {}` {}.".format(
                    base, head, WORKSPACE_DESTRUCTIVE[head]),
                    "Command: {}".format(command.strip()))

        if sub == "providers":
            head = rest[0] if rest else ""
            if head in PROVIDERS_READ_ONLY:
                continue
            if head in PROVIDERS_DESTRUCTIVE:
                block("`{} providers {}` {}.".format(
                    base, head, PROVIDERS_DESTRUCTIVE[head]),
                    "Command: {}".format(command.strip()))

    sys.exit(0)


if __name__ == "__main__":
    main()
