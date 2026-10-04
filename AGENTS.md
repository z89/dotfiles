# agent notes

read this before changing anything in this repo, whichever agent you are. it holds the documentation style, the decisions already settled here and any work left uncommitted, so a later change keeps the earlier work instead of undoing it.

## 🧭 before you edit

- run `git status` and `git log -3` first. uncommitted changes you did not make belong to the owner or to another session. leave them in place, and never stash, reset, check out, reformat or commit them as part of an unrelated task.
- stage the paths you changed by name, never `git add -A` or `git add .`.
- keep documentation changes and code changes in separate commits.
- commit messages are `changelog:`, a blank line, then one to four short bullets with no full stop.
- when a change touches anything this file describes, update this file in the same commit.

## ✍️ documentation style

this covers every markdown file (readme, changelog and docs). code blocks, inline code, URLs and literal values are exempt.

- the readme opens with the title in a centred `h1` and the badge row straight after it, with nothing in between. one or two neutral paragraphs then say what the project is and what it does. no pitch and no opinion words such as best, cheap, robust or seamless.
- badges are static shields.io badges with `style=flat-square&labelColor=1b1a20` in the repo colour. tech and platform badges come first and the license badge is always last, linked to `LICENSE` with `alt="license MIT"`. no stars or last-commit badges. a version on a badge is the version actually tested.
- sections run in this order, skipping any that do not apply. highlights, install, usage, settings, requirements, troubleshooting, tests, layout or architecture, docs, license. headings are lowercase with one emoji.
- highlights follow `- 🌙 **bold phrase** flows straight into the sentence.` and never `**label**: text`.
- prose has no em dashes, en dashes, double hyphens, colons or semicolons. use a comma, a full stop, parentheses, or "to" for a range. a line that would end in a colon before a list or code block ends in a full stop or is reworded. colons stay only in code, URLs, clock times and literal values.
- no filler, hedging or summary phrases ("it's worth noting", "importantly", "in summary").
- write DankMaterialShell in full once per document, followed by (DMS), then DMS from there on. the badge label is `DMS`.
- tool names are lowercase in prose (rust, cargo, bluez, pipewire, wireplumber, linux, systemd, qt, quickshell, hyprland, kitty, zsh, lua). acronyms stay uppercase (CLI, JSON, MIT). Apple names keep Apple's casing (AirPods, macOS).
- units take no space (`400ms`, `640px`).
- `LICENSE` is the standard MIT text with `Copyright (c) 2026 z89` and no trailing blank line. the readme ends with `## 📄 license` and the word MIT.

before committing a doc, `grep -nP '—|–| -- |;' <file>` should print nothing outside code, and every line `grep -n ':' <file>` prints should be code, a URL, a table of literal values or a clock time.

## 📌 settled in this repo

- this repo is public. nothing secret, private or identifying is committed (tokens, keys, private hostnames, email addresses, account names other than z89). run `claude-prune-settings` before committing `.claude/settings.json`.
- the root `.gitignore` is a whitelist, so a newly tracked file needs its own `!path` line.
- the 2026-10-01 restyle is commit f77599b.
- that restyle covers `README.md`, `LICENSE`, `.config/DankMaterialShell/plugins/persona/README.md` and `.config/hypr/tests/README.md`. keep their wording, the badge order (arch linux, hyprland, DMS, then the license, all in `7ee0d6`) and the 400ms theme fade figure.
- `.config/DankMaterialShell/README.md` got the same restyle on 2026-10-02. its spare adapter steps use `<uuid>` in place of the real profile, the connection name and the interface, since the repo is public.
- auris and ember are separate repos linked into `.config/DankMaterialShell/plugins/`, each with its own `AGENTS.md`.
- eco (video wallpapers, formerly livewall) is a separate private repo at `~/Documents/Github-Projects/eco`. its `bin/eco-install` writes `.config/systemd/user/dms.service.d/zz-eco.conf`, which is ignored here because it points at a checkout a fresh install may not have. never track it.
