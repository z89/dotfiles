---
name: commit
description: Stage and commit changes with separated operator and GitHub App identities, signed and published through the correct trusted path
argument-hint: [optional description or scope hint]
allowed-tools: Bash, Read, Glob, Grep
---

# Git Commit

You are committing changes to a git repository. **Which identity you commit as depends on how you
were launched — check that first, before anything else.**

## STEP ZERO — which identity is this?

```bash
echo "${AGENT_GH:-0}"
```

| Result | You are | Signing key |
|---|---|---|
| `1` | an agent launched through `agent-run`, acting as **the GitHub App bot** | the bot's key, already configured |
| `0` | running as the operator, **z89** | their key, from the ssh-agent |

**If `AGENT_GH=1`, follow "Agent identity" below and IGNORE every mention of `SSH_AUTH_SOCK` in this
file.** They apply only to the operator's own sessions.

### Agent identity — AGENT_GH=1

- **NEVER set, export or reference `SSH_AUTH_SOCK`.** `agent-run` removed it on purpose. Removing the
  variable does not remove the socket, so setting it back by hand *works* — and signs the commit with
  the operator's personal key, from inside a repository the agent was confined to. That is the exact
  substitution this whole setup exists to prevent. There is no situation in which an agent needs it.
- **Do not run `ssh-add`.** Nothing to check, and a failure is not a reason to stop.
- **Do not pass `-S`, and do not disable signing either.** `GIT_CONFIG_GLOBAL` already sets
  `commit.gpgsign = true` with the selected profile's own signing key. Plain `git commit -m …`
  signs correctly.
- **Do not alter `user.name` or `user.email`.** They are the bot's, deliberately.
- The transient local commit verifies against the selected bot profile's `allowed_signers` file.
  GitHub cannot attach that key to an App bot account, so the publisher replaces the transient commit
  with a GitHub-server-signed commit before it reaches the default branch.

Everything else in this file — the message format, the push rule, the staging process — applies
unchanged, except for how the commit reaches the remote. See "Publishing as the bot" below.

### Publishing as the bot — AGENT_GH=1

**Do not run `git push`.** Run `~/.claude/skills/commit/gh-signed-commit.sh` instead, after the
local commit and only with the user's approval in this session, exactly as the push rule requires.

Why. The bot signs with its own key, and GitHub cannot verify that key — signing keys attach to
user ACCOUNTS and an App bot has none. On a repository whose ruleset requires verified signatures
every bot commit therefore trips the rule and needs an operator bypass, and bypassing a rule on
every commit is how the rule stops meaning anything. Commits created through GitHub's
`createCommitOnBranch` API are signed by GitHub itself and satisfy the rule honestly.

The script commits nothing. It republishes commits already made locally, which is deliberate: an
API call runs no git hooks, and one of those hooks is the secret scanner. Committing locally first
keeps the scanner in the path. Never invert that order to "save a step".

The publisher preserves the App bot as the primary author and adds exactly one canonical trailer:
`Co-authored-by: z89 <30657227+z89@users.noreply.github.com>`. This lets GitHub associate
the contribution with z89 while truthfully recording that automation authored the commit. Never add,
remove, or substitute that trailer manually; the publisher rejects pre-existing attribution trailers.

Three things it will refuse or warn about, all of them real:

- **New executables and symlinks.** The API carries a path and its contents and no file mode, so a
  new `100755` script would land as a plain `0644` file. The script refuses and names the paths;
  those need a human `git push`.
- **A remote that has moved.** It sends `expectedHeadOid`, so a concurrent push fails the mutation
  rather than overwriting it.
- **A message, tree, author, co-author, or signature that changed unexpectedly.** Every published
  commit is read back and must match before the local branch is reset onto it.

The published commits have DIFFERENT SHAs from the local ones — same trees and messages, rebuilt
and signed by GitHub. The script resets the local branch onto them at the end. That is expected,
not a fault.

If the App is not installed on the repository, the API returns 404 for the repo and the script
fails. That is an installation question for the operator, not something to work around.

## Rules

- NEVER add "Co-authored-by", "Co-signed-by", or any Claude attribution trailer manually. In agent
  mode only, the publishing helper adds the single canonical z89 co-author trailer.
- Do not alter git user config. Operator sessions use z89; agent sessions use the App identity selected
  from the repository owner by `agent-run`.
- Do NOT use `--no-verify` unless the user explicitly asks.
- Do NOT force-push unless the user explicitly asks.
- NEVER push to a remote (`git push`, `gh repo`, etc.) without explicit user approval in the current session — even if the user previously said "push it" in a prior session.
- NEVER create a remote repository (via `gh repo create` or any other method) without explicit user approval in the current session.
- If this is the very first commit of a new repo (i.e. `git log` returns no commits), the commit message must be exactly: `init commit` — no format, no bullets.
- **The three rules below apply ONLY when `AGENT_GH` is unset or `0`.** Under `AGENT_GH=1` they are
  actively harmful — see "Step zero" above.
- Always sign commits using the SSH key loaded in the active `ssh-agent` socket — never use GPG or any other key.
- Agents do not source `.zshrc`, so `SSH_AUTH_SOCK` is not inherited. Use `export SSH_AUTH_SOCK="/run/user/1000/ssh-agent.socket" && ssh-add -l` to verify the key. For the commit itself, set `SSH_AUTH_SOCK=/run/user/1000/ssh-agent.socket` inline so `git commit` remains a standalone command.
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
- **A blank line follows it**, separating subject from body. This is git's own convention — without
  it, git treats the whole message as one subject and `%s` returns every bullet run together on one
  line. GitHub's commit API rejoins subject and body with that blank line regardless, so a message
  written without it comes back changed on publication; written with it, local and published are
  byte-identical.
- Each bullet is a high-level summary of a meaningful change, not a detailed description. Think of it as a signpost for someone scanning commit history — they should understand what area changed, not every implementation detail.
- Aim for 1-4 bullets total. Group related small changes under one bullet rather than listing each individually.
- Write in plain, everyday language. Avoid technical jargon, internal identifiers, and implementation specifics unless essential to understanding what changed.
- No period at the end of bullet points.
- Do not include boilerplate, metadata, or attribution lines. In agent mode, the publishing helper
  adds the canonical co-author trailer after local hooks have passed.

## Process

0. Run `echo "${AGENT_GH:-0}"`. If it prints `1`, skip step 1 entirely and commit with plain `git commit -m …` at step 5 — no `SSH_AUTH_SOCK`, no `ssh-add`, no `-S`.
1. Set `export SSH_AUTH_SOCK="/run/user/1000/ssh-agent.socket"` and verify with `ssh-add -l` before doing anything else. Stop if no keys are loaded.
2. Run `git status` and `git diff` (staged + unstaged) to understand what changed.
3. If nothing is staged, stage all modified/new tracked files with `git add -u`, then ask the user if they also want untracked files added. Staging and committing must use separate Bash tool calls.
4. Draft the commit message following the format above based on the actual diff.
5. Run `git commit` as its own Bash command with no chaining, pipes, redirections, command substitution, or backticks. Set the signing socket inline and pass the message as one safely quoted multiline argument. Note the blank line — `\n\n` after the title, never `\n`: `SSH_AUTH_SOCK=/run/user/1000/ssh-agent.socket git commit -S -m $'changelog:\n\n- summary'`.
6. Report the commit hash and title to the user.
7. Use `AskUserQuestion` to ask if they want to push. If confirmed:
   - `AGENT_GH=1` → run `~/.claude/skills/commit/gh-signed-commit.sh` (see "Publishing as the bot").
   - otherwise → run `export SSH_AUTH_SOCK="/run/user/1000/ssh-agent.socket" && git push`.

## Example

```
changelog:

- tweaked arch-assist and chromium window rules in hyprland
```
