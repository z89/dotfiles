---
name: commit
description: Stage and commit bot work locally, then publish a z89 signed squash after operator confirmation
---

# commit

Check `AGENT_GH` before staging. An `agent-run` session has `AGENT_GH=1` and commits locally as the selected bot. Do not change its name, email, signing key, or Git configuration. Do not restore `SSH_AUTH_SOCK`, call `ssh-add`, or sign with z89's key from the agent session.

Inspect status and the staged and unstaged diffs. Stage only requested paths by name. Run relevant checks and inspect the complete staged diff for secrets. Do not bypass hooks. Use plain `git commit` in bot sessions because the selected profile already signs it.

Keep App tokens limited to the repository in `agent-run`. Do not widen token scope without the operator's approval or seek a plaintext App key when the token broker refuses a request.

When the user asks to publish, draft one final `changelog` message for all unpublished bot commits and run `~/.local/bin/agent-publish-z89` with that message as its single argument. The helper works for both bot profiles and all agents. It verifies the bot commits, prepares one squash with the same tree, and shows the final diff. The operator approves the z89 SSH signature and the push in separate dialogs. The remote gets one Verified z89 authored commit when GitHub accepts the registered key. Bot work commits stay local. Never use plain `git push` for them, and never add attribution trailers.

The helper opens live desktop dialogs. Follow the action-scoped desktop guard in `AGENTS.md` immediately before launching it. A general request to publish does not waive that guard.

The old `gh-signed-commit.sh` keeps bot authorship and is only for an explicit request to publish as the bot. The z89 squash publisher is the default. It refuses merge commits, divergent history, unexpected authors, tree mismatches, and missing signatures. It never force pushes.

For an operator session, verify the key in `/run/user/1000/ssh-agent.socket`, commit with `git commit -S`, and push only after approval for that push.

Commit messages use `changelog:`, a blank line, then one to four short bullets with no final full stop. The first commit of a new repository is `init commit`. Never use `--no-verify` or force push without an explicit user request.
