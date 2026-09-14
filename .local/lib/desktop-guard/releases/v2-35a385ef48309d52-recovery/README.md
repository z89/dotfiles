# Shared desktop guard

Claude Code and Codex keep their existing hook registrations and invoke the same
release through small entrypoint scripts. No chat, terminal, application, or
desktop service needs to be restarted. Each invocation resolves one complete
release; candidate edits are not imported by running sessions.

The guard requests approval for recognized desktop/disruptive actions. Safe
reads, source edits, builds, tests, headless work, and unrelated actions continue
while a request waits. Approval permits one exact operation, with the same actor,
tool arguments, working directory and captured script/process bindings. Pending
requests last two hours; approved permits last five minutes. These deadlines are
not permission windows. `YES DSK-XXXXXX` approves; `NO DSK-XXXXXX` cancels. A
wrong code or unrelated prompt does not lock a session.

Watched Hyprland/DMS configuration writes require approval. Confirmed unwatched
modules such as this installation's `carry.lua` can be prepared normally; the
later live reload requires approval. Unverified process signals require approval;
use the provider's task handle to stop its own background command. Merely sharing
the same Unix user or knowing a numeric PID does not establish task ownership.

## Operator recovery

The human operator can run these from `/home/archie` without changing windows or
restarting anything:

```sh
cd /home/archie
/home/archie/.local/bin/desktop-guard version
/home/archie/.local/bin/desktop-guard status
```

The expected result is the current release path and the private ledger status.
Request records contain complete actions; `show CODE` prints the selected record.
Replace `CODE` with the actual `DSK-XXXXXX` shown in that request. `approve CODE`
grants that record one permit; `cancel CODE` removes that request. Agents must not
invoke the approval helper to approve themselves or edit ledger records.

When the provider omits stable actor identity, the record is operator-only and an
automatic tool retry is never permitted. For a Bash request, the operator can
inspect it, approve it, and invoke `run CODE` to execute the stored command once.
Review the complete command and cwd first. This manual recovery path executes
outside provider hooks, so their independent policies are not automatically
re-evaluated; the operator is responsible for those constraints. Non-shell tool
requests with missing identity require repairing the provider's tool channel.
No fake usable approval is offered when the runtime ledger itself is unavailable.

If a later candidate release breaks the guard, the human operator can run:

```sh
cd /home/archie
/home/archie/.local/bin/desktop-guard rollback
```

For later upgrades, success reports restoration of the previous tested release.
It does not restart providers or the desktop. On initial installation this command
selects an independent repair copy of the first tested replacement: it can recover
damaged replacement files, but cannot undo a behavioral defect shared by both
copies. It is not a rollback to the broken original guard or original instructions.
If the helper reports an invalid/missing previous release, stop and inspect the
installation backups under `.local/state/desktop-guard/backups`; do not disable
the hook or restore unreviewed files.

## State, updates and verification

Records live under `$XDG_RUNTIME_DIR/agent-desktop-guard-v2` (with per-user runtime
and temporary-directory fallbacks). `records/` holds private action records;
`audit.jsonl` records lifecycle events without full command contents. Corrupt
records are preserved under a `.corrupt-*` suffix. Existing v1 state is left
untouched; initial activation checks that it has no outstanding requests.

Source lives in `.local/lib/desktop-guard/releases/`; `current` and `previous`
select complete versions. Do not develop by modifying an active release.
Copy a release into a candidate directory, edit there, run its tests, then use
`deploy.py prepare`, inspect the plan/diffs, and `deploy.py check` followed by
`deploy.py apply` from that candidate. A prepare/apply hash check rejects
concurrent edits to the intended targets or hook registration files. Installation
backs up every replaced file. A failed activation restores replaced bytes when
they have not subsequently been edited by someone else.

The compatibility test runners in both providers discover the shared suite:

```sh
cd /home/archie
PYTHONDONTWRITEBYTECODE=1 python3 .codex/hooks/test_desktop_control_gate.py
PYTHONDONTWRITEBYTECODE=1 python3 .local/lib/desktop-guard/current/verify_install.py --home /home/archie
```

Success means all unit/acceptance tests pass and both installed entrypoints pass
synthetic read/deny/approval/one-use checks. These tests use temporary state and
do not execute any desktop command. No real desktop action is needed for QA.

## Boundaries

This prevents recognizable accidental disruption; it is not an OS security
boundary against arbitrary same-user code. Direct commands, common shell wrappers,
bounded inline interpreter calls, known desktop tools, file targets, and selected
watched dependencies are inspected. It is not a complete shell/Lua/JavaScript
interpreter. Unknown scripts, indirect library behavior, dynamic paths, aliases,
runtime environment changes and provider-specific tool paths can conceal effects.
File/process identity checking occurs just before release of a permit, not as an
OS-enforced lock on the subsequent execution.

Codex documents that later `write_stdin` input does not trigger another
`PreToolUse` check. Outer `functions.exec` source is not broadly scanned for
command words; protection depends on nested canonical tool events. Neither path
is claimed to have universal interception. Send desktop commands through fresh
guarded calls. A complete guarantee requires isolated agents and a narrow host
approval broker, outside this implementation's approved scope.

Origin binding prefers explicit agent ID, then agent transcript, then provider
transcript identity. If a provider gives several agents the same transcript and
omits agent IDs, the hook cannot distinguish them; actor isolation in that case
is a provider limitation, not something a session ID alone solves. Missing all
origin information uses operator-only recovery.

The updated global instructions and next-prompt hook reminder describe the new
action-scoped policy. Existing context is not rewritten. A session retaining old
instructions may need a new user turn to see the reminder; it is never forcibly
restarted. Desktop approvals do not override separate AWS, Terraform, secrets,
or HyprPanel integrity rules.
