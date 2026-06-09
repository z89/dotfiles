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

    # Only act on commands that actually run `git commit`.
    if not re.search(r"(^|&&|\|\||;|`|\$\()\s*git\s+commit\b", cmd):
        allow()

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
