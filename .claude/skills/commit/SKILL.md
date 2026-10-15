---
name: commit
description: Commit work inside the warden box and publish it as z89 through the publisher daemon
argument-hint: [optional description or scope hint]
allowed-tools: Bash, Read, Glob, Grep
---

# commit

Check `WARDEN_PROFILE` before staging. A session started with `agent` has `WARDEN_PROFILE` and `WARDEN_PUBLISH_SOCK` set, runs as its own Unix user, and holds no write credential. A session without them is an operator session.

## local commits inside the box

- Keep the draft identity and git configuration that the box rendered. Do not look for an ssh agent, a signing key or a token, and do not sign a draft commit by hand.
- Inspect status and both staged and unstaged diffs. Stage only the requested paths by name. Keep unrelated work out of the commit.
- Run repository checks and inspect the entire staged diff for secrets before committing. Never bypass hooks.
- Commit with plain `git commit`. Drafts are unsigned and are rewritten by the publisher.
- Do not use plain `git push`. Do not add a `Co-authored-by`, `Requested-by`, `Generated-with` or `Signed-off-by` trailer.
- Name the branch `<type>/<slug>` with type one of feat, fix, chore, docs, refactor, test, perf. Do not use an `agent/` prefix.

## publishing as z89

When the user asks to publish, prepare the final message from all unpublished draft commits and run this from inside the box, in the workspace clone.

```bash
python3 -m warden.client.publish
```

Pass the repository, branch and final message as that command's help describes. The client sends the drafts and only the changed paths to the publisher over `WARDEN_PUBLISH_SOCK`, then polls the job state.

- No pull request is opened. The publisher validates the delta, scans for secrets, signs as z89 with the auto key and pushes the branch over SSH. The job ends at `pushed`.
- The default branch is pushed the same way when the policy marks it automatic, and the push is refused when the remote head moved since the drafts were based. Rebase the drafts and submit again. A branch the policy marks gated stays in `awaiting_operator` until the operator reviews it from an operator session. Report the job id and stop. Do not retry or resubmit while it waits. A protected branch is refused.
- Report the final state and remote sha from the job status. A job in `rejected`, `expired` or `failed` is reported with its reason and is not retried blindly.

The final remote commit has z89 as its only author, committer and signer. Draft commits stay in the clone and never reach the remote.

## operator commits

In an operator session, verify the operator key in `/run/user/1000/ssh-agent.socket` before committing. Use the configured SSH signing key and `git commit -S`. Push only after the user approves that specific push.

## commit message

Except for a new repository's first commit, use exactly this subject, a blank line and one to four short bullets with no final full stop.

```text
changelog:

- describe the change
```

The first commit in a new repository is exactly `init commit`. Never use `--no-verify` or force push unless the user explicitly requests it. Never create a remote repository without current session approval.
