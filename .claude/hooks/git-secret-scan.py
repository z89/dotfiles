#!/usr/bin/env python3
"""PreToolUse hook for the Bash tool.

Scans the content a `git commit` is about to record and every outgoing commit a
`git push` is about to publish. Blocks likely secrets, credentials, and
sensitive files regardless of whether the commit skill was loaded.

There is deliberately NO escape hatch. An override flag is the thing an agent
reaches for when a commit is refused, and a scanner that can be waved past is
not a scanner. A genuine false positive is resolved by adding the offending
term to that repository's .claude/secret-scan-allow.txt, which is reviewable
and scoped, unlike a one-off bypass nobody sees again.
"""
import json
import os
import re
import shlex
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


def has_shell_composition(command):
    """Return whether a git commit command contains unquoted shell control."""
    quote = None
    escaped = False
    for index, char in enumerate(command):
        if escaped:
            escaped = False
            continue
        if char == "\\" and quote != "'":
            escaped = True
            continue
        if quote:
            if char == quote:
                quote = None
            elif quote == '"' and char == "`":
                return True
            elif quote == '"' and char == "$" and command[index:index + 2] == "$(":
                return True
            continue
        if char in ("'", '"'):
            quote = char
        elif char in "\r\n;|&<>`":
            return True
        elif char == "$" and command[index:index + 2] == "$(":
            return True
        elif char in "()":
            return True
    return False


def read_message_file(path, cwd):
    """Return the contents of a `-F <file>` commit message, or None if unreadable."""
    if path == "-":
        return None  # message arrives on stdin; nothing to read here
    full = path if os.path.isabs(path) else os.path.join(cwd, path)
    try:
        with open(full, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except Exception:
        return None


def commit_message(command, start, cwd):
    """Return the message text this commit would record, or None if unparseable.

    ONLY the message is returned -- never the whole command line.

    The message belongs in the scan: a credential pasted into a commit message is
    published exactly as surely as one inside a file. But scanning the raw command
    string swept in every flag value too, so an ordinary invocation like

        git -C ~/Documents/<project> commit -S -F msg.txt

    was refused by the "project path under ~/Documents" rule below -- matched on
    its own `-C` argument, with nothing wrong in the staged content at all. A guard
    with no bypass cannot afford false positives, so the message is now extracted
    properly instead.

    Reading `-F` files is also a genuine gain: their contents were previously never
    scanned, because only the path appeared in the command.
    """
    try:
        words = shlex.split(command[start:])
    except ValueError:
        return None

    parts = []
    index = 0
    while index < len(words):
        word = words[index]
        takes_value = word in ("-m", "--message", "-F", "--file")
        if takes_value:
            if index + 1 >= len(words):
                return None
            value = words[index + 1]
            parts.append(value if word in ("-m", "--message")
                         else read_message_file(value, cwd))
            index += 2
            continue
        for prefix, is_file in (("--message=", False), ("--file=", True)):
            if word.startswith(prefix):
                value = word[len(prefix):]
                parts.append(read_message_file(value, cwd) if is_file else value)
                break
        else:
            # Attached short forms: -mMESSAGE, -Fmsg.txt
            if len(word) > 2 and word[0] == "-" and word[1] in "mF":
                value = word[2:]
                parts.append(value if word[1] == "m"
                             else read_message_file(value, cwd))
        index += 1

    # An amend or an editor-driven commit exposes no message here. That is fine:
    # an amended message was already scanned when it was first written.
    return "\n".join(p for p in parts if p)


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

    # Find a commit or push anywhere first so composed tool calls cannot hide
    # it. The operation is accepted only when it is the sole shell command. The
    # scanner runs before Bash, so allowing `git add` (or a file write) before
    # `git commit` in one payload would inspect the old index and miss what the
    # earlier command is about to stage.
    git_binary = r"(?:git|/(?:usr/)?bin/git)"
    any_operation = re.search(
        r"(?:^|&&|\|\||\||&|;|`|\$\(|\(|\{)\s*" + git_binary
        + gitopts + r"\s+(?:commit|push)\b",
        cmd,
        re.MULTILINE,
    )
    socket = r"(?:/run/user/1000/ssh-agent\.socket|"
    socket += r"\"/run/user/1000/ssh-agent\.socket\"|"
    socket += r"'/run/user/1000/ssh-agent\.socket')"
    signing_prefix = (
        r"(?:SSH_AUTH_SOCK=" + socket + r"\s+|"
        r"export\s+SSH_AUTH_SOCK=" + socket + r"\s*&&\s*)?"
    )
    standalone = re.match(
        r"^\s*" + signing_prefix + r"(?P<git>" + git_binary + r")" + gitopts
        + r"\s+(?P<operation>commit|push)\b",
        cmd,
    )

    if not any_operation and not standalone:
        allow()
    if not standalone or has_shell_composition(cmd[standalone.start("git"):].strip()):
        deny(
            "Git operation blocked by git-secret-scan: run `git commit` or `git push` "
            "as a standalone Bash tool call. This lets the scanner inspect the exact "
            "content being committed or pushed. Do not combine it with other commands, pipes, "
            "redirections, command substitutions, or backticks."
        )

    m = standalone
    operation = m.group("operation")

    # If the git invocation uses `-C <dir>`, scan that repo, not the shell cwd.
    cdir = re.search(r"-C\s+(\S+)", m.group(0))
    if cdir:
        p = cdir.group(1)
        cwd = p if os.path.isabs(p) else os.path.join(cwd, p)

    def git(args):
        try:
            r = subprocess.run(
                ["git"] + args, cwd=cwd,
                capture_output=True, text=True, timeout=15,
            )
            return r.returncode, r.stdout
        except Exception:
            return 1, ""

    if operation == "commit":
        metadata = commit_message(cmd, m.start("git"), cwd)
        if metadata is None:
            deny(
                "Commit blocked by git-secret-scan: unable to parse the commit "
                "command safely, so the message could not be scanned. Pass the "
                "message with `-m` or `-F <file>`."
            )
        _, diff = git(["diff", "--cached"])
        _, name_output = git(["diff", "--cached", "--name-only"])
        names = [n for n in name_output.splitlines() if n]

        # `git commit -a/--all` also sweeps tracked-but-unstaged modifications.
        if re.search(r"\bcommit\b[^\n]*?(?:\s-(?!-)\w*a\w*\b|\s--all\b)", cmd):
            _, unstaged_diff = git(["diff"])
            _, unstaged_names = git(["diff", "--name-only"])
            diff += "\n" + unstaged_diff
            names += [n for n in unstaged_names.splitlines() if n]
    else:
        try:
            words = shlex.split(cmd[m.start("git"):])
        except ValueError:
            deny("Push blocked by git-secret-scan: unable to parse the git push command safely.")

        push_index = words.index("push")
        push_args = words[push_index + 1:]
        targets = []
        positional = []
        value_options = {"--receive-pack", "--exec", "--repo", "--push-option", "-o"}
        skip_value = False
        for word in push_args:
            if skip_value:
                skip_value = False
                continue
            if word in value_options:
                skip_value = True
                continue
            if word.startswith("-"):
                continue
            positional.append(word)

        refspecs = positional[1:] if positional else []
        if "--mirror" in push_args:
            targets = ["--all"]
        else:
            if "--all" in push_args:
                targets.append("--branches")
            if "--tags" in push_args:
                targets.append("--tags")
            for refspec in refspecs:
                source = refspec.split(":", 1)[0]
                if not source:  # Deleting a remote ref sends no local content.
                    continue
                if "*" in source:
                    deny(
                        "Push blocked by git-secret-scan: wildcard refspecs cannot be "
                        "scanned safely. Push explicit branches or tags instead."
                    )
                targets.append(source.lstrip("+"))
            if not targets:
                targets = ["HEAD"]

        # Scan every commit that is reachable from the pushed refs but from no
        # locally known remote-tracking ref. This catches secrets added and then
        # removed in an earlier outgoing commit, not merely the final tree diff.
        rev_args = targets + ["--not", "--remotes"]
        diff_rc, diff = git(["log", "--format=", "--patch", "--no-ext-diff"] + rev_args)
        message_rc, metadata = git(["log", "--format=%B"] + rev_args)
        names_rc, name_output = git(["log", "--format=", "--name-only"] + rev_args)
        if diff_rc or message_rc or names_rc:
            deny(
                "Push blocked by git-secret-scan: unable to determine and scan the "
                "outgoing commits. Push explicit local branches or tags after fixing "
                "the Git ref or repository error."
            )
        names = [n for n in name_output.splitlines() if n]

    if not diff and not names:
        allow()

    # Only inspect added lines (ignore context and removals).
    added = metadata + "\n" + "\n".join(
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
        # A repo may exempt specific denylist patterns it legitimately contains, by
        # listing them in .claude/secret-scan-allow.txt. The denylist exists to stop
        # work-internal terms reaching the PUBLIC dotfiles repo; inside the private repo
        # those same terms are the module path and appear on every line, so without
        # this the scanner would refuse every commit in that repo — and a guard that
        # always fires is a guard people find a way around.
        #
        # This narrows the keyword denylist ONLY. Private keys, credential patterns and
        # sensitive files are checked above and cannot be exempted by a repo, so a repo
        # can never opt out of the checks that actually matter.
        exempt = []
        allowfile = os.path.join(cwd, ".claude", "secret-scan-allow.txt")
        if os.path.isfile(allowfile):
            try:
                with open(allowfile) as fh:
                    exempt = [s.strip() for s in fh
                              if s.strip() and not s.lstrip().startswith("#")]
            except Exception:
                exempt = []

        for p in patterns:
            if p in exempt:
                continue
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
            f"{operation.capitalize()} blocked by git-secret-scan: the change appears to "
            "contain secrets or sensitive files:\n" + bullet +
            "\n\nRemove the secret and unstage the file, or remove it from the "
            "outgoing Git history before retrying. Add sensitive files to .gitignore. "
            "If this is a false positive, add the offending term to "
            "this repository's .claude/secret-scan-allow.txt -- that is reviewable "
            "and scoped. There is no bypass flag."
        )

    allow()


if __name__ == "__main__":
    main()
