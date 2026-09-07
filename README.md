# dotfiles 

a collection of my dotfiles for my arch setup, below is a demo of the desktop running these dotfiles:

![desktop demo](assets/desktop-demo.gif)

## Rebuilding the desktop

Arch Linux, Hyprland (`~/.config/hypr/hyprland.lua`) and DankMaterialShell (DMS) as the bar and shell.

1. **Packages**: `pkglist/native.txt` and `pkglist/aur.txt` are the explicitly installed packages (`pacman -Qqen` / `pacman -Qqem`).
   `sudo pacman -S --needed - < pkglist/native.txt` then `yay -S --needed - < pkglist/aur.txt`.
2. **User services**: `systemctl --user enable dms.service cliphist.service ssh-agent.service theme-apply.path theme-sync-dconf.path theme-sync.timer hyprsunset-auto.timer hyprpolkitagent.service`.
3. **DMS**: settings live in `~/.config/DankMaterialShell/settings.json` and `plugin_settings.json`. `dms.service` runs through
   `~/.local/bin/dms-run-patched`, which uses a patched copy of the DMS shell built by `~/.local/bin/dms-shell-patch`
   (wider launcher centred between the bar and the screen edge, and a lock-screen crossfade: Super + Alt + L fades the lock
   screen in over the desktop and back out on unlock; `LOCK_FADE_IN`/`LOCK_FADE_OUT` set the durations, `LOCK_FADE=0` disables it).
   The patch rebuilds itself after a DMS upgrade.
4. **DMS plugins**: `~/.config/DankMaterialShell/plugins/` holds symlinks to clones of
   [z89/auris](https://github.com/z89/auris) (AirPods) and [z89/ember](https://github.com/z89/ember) (night light).
   The `persona` avatar plugin lives in this repo at `~/.config/DankMaterialShell/plugins/persona`; `avatar-make` builds its picture.
5. **Colours**: DMS runs matugen on wallpaper change. User templates are in `~/.config/matugen/`; `theme-apply.path` fires
   `~/.local/bin/theme-apply` to reload kitty, GTK, Spotify, Notion, VS Code and Hyprland borders. `theme-switch` picks a wallpaper.
6. **Fonts**: Inter (UI) and JetBrainsMono Nerd Font (mono). `~/.config/fontconfig/fonts.conf` sets the fallbacks and
   `~/.config/gtk-{3,4}.0/settings.ini` the GTK fallback. On Wayland GTK reads dconf, so load the tracked keyfile once:
   `dconf load /org/gnome/desktop/interface/ < ~/.config/gsettings/interface.ini` (fonts, cursor and dark scheme;
   theme and icon names are left to `theme-apply`). `font-switch` from hyprkit changes all of these at once later.
7. **Helpers from [z89/hyprkit](https://github.com/z89/hyprkit)**: `setup-spicetify`, `setup-betterdiscord` and `font-switch` in
   `~/.local/bin` are symlinks into a clone at `~/.config/hyprkit`.

Generated files are deliberately untracked and are recreated on first start: `~/.config/hypr/dms/`, `~/.config/hypr/colors.*`,
kitty `dank-tabs.conf` / `matugen-theme*.conf`, GTK `dank-colors.css` / `palette-colors.css`, and DMS `firefox.css`.
