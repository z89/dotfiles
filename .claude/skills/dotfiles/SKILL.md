---
name: dotfiles
description: Manage the dotfiles repo — add new files, update the whitelist, commit tracked config
argument-hint: [file or directory to add, or task description]
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# Dotfiles Repository

## Repo Details

| Key | Value |
|-----|-------|
| Remote | `git@github.com:z89/dotfiles.git` |
| Branch | `desktop` |
| Root | `/home/archie` (bare-style, worktree is `$HOME`) |
| Git identity | z89 / z89 — follow `~/.claude/skills/commit/SKILL.md` for all commits |

## How the Repo Works

The root `.gitignore` uses a **whitelist pattern**:
- `/*` — ignores everything at the home root by default
- `!<path>` — explicitly un-ignores only the listed files/directories

This means **nothing is tracked unless deliberately added**. Never use `git add -A` or `git add .` — it will silently do nothing thanks to the gitignore, but it's still bad practice.

## Currently Tracked Files

```
.claude/          (selectively — see .claude/.gitignore)
.config/Code/User/keybindings.json
.config/Code/User/settings.json
.config/gtk-3.0/gtk.css
.config/picom/
.config/polybar/
.config/redshift/launch.sh
.config/rofi/
.config/systemd/user/geoclue-agent.service
.config/wpg/templates/
.git-commit-template
.gitignore
README.md
tuning.sh
.vimrc
.zprofile
.zprofile
.zsh-themes/custom-z89.zsh-theme
.zshrc
```

### Inside `.claude/` (selective via `.claude/.gitignore`)

The `.claude/` directory has its own `.gitignore` that whitelists only:
- `.gitignore` (the nested one)
- `CLAUDE.md`
- `settings.json`
- `skills/` and all contents

Everything else in `.claude/` (history, sessions, cache, permissions, etc.) is excluded.

## Adding a New File or Directory to the Repo

1. Check it isn't already tracked: `git ls-files <path>`
2. Add the whitelist entry to `~/.gitignore`:
   - For a single file: `!.config/app/file.conf`
   - For a whole directory: `!.config/app/`
   - For selective tracking inside a directory: create a `<dir>/.gitignore` with `*` + `!<file>` pattern (same as `.claude/.gitignore`)
3. Stage: `git add <path>`
4. Verify only intended files are staged: `git diff --cached --name-only`
5. Commit following the commit skill format

## Adding a New Skill to `.claude/skills/`

Skills are auto-tracked because `!skills/**` is whitelisted in `.claude/.gitignore`. Just stage the new skill file directly:
```
git add .claude/skills/<name>/SKILL.md
```

## Rules

- NEVER use `git add -A` or `git add .` — always add paths explicitly
- NEVER add files containing secrets (API keys, tokens, `.env` files, `settings.local.json`)
- Before adding a new config dir, check for sensitive files inside it first
- Always verify staged files with `git diff --cached --name-only` before committing
- Follow `~/.claude/skills/commit/SKILL.md` for all commits and push approval
