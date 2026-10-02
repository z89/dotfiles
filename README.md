<h1 align="center">dotfiles</h1>

<p align="center">
  <img src="https://img.shields.io/badge/arch%20linux-6.18.54--lts-7ee0d6?style=flat-square&labelColor=1b1a20" alt="arch linux 6.18.54-lts">
  <img src="https://img.shields.io/badge/hyprland-0.56.2-7ee0d6?style=flat-square&labelColor=1b1a20" alt="hyprland 0.56.2">
  <img src="https://img.shields.io/badge/DMS-1.7--beta-7ee0d6?style=flat-square&labelColor=1b1a20" alt="DMS 1.7-beta">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-7ee0d6?style=flat-square&labelColor=1b1a20" alt="license MIT"></a>
</p>

dotfiles for an arch linux desktop running hyprland, with [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS) as the bar, launcher, lock screen and notifications, and kitty with zsh and starship as the terminal. the whole desktop recolours itself from the current wallpaper.

the repo also holds the package lists and system files needed to rebuild the machine, a patched build of the DMS shell, the `persona` bar widget, the scripts in `~/.local/bin`, and the claude code setup.

## ✨ highlights

- 🪟 **window carry** moves the active window to another workspace with a spring animation on `Super + Shift + period` and `comma`, or `Super + Shift + 1` to `0`. it is written in plain lua inside hyprland and covered by offline tests.
- 🎨 **wallpaper theming** fades kitty and the text already printed in it, gtk, spotify, notion, the hyprland borders and the portal onto a new wallpaper's palette together, about 400ms after the click.
- 🧩 **a patched DMS** comes from `dms-shell-patch`, which rebuilds the shell with a wider launcher, a compact notification card, a lock screen crossfade and synced palette fades, and applies itself again after a DMS upgrade.
- 🎯 **focus or launch** jumps to an app's existing window, on whatever workspace it is on, instead of starting a second copy.
- 🔗 **links from other apps** open in a browser window on the current workspace.
- 🔐 **boot and login** use a touch-only fido2 disk unlock from `luks-boot-setup`, with a plymouth theme drawn from the current palette, and greetd with the DMS greeter.

## 📦 rebuild

```sh
sudo pacman -S --needed - < pkglist/native.txt
paru -S --needed - < pkglist/aur.txt
sudo dotfiles-sync --apply
dms-plugins
systemctl --user enable dms.service cliphist.service ssh-agent.service theme-apply.path theme-sync-dconf.path theme-sync.timer hyprpolkitagent.service
dconf load /org/gnome/desktop/interface/ < ~/.config/gsettings/interface.ini
```

`dotfiles-sync --apply` copies the mirrored system files in `system/` back onto `/`. plain `dotfiles-sync` refreshes the mirror, the package lists and the service lists, so `git status` shows drift. secrets and machine identity are never mirrored.

[auris](https://github.com/z89/auris) and [ember](https://github.com/z89/ember) live in their own repos. `dms-plugins` clones them and links them into `~/.config/DankMaterialShell/plugins/`. auris also needs its daemon, which its readme sets up. video wallpapers come from [eco](https://github.com/z89/eco) (private for now), which is optional. clone it, run its `bin/eco-install` and restart `dms.service`. [`.config/DankMaterialShell/README.md`](.config/DankMaterialShell/README.md) has the full DMS install sequence.

## 📁 layout

| path | what it holds |
| --- | --- |
| 🪟 `.config/hypr/` | `hyprland.lua`, `carry.lua`, notification focus and their tests |
| 🧩 `.config/DankMaterialShell/` | DMS settings, shell patches and the `persona`, `cpumon`, `memmon` and `gpumon` plugins |
| 🎨 `.config/matugen/` | colour templates filled from the wallpaper |
| 🐱 `.config/kitty/` | terminal config, with the prompt in `.config/starship.template.toml` |
| 🔧 `.local/bin/` | theme, launcher, screenshot, boot and agent scripts |
| 💽 `system/` | mirrored `/etc` and `/usr` files and the enabled service lists |
| 📦 `pkglist/` | explicitly installed native and aur packages |
| 🤖 `.claude/` | claude code instructions, settings, guard hooks and skills |

generated colour files are not tracked and are recreated on first start.

## 📄 license

MIT
