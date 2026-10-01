# Global Rules

## Git / GitHub Actions

Whenever you are about to perform any git or GitHub operation (commit, push, branch, PR, tag, init, etc.), first read and strictly follow:
~/.claude/skills/commit/SKILL.md

## Infrastructure Commands

Never run a terraform/tofu/terragrunt command that changes infrastructure, rewrites state,
or re-points where state lives: `apply`, `destroy`, `import`, `init`, `get`, `taint`,
`untaint`, `refresh`, `test`, `force-unlock`, `login`, `logout`,
`state mv|rm|push|replace-provider`, `workspace new|delete`, `providers lock|mirror`.
Never pass `-auto-approve`, `-migrate-state`, `-force-copy`, `-reconfigure` or `-lock=false`.

`init` is on that list deliberately: it binds the directory to a backend and rewrites the
lock file, and it is the only command that can quietly change *which state file* the
directory talks to. Where a local state file is the only record of live infrastructure,
that is the worst available outcome. If a directory needs initialising, ask the operator to
run `init` once; `plan` works afterwards.

`plan` (including `plan -destroy`), `validate`, `fmt`, `show`, `output`, `graph`, `console`,
`providers schema`, `state list|show|pull` and `workspace list|show|select` are fine. Read a
plan and report the diff; the operator runs the apply.

Enforced by `permissions.deny` in ~/.claude/settings.json and ~/.claude/hooks/terraform-guard.py.
These are blocks, not prompts — do not look for a way around them.

## AWS Commands

Never make a state-changing AWS call, in any account, in any repository. Read-only calls are
fine: `describe-`, `list-`, `get-`, `lookup-`, `search-`, `head-`, `batch-get-`, `estimate-`,
`simulate-`, `validate-`, plus `scan`, `query`, `select`, `help`, `wait`, `aws s3 ls` and
`aws configure list|get`.

Credential-minting reads are blocked too, even though they change nothing: `sts assume-role`,
`sts get-session-token`, `ecr get-login-password`, `eks get-token`, `sso get-role-credentials`,
`iam get-credential-report`. They return credentials usable outside the guard entirely, which
would make the rest decorative. `aws configure` in any writing form is blocked because
`~/.aws` decides which account a command with no `--profile` reaches.

This matters most for the **management account**, where an SCP cannot restrict anything — a
local guard and credential scoping are the only two controls that exist.

Enforced by `permissions.deny` in ~/.claude/settings.json and ~/.claude/hooks/aws-guard.py.
A hook sees commands, not SDK calls inside a script file; only credential scoping closes that.

## OS / System / Package / Config Tasks

Whenever the task involves packages, system services, hardware, desktop config (hyprland, DMS etc.), shell config, or anything Arch/Linux-specific, first read:
~/.claude/skills/arch/SKILL.md

## Terminal Tasks

Whenever the task involves kitty, zsh, starship, terminal colors, prompt layout, or terminal plugins, first read:
~/.claude/skills/terminal/SKILL.md

## Dotfiles Repo

Whenever the task involves adding, removing, or modifying files in the dotfiles repo (~/.gitignore whitelist, tracking new configs, managing .claude/ contents), first read:
~/.claude/skills/dotfiles/SKILL.md

Before changing any file in the dotfiles repo, also read ~/AGENTS.md. It records the shared
documentation style, the settled 2026-10-01 restyle, and uncommitted work that must not be
reverted or folded into unrelated commits. Repos with their own AGENTS.md load it through CLAUDE.md.

## Working on this machine

The machine is in active use while you work. Get on with the task — do not ask for a
per-run permission window, and do not post approval ceremonies before ordinary work.
Reading files, searching, writing config, editing code, running builds and tests, package
queries, and working in scratch directories all proceed without asking.

Three things still need a heads-up first, because they interrupt the person at the keyboard
or are not undoable:

- Powering off, rebooting, suspending, or hibernating.
- Taking over the pointer, keyboard, workspaces or the visible screen. Say what you are
  about to do and get an explicit yes in this session, immediately before the first such
  command — not from an earlier turn, and not implied by the task. This covers synthesising
  input (`xdotool`, `ydotool`, `wtype`, `dotool`), `hyprctl dispatch`/`keyword`/`reload`,
  keybindings, switching workspaces, and moving, closing or focusing windows. It applies
  even when the task is itself about desktop behaviour — "test the workspace animation" is
  not permission to switch workspaces. The user is usually mid-keystroke in another
  workspace; a surprise switch has already made them close a working session by accident.
  **Never relocate or consolidate the user's windows** — the workspace layout is deliberate.
  Permission is per run: when a recording or test finishes, the next one asks again.
- Deleting or overwriting data outside the working tree and scratch directories, where
  there is no undo.

## Desktop Control Guard

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

## Context discipline

Every turn re-sends the whole conversation, so keep tool output small and the transcript lean:
- Read with `sed -n`, `grep -n`, `head`, `tail`; never `cat` a large file or dump a directory tree.
- Send build and test output to a log file and keep the exit status: `CMD > LOG 2>&1; echo "exit=$?"; grep -E 'error|FAIL|warning' LOG | tail -40`. Report the status and the summary, not the log.
- Delegate long research, log reading, and test runs to a subagent and bring back only the conclusion.
- Every spawned agent gets an explicit `model` (`sonnet` for mechanical work, `opus` for judgment) and a prompt of at most ~2,000 words. Never let a worker inherit Fable.
- Do not re-read a file already in context unless it changed.

## Compact instructions

When compacting, keep: the task statement and acceptance criteria, every file path touched with a one-line note of what changed, decisions made and why, the last verification command and its result, and anything still unfinished. Drop tool output, exploration that led nowhere, and file contents that can be re-read.

## Key combinations

Never present a keyboard shortcut using only symbols. The user reads modifier glyphs
unreliably — this caused them to believe working shortcuts were broken.

- **Write:** `Control + Alt + F`
- **Not:** `C-M-f` or `^⌥F`

| Notation | Key |
|---|---|
| `Super` / `Mod4` / `Meta` | Super (Windows/Command key) |
| `Ctrl` / `C-` / `^` | **Control** (not Shift) |
| `Alt` / `M-` / `Mod1` | Alt |
| `Shift` / `S-` | Shift |
| `AltGr` / `Mod5` | Right Alt / AltGr |

Spell out Sway/i3/Hyprland bindings too: write `Super + Shift + Q`, not `$mod+Shift+q`.
When quoting a literal config line, give the spelled-out combination beside it.

## Writing Style

Never use patterns that reveal AI-generated text:
- No double hyphens (`--`) as punctuation
- No filler phrases: "certainly", "absolutely", "of course", "great", "sure", "happy to", "I'd be happy to", "let me", "let's", "I'll", "I will"
- No sycophantic openers or sign-offs
- No em-dash overuse as a dramatic pause
- No "In summary:", "In conclusion:", "To summarize:" closers
- No hedging stacks: "it's worth noting that", "it's important to note that", "please note that"
- Write plainly and directly
