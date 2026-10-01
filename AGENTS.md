# agent notes

read this before changing anything in this repo, whichever agent you are. it holds the documentation style shared by the z89 repos (lean, gloss, ember, auris, somnus and dotfiles), the decisions already settled here and any work left uncommitted, so a later change keeps the earlier work instead of undoing it.

## 🧭 before you edit

- run `git status` and `git log -3` first. uncommitted changes you did not make belong to the owner or to another session. leave them in place, and never stash, reset, check out, reformat or commit them as part of an unrelated task.
- the published branch was rewritten and force-pushed on 2026-10-01. a clone or branch from before then carries the old history. rebase its own commits onto the remote branch, never merge the old history back in and never force-push from it.
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
- tool names are lowercase in prose (rust, cargo, bluez, pipewire, wireplumber, linux, systemd, qt, quickshell, hyprland, kitty, zsh, lua). acronyms stay uppercase (ANC, CLI, JSON, MPRIS, BLE, MIT). Apple names keep Apple's casing (AirPods, Mac, macOS, iPhone).
- units take no space (`800ms`, `5s`, `2000K`).
- `LICENSE` is the standard MIT text with `Copyright (c) 2026 z89`, byte-identical across the repos and with no trailing blank line. the readme ends with `## 📄 license` and the word MIT.

before committing a doc, `grep -nP '—|–| -- |;' <file>` should print nothing outside code, and every line `grep -n ':' <file>` prints should be code, a URL, a table of literal values or a clock time.

## 📌 settled in this repo

- this repo is public. nothing secret, private or identifying is committed (tokens, keys, private hostnames, email addresses, account names other than z89). run `claude-prune-settings` before committing `.claude/settings.json`.
- the root `.gitignore` is a whitelist, so a newly tracked file needs its own `!path` line.
- the 2026-10-01 restyle is commit f77599b, which replaced 8acdc80. never reset to 8acdc80 or to anything reachable only from it.
- that restyle covers `README.md`, `LICENSE`, `.config/DankMaterialShell/plugins/persona/README.md` and `.config/hypr/tests/README.md`. keep their wording, the badge order (arch linux, hyprland, DMS, then the license, all in `7ee0d6`) and the 400ms theme fade figure.
- auris and ember are separate repos linked into `.config/DankMaterialShell/plugins/`, each with its own `AGENTS.md`.

## 🚧 uncommitted work as of 2026-10-01

three separate pieces of work, each its own commit. none of them is part of the docs restyle.

1. **multiple Wi-Fi adapters for DMS** came from another session on 2026-10-01 and may still be open. it covers `.config/DankMaterialShell/README.md`, `.config/DankMaterialShell/patches/network-core.patch`, `.config/DankMaterialShell/patches/network-shell.patch`, `.local/bin/dms-network-build`, `.local/bin/dms-run-patched`, `.local/bin/dms-shell-patch`, `.local/bin/dms-shim/dms` and the `!.local/bin/dms-network-build` line in `.gitignore`.
   - finish and test it first. `dms-run-patched` no longer falls back to stock DMS on its own, so a failed build now stops `dms.service`, and `DMS_NETWORK_STOCK=1` is the recovery path.
   - restyle `.config/DankMaterialShell/README.md` to the rules above in the same commit. it was left out of the 2026-10-01 restyle because of this work, and it still has title case headings without emoji, DankMaterialShell written in full more than once and about 34 prose lines with colons, semicolons or dashes. keep every command, path, version and recovery step exactly.
   - `dms-network-build` is a new executable, and the bot publisher drops file modes. the owner publishes that commit from their own terminal.
2. **`.local/bin/agent-run`** is a stale copy from 2026-09-03 sitting over the committed 2026-09-07 version. committing it would revert the runtime profile discovery and write private account names into this public repo. never commit it. the owner decides whether to restore the committed version with `git checkout -- .local/bin/agent-run`.
3. **`.claude/settings.json`** sets the session model and effort and adds the gloss hooks. run `claude-prune-settings`, read the diff, then commit it on its own.

delete each item here once it is committed.
