---
name: commit
description: Stage and commit changes using the project changelog format, signed only by the z89 GitHub account
argument-hint: [optional description or scope hint]
allowed-tools: Bash, Read, Glob, Grep
---

# Git Commit

You are committing changes to a git repository on behalf of the user's z89 GitHub account.

## Rules

- NEVER add "Co-authored-by", "Co-signed-by", or any Claude attribution trailer to the commit message.
- The commit must be authored solely by the git user already configured in the repo or globally (z89 GitHub account). Do not alter git user config.
- Do NOT use `--no-verify` unless the user explicitly asks.
- Do NOT force-push unless the user explicitly asks.
- NEVER push to a remote (`git push`, `gh repo`, etc.) without explicit user approval in the current session — even if the user previously said "push it" in a prior session.
- NEVER create a remote repository (via `gh repo create` or any other method) without explicit user approval in the current session.
- If this is the very first commit of a new repo (i.e. `git log` returns no commits), the commit message must be exactly: `init commit` — no format, no bullets.
- Always sign commits using the SSH key loaded in the active `ssh-agent` socket — never use GPG or any other key.
- Agents do not source `.zshrc`, so `SSH_AUTH_SOCK` is not inherited. Always prepend `export SSH_AUTH_SOCK="/run/user/1000/ssh-agent.socket"` to any Bash command that uses ssh or git signing (e.g. `export SSH_AUTH_SOCK="/run/user/1000/ssh-agent.socket" && ssh-add -l`).
- If `ssh-add -l` fails or returns no keys even after setting the socket, STOP. Do NOT commit unsigned. Instead, tell the user the ssh-agent is unavailable and ask them to run `ssh-add ~/.ssh/id_ed25519` in their terminal, then retry. An unsigned commit is never acceptable.
- `~/.gitconfig` is configured with `gpg.format = ssh` and `commit.gpgsign = true`, so `git commit -S` will use SSH automatically. Do NOT pass `-c gpg.format=...` overrides.
- NEVER push commits yourself. After all commits are done, use the `AskUserQuestion` tool to ask the user whether they want to push the commits, then run `git push` if they confirm.

## Commit Message Format

```
changelog:
- short summary of atomic change 1
- short summary of atomic change 2
- ...
```

- The title line is always exactly `changelog:` — no summary, no parentheses.
- Each bullet is a high-level summary of a meaningful change, not a detailed description. Think of it as a signpost for someone scanning commit history — they should understand what area changed, not every implementation detail.
- Aim for 1-4 bullets total. Group related small changes under one bullet rather than listing each individually.
- Write in plain, everyday language. Avoid technical jargon, internal identifiers, and implementation specifics unless essential to understanding what changed.
- No period at the end of bullet points.
- Do not include boilerplate, metadata, or attribution lines of any kind.

## Process

1. Set `export SSH_AUTH_SOCK="/run/user/1000/ssh-agent.socket"` and verify with `ssh-add -l` before doing anything else. Stop if no keys are loaded.
2. Run `git status` and `git diff` (staged + unstaged) to understand what changed.
3. If nothing is staged, stage all modified/new tracked files with `git add -u`, then ask the user if they also want untracked files added.
4. Draft the commit message following the format above based on the actual diff.
5. Run `git commit -m "$(cat <<'EOF'\n<message>\nEOF\n)"` — use a HEREDOC to preserve formatting.
6. Report the commit hash and title to the user.
7. Use `AskUserQuestion` to ask if they want to push. If confirmed, run `export SSH_AUTH_SOCK="/run/user/1000/ssh-agent.socket" && git push`.

## Example

```
changelog:
- tweaked arch-assist and chromium window appearance in i3
```
