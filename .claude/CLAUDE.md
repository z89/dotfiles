# Global Rules

## Git / GitHub Actions

Whenever you are about to perform any git or GitHub operation (commit, push, branch, PR, tag, init, etc.), first read and strictly follow:
~/.claude/skills/commit/SKILL.md

## Infrastructure Commands

Never run a terraform command that changes infrastructure, rewrites state, or re-points
where state lives — in any repository, under any circumstance. Specifically: `apply`,
`destroy`, `import`, `init`, `get`, `taint`, `untaint`, `refresh`, `test`, `force-unlock`,
`login`, `logout`, `state mv|rm|push|replace-provider`, `workspace new|delete`, and
`providers lock|mirror`. The same applies to `tofu`, `opentofu` and `terragrunt`,
including `terragrunt run-all`.

Never pass `-auto-approve`, `-migrate-state`, `-force-copy`, `-reconfigure` or
`-lock=false` to anything.

**`init` is on that list and it is not an oversight.** It binds the directory to a backend
and rewrites the provider lock file, and it is the only command that can quietly change
*which state file the directory is talking to*. `-migrate-state` copies state to a new
backend; `-reconfigure` re-points without copying, so the next `plan` reads an empty state
and proposes creating everything that already exists. Where a local state file is the only
record of live infrastructure, that is the worst available outcome, and nothing about the
command line looks dangerous. If a directory needs initialising, ask the operator to run
`init` once; `plan` works afterwards.

`plan` (including `plan -destroy`), `validate`, `fmt`, `show`, `output`, `graph`,
`console`, `providers schema`, `state list|show|pull` and `workspace list|show|select` are
all fine. Read a plan and report the diff; the operator runs the apply themselves.

This is enforced three ways and stating it here is the first: `permissions.deny` in
~/.claude/settings.json, and ~/.claude/hooks/terraform-guard.py, which catches the cases a
prefix rule cannot (`cd infra && terraform destroy`, `bash -c '…'`) and holds even under
`--dangerously-skip-permissions`. There is no override flag. Do not go looking for one, and
do not write a wrapper script to get around it.

## AWS Commands

Never make a state-changing AWS call, in any account, in any repository. Read-only calls
are fine and do not need to be handed over.

Allowed: operations beginning `describe-`, `list-`, `get-`, `lookup-`, `search-`, `head-`,
`batch-get-`, `estimate-`, `simulate-` or `validate-`, plus `scan`, `query`, `select`,
`help`, `wait`, `aws s3 ls` and `aws configure list|get`. Everything else is blocked by
default, including operations that do not exist yet.

**Some reads are blocked anyway, and the reason matters.** `sts assume-role`,
`sts get-session-token`, `ecr get-login-password`, `eks get-token`, `sso get-role-credentials`
and `iam get-credential-report` change nothing, but they return credentials usable outside
the guard entirely — with curl, or a script file, or any binary that is not `aws`. Allowing
them would make the rest decorative.

`aws configure` in any writing form is blocked because `~/.aws` decides which account a
command with no `--profile` reaches.

This matters most for the **management account**, because an SCP cannot restrict the
management account. There is no AWS-side control available for it, so a local guard and
credential scoping are the only two that exist.

Enforced by `permissions.deny` in ~/.claude/settings.json and by
~/.claude/hooks/aws-guard.py, which catches what a prefix rule cannot (`cd /tmp && aws s3
rb`, `bash -c '…'`, `AWS_PROFILE=x aws …`) and holds even under
`--dangerously-skip-permissions`. There is no override flag.

**A hook only sees commands. It cannot see an SDK.** Inline code passed to an interpreter is
pattern-matched for boto3 and aws-sdk, but a call inside a script file is never seen by any
hook. Only credential scoping closes that, because it removes the permission rather than the
command.

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

## Writing Style

Never use patterns that reveal AI-generated text:
- No double hyphens (`--`) as punctuation
- No filler phrases: "certainly", "absolutely", "of course", "great", "sure", "happy to", "I'd be happy to", "let me", "let's", "I'll", "I will"
- No sycophantic openers or sign-offs
- No em-dash overuse as a dramatic pause
- No "In summary:", "In conclusion:", "To summarize:" closers
- No hedging stacks: "it's worth noting that", "it's important to note that", "please note that"
- Write plainly and directly
