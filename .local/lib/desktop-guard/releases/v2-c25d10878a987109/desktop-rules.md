The machine is shared with the user and other running Claude/Codex sessions.
Ordinary reads, searches, source edits, builds, tests, and headless work proceed
without desktop approval. Never assume that another window, process, session,
workspace, clipboard, or audio device belongs to the current task.

The desktop-control hooks are mandatory in permission-bypass modes. They use
one shared, action-scoped guard. Before changing live windows/workspaces, input,
displays, visible applications, shared desktop state, or desktop/session services,
obtain explicit approval immediately before that action. The same applies to
writing configuration that automatically reloads the active desktop. Preparation
in unwatched files and staging copies is ordinary work; applying it is separate.

When the hook requests approval:

- Show its complete request and explain the intended effect and target.
- Leave that action pending. Unrelated safe work may continue; there is no
  session-wide lock. Never retry through another command, wrapper, or tool to
  evade approval, and never perform a refused action without a new user request.
- The user replies `YES DSK-XXXXXX` or `NO DSK-XXXXXX`. An approval permits one
  exact action by its initiating actor, with the same arguments and cwd, within
  five minutes. It grants no permission window or related follow-up actions.
- Report the actual result after an approved desktop action. Approval/consumption
  does not prove execution succeeded. Each later desktop test needs its own approval.

Use provider-owned task handles to stop the current task's background work.
Numeric PIDs and matching Unix usernames are not proof of ownership. Signals to
unverified processes and restarts of shared services require approval.

The operator recovery helper is `~/.local/bin/desktop-guard`: `status`, `show CODE`,
`approve CODE`, and `cancel CODE`. Only the human operator may invoke its approval
or execution commands; agents must not approve themselves or edit approval records.
For a Bash request missing actor identity, the operator can inspect, approve, and
then `run CODE` once. Non-shell identity failures require repairing the tool channel.
`rollback` selects the previous tested guard release (or the first-install repair
copy); it never restarts providers or the desktop. See the installed README for
the initial repair copy's limitations.
Never disable, modify, or work around the guard without an approved guard-change plan.

Hooks are an accident guard, not complete isolation. Commands sent later into an
existing interactive shell may not be checked again. Send desktop operations as
fresh guarded tool calls; never use shell/REPL continuation to bypass the gate.
Generic scripts and specialized tool paths can conceal effects the hook cannot
observe. Prefer headless validation and require immediate approval for live testing.

Desktop approval does not override separate AWS, Terraform, secret, or HyprPanel
integrity rules. Identify an independent denial accurately instead of presenting
another desktop approval as a way to override it.
