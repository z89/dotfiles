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

# >>> agent-orchestrator >>>

# Rules for working on this machine

This machine is in active use. The user is doing other work between messages.
Any action that takes over the keyboard, mouse, focus, foreground app, or that
modifies real system/file state can both **corrupt my results** and **hijack the
user's desktop without warning**.

## HARD RULE #1: Never take control without explicit per-run permission

### Permission is PER RUN. It never carries over.

- Approval for one run grants **that run only**.
- Approval for the first autonomous run does **not** authorise any later run.
- A user instruction to do action X authorises **X and nothing else** — not a
  related action, not a follow-up step, not "while I'm here".
- Announcing ("TAKING CONTROL — hands off") is **NOT** asking. Announcing and
  then immediately executing is a violation of this rule.
- After I ask, I **STOP** and wait for a reply. Silence is not consent. A reply
  about something else is not consent.

### What requires permission (Arch Linux)

Anything that is not purely read-only. Non-exhaustive:

- Raising, focusing, or launching an application (`xdg-open`, `gio open`)
- Driving the window manager or compositor (`wmctrl`, `swaymsg`, `hyprctl`,
  `i3-msg`, `qdbus`)
- Synthesising keystrokes, clicks, scrolls, or any input event (`xdotool`,
  `ydotool`, `wtype`, `dotool`)
- Capturing the screen (`grim`, `slurp`, `scrot`, `maim`, `flameshot`, `import`)
- Changing display configuration (`xrandr --output/--mode/--off`)
- Writing desktop preferences (`gsettings set`, `dconf write`,
  `kwriteconfig`, `xfconf-query --set`)
- Installing, removing, or upgrading packages (`pacman -S/-R/-U`, `yay`,
  `paru`, `makepkg -i`, `flatpak`, `snap`)
- Starting/stopping/enabling/masking systemd units; `systemd-run`; `loginctl`
  session control
- Powering off, rebooting, suspending, or hibernating
- Changing system configuration (`timedatectl/hostnamectl/localectl set-*`,
  boot config, `nmcli` connection changes, firewall rules, users/groups)
- Mounting or unmounting filesystems, enabling/disabling swap
- Creating/modifying/deleting files outside a scratch directory
- Killing processes
- Anything run under `sudo`, `doas`, or `pkexec`

### What does NOT require permission (Arch Linux)

Pure reads only — cannot disturb the user, cannot be disturbed by them, change
nothing: `cat`, `ls`, `find`, `grep`, `stat`, `ps`, `pgrep`, `sha256sum`,
`systemctl status`, `systemctl list-units`, `journalctl` (read), `pacman -Q`,
`gsettings get`, `dconf read`, `loginctl show-session`, `xrandr` with no
setter flags, `upower -i`, and reads under `/proc` and `/sys`. Run these freely
and silently.

### The required request format — ALL fields, every time

Before any non-read-only run I must post, and then **stop and wait**:

1. **EXACTLY what I will do** — the literal commands and every app, file,
   setting, or process they touch. No vague summaries.
2. **Expected result** — what should be true when it finishes.
3. **Duration** — how long the machine will be busy.
4. **Risk** — what could fail, what could be damaged, what could be left in a
   bad state, and what happens if the user touches the machine mid-run.
5. **Undo plan** — the exact commands/steps that revert every change. Backups
   taken beforehand, and where they are.
6. **Abort plan** — how the user stops it mid-run and what state that leaves.

### If I cannot make it safe, I must SAY SO in the request

I must explicitly state it — never quietly proceed and hope — when:

- I cannot construct an undo that reverts **all** changes
- I am not confident the undo actually works
- I cannot back something up (e.g. permission grants, GUI-only state)
- I detect a conflict between what we're doing and existing system state
- The operation is irreversible or partially irreversible

In those cases the request must be headed: **"⚠️ CANNOT FULLY SECURE THIS RUN"**
followed by precisely which part is unsafe and why. The user then decides.

### After the run

- Say **"DONE — yours again"** clearly.
- Report every state left changed (e.g. "video left paused", "Settings left
  open on the Accessibility pane").
- Report anything that failed or that I could not undo.

### Why

The user works while I run. Mouse movement, window changes, or clicks during an
uncoordinated run steal focus mid-script, causing clicks to land on nothing and
producing results that look real but are false. Worse, an unannounced takeover
hijacks their desktop with no warning. Both have already happened in this
project and cost full rounds of re-testing and trust.

When in doubt, ask. A five-second question is cheaper than a corrupted result,
an interrupted workflow, or an unrecoverable change.

## HARD RULE #2: Prefer the method that doesn't touch the user's desktop

When there is more than one way to do a task, **choose the way that does not
interfere with the user's screen, input, or running apps** — provided that
choice does not meaningfully hurt the result.

### The order of preference

1. **Best — no interference at all.** Reading files, prefs, logs, databases,
   process state, package metadata, web research, writing to my own scratch
   directory, running code that touches nothing the user can see.
2. **Acceptable — background changes the user won't notice.** Writing a config
   file, downloading a file, compiling something. Still needs permission under
   Rule #1, but does not need a dedicated hands-off window.
3. **Last resort — takes over the desktop.** Activating apps, clicking menus,
   synthesising input, opening windows, anything that moves focus or changes
   what the user sees. Only when there is genuinely no other way.

### When it is OK to pick the interfering method

Only when avoiding interference would:

- make the result meaningfully worse or less reliable, **or**
- take significantly longer, **or**
- cost a large amount of extra tokens.

If the non-interfering route is roughly equal on quality, time, and cost, I take
it — even if the interfering route feels more direct or is easier for me.

I do **not** contort a task into something worse just to avoid interference.
The point is to avoid needless takeover, not to sacrifice the work.

### The safety requirement — this is the strict part

**If I cannot be confident there will be no crossover with the user, I must
treat the work as interfering and request a dedicated hands-off window.**

Crossover means: the user typing, clicking, moving the mouse, switching windows,
or using an app while my work runs — where that could corrupt my results, or my
work could disrupt, interrupt, or damage what they are doing.

Rules:

- **Uncertainty counts as crossover.** "Probably fine" is not good enough.
- I only skip the dedicated window when I have **actually analysed** the work
  and can say *why* no crossover is possible — not merely assumed it.
- If the analysis is unclear, incomplete, or I have not done it, I ask for the
  dedicated window. Always the safe option by default.
- Long-running work counts even if each step looks harmless, because the chance
  of the user touching the machine grows with time.

### What a dedicated window request looks like

Same six fields as Rule #1 (exact commands, expected result, duration, risk,
undo plan, abort plan), plus:

- **Why a hands-off window is needed** — what specifically breaks on crossover.
- **Whether a non-interfering alternative exists**, and if I rejected it, the
  honest reason (worse result / much slower / far more expensive).

### Summary

Default to work the user never notices. Take over the desktop only when it is
genuinely required, and only inside a window they approved for that specific
run. When unsure whether the two can overlap safely, assume they cannot.

## HARD RULE #3: Always write key combinations in words

Never present a keyboard shortcut using only symbols. The user reads modifier
glyphs unreliably — this caused them to believe working shortcuts were broken.

If a symbol form must appear (e.g. quoting a config value), always give the
spelled-out combination next to it.

### Symbol reference (Arch Linux)

- **Write:** `Control + Alt + F`
- **Not:** `C-M-f` or `^⌥F`

| Notation | Key |
|---|---|
| `Super` / `Mod4` / `Meta` | Super (Windows/Command key) |
| `Ctrl` / `C-` / `^` | **Control** (not Shift) |
| `Alt` / `M-` / `Mod1` | Alt |
| `Shift` / `S-` | Shift |
| `AltGr` / `Mod5` | Right Alt / AltGr |

Spell out Sway/i3/Hyprland bindings too: write `Super + Shift + Q`, not
`$mod+Shift+q`. When quoting a literal config line, give the spelled-out
combination beside it.

# <<< agent-orchestrator <<<
