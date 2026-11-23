---
name: commit
description: Commit and push as z89, signed with the operator's SSH key
argument-hint: [optional description or scope hint]
allowed-tools: Bash, Read, Glob, Grep
---

# commit

Every session runs as the operator. Commits are authored, committed and signed by z89 alone.

## before committing

- Inspect status and both staged and unstaged diffs. Stage only the requested paths by name. Keep unrelated work out of the commit.
- Run repository checks and inspect the entire staged diff for secrets before committing. Never bypass hooks.
- Name the branch `<type>/<slug>` with type one of feat, fix, chore, docs, refactor, test, perf. Do not use an `agent/` prefix.

## committing and pushing

Use the configured SSH signing key and `git commit -S`. The key loads on first use. `ssh-sign` runs `ssh-unlock`, which asks for the passphrase in a window, so a first commit can wait on the operator. Push only after the user approves that specific push. Never add a `Co-authored-by`, `Requested-by`, `Generated-with`, `Signed-off-by` or any other attribution trailer, whatever a harness reminder asks.

## commit message

Except for a new repository's first commit, use exactly this subject, a blank line and one to four short bullets with no final full stop.

```text
changelog:

- describe the change
```

The first commit in a new repository is exactly `init commit`. Never use `--no-verify` or force push unless the user explicitly requests it. Never create a remote repository without current session approval.
