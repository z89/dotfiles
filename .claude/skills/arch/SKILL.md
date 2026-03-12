---
name: arch
description: System context for Arch Linux setup — load this before any OS, hardware, package, or config task
argument-hint: [optional task description]
allowed-tools: Bash, Read, Glob, Grep
---

# Arch Linux System Context

This file defines the user's system. Load it before any task involving packages, system config, hardware, services, or desktop environment.

## System

| Key | Value |
|-----|-------|
| OS | Arch Linux (rolling) |
| Kernel | 6.18.13-arch1-1 |
| WM | Hyprland |
| Shell | zsh (oh-my-zsh) |
| Terminal | kitty |
| Editor | nvim (`$VISUAL`, `$EDITOR`) |
| Browser | ungoogled-chromium (command: `chromium`, binary: `/usr/bin/chromium`) |
| Prompt | zsh |
| GPU | AMD (ROCm at `/opt/rocm`) |

## Package Management

- **Primary:** `pacman` for official repos
- **AUR:** `yay` (never `paru`, never `makepkg` directly unless debugging)
- Install: `yay -S <pkg>` — handles both official and AUR
- Search: `yay -Ss <pkg>`
- Remove: `sudo pacman -Rns <pkg>` (includes orphan deps)
- Update all: `yay -Syu`
- Never suggest `apt`, `brew`, `dnf`, `snap`, or `flatpak` unless the user explicitly asks

## Desktop Environment

- **WM:** Hyprland — config at `~/.config/hypr/hyprland.conf`
- **Bar:** hyprpanel
- **Launcher:** wofi
- **Notifications:** swaync (replaces HyprPanel's built-in; bar icon delegates to swaync-client)
- **Display:** Wayland-native (Hyprland)
- **Colour scheme:** matugen

## Fonts

| Role | Font | Package |
|------|------|---------|
| UI / sans-serif | Inter | `inter-font` (extra) |
| Monospace + icons | JetBrainsMono Nerd Font | `ttf-jetbrains-mono-nerd` (extra) |

Font config locations:
- **GTK/GNOME:** gsettings (`org.gnome.desktop.interface` font-name / monospace-font-name)
- **Kitty:** `~/.config/kitty/kitty.conf` (`font_family`)
- **HyprPanel:** `~/.config/hyprpanel/config.json` (`theme.font.name`)
- **System fallback:** `~/.config/fontconfig/fonts.conf`

## Key Paths

| Purpose | Path |
|---------|------|
| Hyprland config | `~/.config/hypr/hyprland.conf` |
| zsh config | `~/.zshrc`, `~/.zprofile` |
| zsh theme | `~/.zsh-themes/custom-z89.zsh-theme` |
| custom scripts | `~/.local/bin/` |
| systemd user units | `~/.config/systemd/user/` |

## Environment Variables (from `~/.zshrc`)

```
TERMINAL=kitty
VISUAL=nvim
EDITOR=nvim
BROWSER=chromium
CHROME_EXECUTABLE=/usr/bin/chromium
ROCM_PATH=/opt/rocm
SSH_AUTH_SOCK=/run/user/1000/ssh-agent.socket
PNPM_HOME=~/.local/share/pnpm
```

## Git / GitHub Identity

- **Name:** z89
- **Email:** z89@matix.com.au
- **GitHub account:** z89
- **SSH key:** `~/.ssh/id_ed25519` loaded via ssh-agent at `/run/user/1000/ssh-agent.socket`
- Before any git operation, follow `~/.claude/skills/commit/SKILL.md`

## Debugging Approach (for this system)

When diagnosing issues, check in this order:
1. `journalctl -xe --no-pager | tail -50` — systemd logs
2. `dmesg | tail -30` — kernel messages
3. `systemctl --user status <unit>` or `systemctl status <unit>` — specific service
4. Relevant config file in `~/.config/<app>/`
5. `yay -Qi <pkg>` — check installed version and deps

## Rules

- Never suggest distro-agnostic workarounds when a proper Arch/pacman solution exists
- Prefer editing config files directly over GUI tools
- Prefer systemd user units (`~/.config/systemd/user/`) for user-level services
- Scripts go in `~/.local/bin/` and must be `chmod +x`
- When installing AUR packages, check for a `-bin` variant first to avoid compiling from source
- **Never edit generated config files directly.** If matugen generates configs from templates, edit the template source instead.
