# Global Rules

## Git / GitHub Actions

Whenever you are about to perform any git or GitHub operation (commit, push, branch, PR, tag, init, etc.), first read and strictly follow:
~/.claude/skills/commit/SKILL.md

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
