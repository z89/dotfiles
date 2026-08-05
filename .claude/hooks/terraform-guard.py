#!/usr/bin/env python3
"""PreToolUse guard: no AI session ever runs a state-changing terraform command.

This exists because a single `terraform destroy` against a production profile
wipes real infrastructure and there is no undo. The permission allowlist is not
a sufficient control on its own — it is easy to widen by accident (a `terraform
destroy *` wildcard once lived in settings.json), and `--dangerously-skip-
permissions` ignores it entirely. PreToolUse hooks still run in that mode, so
this file is the backstop that holds when everything else has been bypassed.

Policy is DEFAULT DENY. Every terraform/tofu/terragrunt invocation is blocked
unless its subcommand is in READ_ONLY below. A subcommand nobody anticipated —
or a new one added by a future terraform release — is therefore blocked, not
waved through. Read-only calls that survive are still subject to the normal
permission prompt; this hook never grants anything, it only takes away.

Blocking is unconditional: there is deliberately no environment-variable escape
hatch, because an escape hatch is the thing an agent reaches for when a command
fails. The user runs these commands themselves, in their own terminal.

Exit 0 = allow, exit 2 = block (stderr goes back to Claude).
Fails CLOSED for terraform: if the command mentions terraform and cannot be
parsed, it is blocked. Unrelated tool calls always pass.
"""
import json
import re
import sys

# Subcommands that only read. Everything else is denied.
# `init` is absent on purpose: it writes .terraform/, can run provider code, and
# with -migrate-state/-reconfigure it rewrites backend state.
READ_ONLY = {
    "validate", "fmt", "version", "providers", "graph",
    "output", "show", "plan", "console", "test", "metadata",
}

# state subcommands that only read; `state` alone is not enough to judge.
STATE_READ_ONLY = {"list", "show", "pull"}

# Binaries this guard governs.
BINARIES = {"terraform", "tofu", "opentofu", "terragrunt", "tf"}

# Anything matching these is blocked regardless of subcommand parsing.
HARD_PATTERNS = [
    (r"-auto-approve", "-auto-approve removes the last human checkpoint"),
    (r"-force\b", "-force overrides safety checks"),
    (r"\bdestroy\b", "destroy deletes real infrastructure"),
]

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if data.get("tool_name", "") != "Bash":
    sys.exit(0)

cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""
if not cmd:
    sys.exit(0)

# Cheap pre-filter: if no governed binary is named at all, this is not our business.
if not re.search(r"\b(?:terraform|tofu|opentofu|terragrunt)\b", cmd, re.I):
    sys.exit(0)


def block(reason: str, detail: str = ""):
    sys.stderr.write(
        "BLOCKED by terraform-guard: {}\n\n"
        "No AI session may run state-changing terraform. This is a hard block "
        "with no override flag — destroying or mutating live infrastructure is "
        "not a risk that gets delegated to an agent.\n\n"
        "{}"
        "Run it yourself in your own terminal if you actually intend it. In this "
        "session, prefer `terraform plan` and read the diff instead.\n".format(
            reason, (detail + "\n\n") if detail else ""
        )
    )
    sys.exit(2)


# ---------------------------------------------------------------------------
# Paranoid sweep, run BEFORE any structured parsing.
#
# The tokenizer below only inspects command position, so it cannot see through
# `bash -c '...'`, `eval`, or quoting games. This sweep does not care about
# structure at all: if a governed binary appears anywhere with a mutating
# subcommand after it, the call dies here.
#
# It will occasionally block something harmless, like grepping the docs for the
# literal string. That trade is intentional and not worth tuning away — a
# false positive costs one reworded grep, a false negative costs the business.
# ---------------------------------------------------------------------------
MUTATING = (
    r"destroy|apply|import|taint|untaint|force-unlock|init|refresh|"
    r"state\s+(?:rm|mv|push|replace-provider)|"
    r"workspace\s+(?:new|delete|select)"
)
SWEEP = re.compile(
    r"\b(?:terraform|tofu|opentofu|terragrunt|tf)\b"
    r"(?:\s+(?:run-all|--?\S+))*"      # -chdir=..., run-all, other flags
    r"\s+(?:" + MUTATING + r")\b",
    re.I,
)
m = SWEEP.search(cmd)
if m:
    block(
        "the command contains `{}`.".format(" ".join(m.group(0).split())),
        "Command: {}".format(cmd.strip()),
    )

# Ignore text that is plainly not an invocation: a path, a comment, a grep
# pattern. We only care about a governed binary appearing in command position.
# Split on shell separators so `cd x && terraform destroy` and
# `nohup timeout 90 terraform apply` are both reached.
SEPARATORS = r"(?:\|\||&&|\||;|\n|\$\(|`|<\()"
segments = re.split(SEPARATORS, cmd)

# Command-position wrappers that precede the real binary.
WRAPPERS = {
    "nohup", "timeout", "sudo", "env", "time", "stdbuf", "nice", "ionice",
    "xargs", "command", "exec", "doas", "setsid",
}

for seg in segments:
    tokens = seg.strip().split()
    i = 0
    # Step over `VAR=value` prefixes and wrapper commands to find the binary.
    while i < len(tokens):
        t = tokens[i]
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", t):
            i += 1
            continue
        base = t.split("/")[-1]
        if base in WRAPPERS:
            i += 1
            # skip a numeric arg to timeout, and flags to wrappers
            while i < len(tokens) and (
                re.fullmatch(r"[0-9]+[smhd]?", tokens[i]) or tokens[i].startswith("-")
            ):
                i += 1
            continue
        break

    if i >= len(tokens):
        continue

    base = tokens[i].split("/")[-1]
    if base not in BINARIES:
        continue

    args = tokens[i + 1:]
    seg_l = seg.lower()

    # Unconditional patterns first — these never need subcommand context.
    for pat, why in HARD_PATTERNS:
        if re.search(pat, seg_l):
            block("`{}` in a terraform command — {}.".format(pat.strip("\\b-"), why),
                  "Command: {}".format(seg.strip()))

    # Find the subcommand: first token that is not a global flag.
    sub = None
    rest = []
    for j, a in enumerate(args):
        if a.startswith("-"):
            continue  # -chdir=..., -help, -version
        sub = a.lower()
        rest = [x.lower() for x in args[j + 1:] if not x.startswith("-")]
        break

    if sub is None:
        # Bare `terraform` or only global flags — harmless, let it prompt.
        continue

    if sub == "state":
        substate = rest[0] if rest else None
        if substate in STATE_READ_ONLY:
            continue
        block(
            "`terraform state {}` mutates or exports state.".format(substate or "<none>"),
            "Command: {}".format(seg.strip()),
        )

    if sub == "workspace":
        if rest and rest[0] in ("list", "show"):
            continue
        block("`terraform workspace {}` changes which state is live.".format(
            rest[0] if rest else "<none>"), "Command: {}".format(seg.strip()))

    if sub in READ_ONLY:
        continue

    block(
        "`terraform {}` is not a read-only subcommand.".format(sub),
        "Command: {}\n\nRead-only subcommands allowed through this guard "
        "(they still require your approval): {}".format(
            seg.strip(), ", ".join(sorted(READ_ONLY))
        ),
    )

sys.exit(0)
