#!/usr/bin/env python3
"""PreToolUse hook for the Bash tool.

Scans the content a `git commit` is about to record and blocks the commit if it
contains likely secrets/credentials or sensitive files. Runs regardless of
whether the /commit skill was loaded, so it is a backstop the model cannot skip.

Escape hatch: prefix the command with CLAUDE_ALLOW_SECRETS=1 to bypass (use only
for a deliberate, reviewed commit).
"""
import json
import os
import re
import subprocess
import sys


def allow():
    sys.exit(0)


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        allow()

    cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""
    cwd = data.get("cwd") or os.getcwd()

    # Optional git global options that may sit between `git` and the subcommand
    # (e.g. `git -C <dir> commit`, `git -c k=v commit`, `git --git-dir=… commit`).
    gitopts = (
        r"(?:\s+(?:-C\s+\S+|-c\s+\S+|--git-dir(?:=\S+|\s+\S+)|"
        r"--work-tree(?:=\S+|\s+\S+)|--namespace(?:=\S+|\s+\S+)|"
        r"--exec-path(?:=\S+)?|--paginate|--no-pager|-p|--bare|"
        r"--no-replace-objects|--literal-pathspecs|--no-optional-locks|"
        r"--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|"
        r"--no-advice|--no-lazy-fetch))*"
    )

    # Only act on commands that actually run `git commit`.
    m = re.search(r"(?:^|&&|\|\||;|`|\$\()\s*git" + gitopts + r"\s+commit\b", cmd)
    if not m:
        allow()

    # If the git invocation uses `-C <dir>`, scan that repo, not the shell cwd.
    cdir = re.search(r"-C\s+(\S+)", m.group(0))
    if cdir:
        p = cdir.group(1)
        cwd = p if os.path.isabs(p) else os.path.join(cwd, p)

    # Deliberate, reviewed override.
    if re.search(r"\bCLAUDE_ALLOW_SECRETS=1\b", cmd):
        allow()

    def git(args):
        try:
            r = subprocess.run(
                ["git"] + args, cwd=cwd,
                capture_output=True, text=True, timeout=15,
            )
            return r.stdout
        except Exception:
            return ""

    diff = git(["diff", "--cached"])
    names = [n for n in git(["diff", "--cached", "--name-only"]).splitlines() if n]

    # `git commit -a/--all` also sweeps tracked-but-unstaged modifications.
    if re.search(r"\bcommit\b[^\n]*?(?:\s-(?!-)\w*a\w*\b|\s--all\b)", cmd):
        diff += "\n" + git(["diff"])
        names += [n for n in git(["diff", "--name-only"]).splitlines() if n]

    if not diff and not names:
        allow()

    # Only inspect added lines (ignore context and removals).
    added = "\n".join(
        ln[1:] for ln in diff.splitlines()
        if ln.startswith("+") and not ln.startswith("+++")
    )

    placeholder = re.compile(
        r"(?i)(your[_-]?|example|changeme|placeholder|redacted|dummy|xxxx|"
        r"<[^>]+>|\$\{?[A-Z_]+\}?|\*\*\*\*)"
    )

    secret_patterns = [
        (r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----", "private key block"),
        (r"\bAKIA[0-9A-Z]{16}\b", "AWS access key id"),
        (r"\bASIA[0-9A-Z]{16}\b", "AWS temporary access key id"),
        (r"\bgh[pousr]_[0-9A-Za-z]{36,}\b", "GitHub token"),
        (r"\bgithub_pat_[0-9A-Za-z_]{22,}\b", "GitHub fine-grained PAT"),
        (r"\bxox[baprs]-[0-9A-Za-z-]{10,}\b", "Slack token"),
        (r"\bAIza[0-9A-Za-z\-_]{35}\b", "Google API key"),
        (r"\bsk-ant-[0-9A-Za-z\-_]{20,}\b", "Anthropic API key"),
        (r"\bsk-[0-9A-Za-z]{32,}\b", "OpenAI-style secret key"),
        (r"\beyJ[0-9A-Za-z_-]{10,}\.[0-9A-Za-z_-]{10,}\.[0-9A-Za-z_-]{10,}\b", "JWT"),
        (r"\b[a-z][a-z0-9+.-]*://[^\s:@/]+:[^\s:@/]+@[^\s/]+", "URL with embedded credentials"),
    ]

    # name=value style credential, with a non-placeholder value of real length.
    cred_assign = re.compile(
        r"(?i)\b(?:api[_-]?key|secret[_-]?key|secret|access[_-]?token|auth[_-]?token|"
        r"client[_-]?secret|password|passwd|passphrase|private[_-]?key|bearer)\b"
        r"\s*[:=]\s*[\"']?([^\s\"'#]{12,})"
    )

    findings = []

    for pat, label in secret_patterns:
        m = re.search(pat, added)
        if m:
            findings.append(f"{label}")

    for m in cred_assign.finditer(added):
        val = m.group(1)
        if not placeholder.search(val):
            findings.append("hardcoded credential assignment")
            break

    # Sensitive filenames being committed.
    env_ok = (".example", ".sample", ".template", ".dist", ".defaults")
    sensitive_file = [
        (r"(^|/)\.env$", ".env file"),
        (r"(^|/)\.env\.[\w.-]+$", ".env.* file"),
        (r"\.pem$", "PEM file"),
        (r"\.key$", "key file"),
        (r"\.p12$", "PKCS#12 keystore"),
        (r"\.pfx$", "PFX keystore"),
        (r"(^|/)id_(rsa|dsa|ecdsa|ed25519)$", "SSH private key"),
        (r"(^|/)credentials(\.json)?$", "credentials file"),
        (r"(^|/)(token|auth)\.json$", "token/auth file"),
        (r"(^|/)settings\.local\.json$", "settings.local.json"),
        (r"(^|/)\.npmrc$", ".npmrc (may carry tokens)"),
        (r"(^|/)\.pgpass$", ".pgpass file"),
        (r"(^|/)\.(bash|zsh)_history$", "shell history file"),
        (r"(^|/)secrets?\.(ya?ml|json|toml|env)$", "secrets config file"),
    ]
    for n in names:
        base = n.rsplit("/", 1)[-1]
        if base.startswith(".env") and base.endswith(env_ok):
            continue
        for pat, label in sensitive_file:
            if re.search(pat, n):
                findings.append(f"sensitive file: {n} ({label})")
                break

    # Project-specific paths must never reach this (public) repo. All real
    # project work lives under ~/Documents; the only intentional exceptions are
    # the ycombo/hyprlax desktop integrations referenced from the hypr config.
    docs_prefix = os.path.expanduser("~/Documents/")
    proj_exceptions = ("ycombo", "hyprlax")
    for ln in added.splitlines():
        if docs_prefix in ln and not any(x in ln for x in proj_exceptions):
            findings.append("project path under ~/Documents in a tracked file")
            break

    # Extra keyword/regex denylist, kept OUT of the tracked repo so the terms
    # themselves never leak (~/.claude/secret-denylist.txt; one pattern per
    # line, '#' for comments, matched case-insensitively against additions).
    denylist = os.path.expanduser("~/.claude/secret-denylist.txt")
    if os.path.isfile(denylist):
        try:
            with open(denylist) as fh:
                patterns = [s.strip() for s in fh
                            if s.strip() and not s.lstrip().startswith("#")]
        except Exception:
            patterns = []
        for p in patterns:
            try:
                hit = re.search(p, added, re.IGNORECASE)
            except re.error:
                hit = p.lower() in added.lower()
            if hit:
                findings.append(f"denylisted term ({p}) from secret-denylist.txt")
                break

    if findings:
        uniq = []
        for f in findings:
            if f not in uniq:
                uniq.append(f)
        bullet = "\n".join(f"  - {f}" for f in uniq)
        deny(
            "Commit blocked by git-secret-scan: the staged change appears to "
            "contain secrets or sensitive files:\n" + bullet +
            "\n\nRemove the secret / unstage the file (and add it to .gitignore), "
            "then retry. If this is a false positive and the content is safe to "
            "commit, re-run the exact command prefixed with CLAUDE_ALLOW_SECRETS=1."
        )

    allow()


if __name__ == "__main__":
    main()
