---
name: commit
description: Commit bot work locally and publish a z89 signed squash after operator confirmation
argument-hint: [optional description or scope hint]
allowed-tools: Bash, Read, Glob, Grep
---

# commit

Read `AGENT_GH` before staging. Sessions launched with `agent-run` have `AGENT_GH=1` and use the selected GitHub App identity for local commits. Other sessions use the operator identity.

## local bot commits

- Keep the bot name, email, signing key and Git configuration selected by `agent-run`. Do not restore `SSH_AUTH_SOCK`, use `ssh-add`, or sign a bot commit with the operator key.
- Inspect status and both staged and unstaged diffs. Stage only the requested paths by name. Keep unrelated work out of the commit.
- Run repository checks and inspect the entire staged diff for secrets before committing. Never bypass hooks.
- Commit with plain `git commit`. The bot profile signs the local commit automatically.
- Do not use plain `git push` for bot commits. Do not add a `Co-authored-by` or `Requested-by` trailer.
- Keep App tokens limited to the repository in `agent-run`. Do not widen token scope without the operator's approval or seek a plaintext App key when the token broker refuses a request.

## publishing bot work as z89

When the user asks to publish bot work, prepare a final message from all unpublished bot commits and run `~/.local/bin/agent-publish-z89` from the repository. This one helper is the default for both bot profiles, Claude and Codex. Pass the complete final message as its single argument.

The helper opens live desktop dialogs. Follow the action-scoped desktop guard in `AGENTS.md` immediately before launching it. A general request to publish does not waive that guard.

The helper fetches the remote branch, verifies the outgoing bot commits, and builds one squash commit in a temporary worktree. It checks that the final tree matches the tested bot tree. The operator sees the diff and chooses Sign or Cancel. Git then asks through the existing SSH agent confirmation dialog before signing with z89's key. A separate dialog asks before the exact signed commit is pushed with z89's GitHub CLI login. Canceling or failing the push retains the signed commit under `refs/agent-publish/pending/`.

The final remote commit has z89 as its only author and committer. This produces one z89 commit contribution when GitHub's normal contribution criteria are met. Bot commits remain local and do not appear in remote history. The publisher refuses merges, divergent history, an unexpected author, a different tree, and a missing or unverified signature. It never force pushes.

The old `gh-signed-commit.sh` publishes bot-authored GitHub signed commits. Use it only when the user explicitly asks for bot authorship instead of z89 authorship. Do not use it for this workflow.

## operator commits

When `AGENT_GH` is unset or `0`, verify the operator key in `/run/user/1000/ssh-agent.socket` before committing. Use the configured SSH signing key and `git commit -S`. Push only after the user approves that specific push.

## commit message

Except for a new repository's first commit, use exactly this subject, a blank line and one to four short bullets with no final full stop.

```text
changelog:

- describe the change
```

The first commit in a new repository is exactly `init commit`. Never use `--no-verify` or force push unless the user explicitly requests it. Never create a remote repository without current session approval.
