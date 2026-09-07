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
| Git identity | z89 <z89@matix.com.au> — follow `~/.claude/skills/commit/SKILL.md` for all commits |

## How the Repo Works

The root `.gitignore` uses a **whitelist pattern**:
- `/*` — ignores everything at the home root by default
- `!<path>` — explicitly un-ignores only the listed files/directories

This means **nothing is tracked unless deliberately added**. Never use `git add -A` or `git add .` — it will silently do nothing thanks to the gitignore, but it's still bad practice.

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
- Follow `~/.claude/skills/commit/SKILL.md` for all commits and push approval

### Public Repo — Zero Secrets Policy

This is a **public repository**. Every line committed is visible to anyone on the internet. Treat every staged change as if it will be read by strangers.

**Before every commit, scan all staged content for leaks:**

1. Run `git diff --cached` (full diff, not just filenames) and read every added/modified line
2. Reject the commit if ANY of the following appear in staged content:
   - API keys, tokens, secrets, passwords, passphrases, or credentials of any kind
   - Private SSH keys, GPG private keys, or signing keys
   - `.env` files, `settings.local.json`, or any secret-bearing config
   - Session cookies, JWTs, bearer tokens, OAuth tokens
   - IP addresses, hostnames, or URLs pointing to private/internal infrastructure
   - Email addresses, phone numbers, physical addresses, or other PII
   - Usernames or account identifiers not already public (GitHub username `z89` is fine)
   - Database connection strings or DSNs
   - Encrypted secrets (they can still be brute-forced or leak metadata)
   - Hardcoded paths containing usernames other than `archie` (the home dir is inherent to the repo)

**Files to never track or commit:**
- `.env`, `.env.*`, `*.secret`, `*.key`, `*.pem` (private), `*.p12`, `*.pfx`
- `credentials.json`, `token.json`, `auth.json`, `settings.local.json`
- Browser profiles, cookie stores, session storage
- Shell history files (`.bash_history`, `.zsh_history`, etc.)
- Password manager databases or exports

**When adding a new config directory:**
- `grep -rn` the directory for patterns like `key=`, `token=`, `password=`, `secret=`, `auth`, `bearer`, `api_key` before staging
- If any match is found, inspect each one manually and exclude sensitive files via `.gitignore` before proceeding

**If a secret is accidentally committed:**
- Do NOT just delete it in a follow-up commit (git history retains it)
- Alert the user immediately — the secret must be rotated and history rewritten or the repo re-created
