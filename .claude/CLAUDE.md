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

## HyprPanel Tasks

Whenever the task involves hyprpanel (config, SCSS, theming, patches, launching, or the theme switcher), first read and strictly follow:
~/.claude/skills/hyprpanel/SKILL.md

Hard rules (enforced by ~/.claude/hooks/hyprpanel-guard.py):
- Start/restart ONLY via `~/.config/hyprpanel/bin/hyprpanel-launch`. The `hyprpanel-watchdog` (hyprland exec-once) owns the lifecycle and is the sole parent; it restarts through `hyprpanel-launch` too. Never run the stock binary (`hyprpanel-app`, `hyprpanel -q`, or a direct `gjs -m … dmFyIF-ags.js`) — it skips all JS patches and breaks the theme switcher.
- Kill-only is `pkill -f "gjs.*dmFyIF-ags.js"`. Plain `hyprpanel <cmd>` CLI calls (rc, cfc, applyTheme, toggleWindow …) are fine — they talk to the running patched instance.
- Never edit the decoded JS bundle (`$XDG_RUNTIME_DIR/dmFyIF-ags.js`) directly — it is rewritten on every launch. All JS changes go through sed/python patches in `hyprpanel-patched`.
- Never edit generated files by hand: `matugen-colors.scss` (edit the matugen template), or anything under `/usr/share/hyprpanel/`.
- `hyprpanel-launch` is the single source of truth for the start sequence (kill → socket cleanup → persist theme colors into config.json → log rotation → exec patched). Add new start-time logic there, never in a parallel path.

## OS / System / Package / Config Tasks

Whenever the task involves packages, system services, hardware, desktop config (hyprland, hyprpanel etc.), shell config, or anything Arch/Linux-specific, first read:
~/.claude/skills/arch/SKILL.md

## Terminal Tasks

Whenever the task involves kitty, zsh, starship, terminal colors, prompt layout, or terminal plugins, first read:
~/.claude/skills/terminal/SKILL.md

## Dotfiles Repo

Whenever the task involves adding, removing, or modifying files in the dotfiles repo (~/.gitignore whitelist, tracking new configs, managing .claude/ contents), first read:
~/.claude/skills/dotfiles/SKILL.md

## Working on this machine

The machine is in active use while you work. Get on with the task — do not ask for a
per-run permission window, and do not post approval ceremonies before ordinary work.
Reading files, searching, writing config, editing code, running builds and tests, package
queries, and working in scratch directories all proceed without asking.

Three things still need a heads-up first, because they interrupt the person at the keyboard
or are not undoable:

- Powering off, rebooting, suspending, or hibernating.
- Synthesising input (`xdotool`, `ydotool`, `wtype`, `dotool`) or driving the compositor to
  move, close, or focus windows the user did not ask you to touch. **Never relocate or
  consolidate the user's windows** — the workspace layout is deliberate.
- Deleting or overwriting data outside the working tree and scratch directories, where
  there is no undo.

Where two approaches work, take the one the user does not see. Prefer reading state over
driving a GUI, headless capture over screenshotting the live desktop, and background work
over anything that steals focus. Do not contort a task into something worse just to avoid
interference — the point is to skip needless takeover, not to sacrifice the result.

When a run does change something the user can see, say so plainly afterwards: what is left
changed, and anything that failed.

## Context discipline

Every turn re-sends the whole conversation, so keep tool output small and the transcript lean:
- Read with `sed -n`, `grep -n`, `head`, `tail`; never `cat` a large file or dump a directory tree.
- Pipe build and test output through `grep -E 'error|FAIL|warning'` and `tail -40`; report the summary, not the log.
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
