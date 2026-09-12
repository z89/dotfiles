# dotfiles

a collection of my dotfiles for my arch setup: Hyprland, DankMaterialShell (DMS), kitty, and the scripts that keep the
whole desktop recoloured from the current wallpaper.

## Highlights

The custom-built parts of this setup, as opposed to configuration of things that already existed:

- **Window carry animation** (`~/.config/hypr/carry.lua`). Hyprland has no animation for sending a window to another
  workspace: the window simply disappears from one and reappears on the next. This adds one. `Super + Shift + period`
  and `comma` move the active window to the next or previous workspace, `Super + Shift + 1` to `0` send it to a
  specific one, and in both cases it now travels there. The module pins the live window so it floats above the
  workspace slide, turns off its own animations so every position write lands instantly, and drives it from a 2 ms Lua
  timer with two cascaded springs: the window leans away, the new workspace slides in underneath it, and it settles
  back into the exact spot it started from. The timer is paced against `/proc/uptime`, because it slows to 4-5 ms
  under the redraw load of a full-screen slide and a fixed step made the flight run at less than half speed. Unpinning
  can leave the window a pixel off, so a short landing phase reads the position back and corrects it before animations
  are switched on again. Pressing again mid-flight chains to the next workspace, but only once the arriving workspace
  has covered the middle of the window; before that the press is ignored, so a key repeat cannot queue up a stack of
  switches. It is plain Lua inside Hyprland's own config runtime, with no daemon, no patched compositor and no
  external process. Tunables are at the top of the file, there is a mock-backend test harness for the physics and the
  state machine, and if the module ever fails to load the keys fall back to the old shell carry.
- **Wallpaper-driven theme pipeline**. Matugen templates plus `theme-apply` fade kitty, GTK, Spotify, Notion, Hyprland
  borders and the portal onto a new palette on the same frame, in about 400 ms from clicking a wallpaper (section 6).
- **Patched DMS shell**. `dms-shell-patch` rebuilds DankMaterialShell with a wider launcher, a compact notification
  card, a lock-screen crossfade and synchronised palette fades, and re-applies itself after an upgrade (section 4).
- **DMS plugins**: [auris](https://github.com/z89/auris) for AirPods and [ember](https://github.com/z89/ember) for the
  night light, both in their own repos, plus the `persona` avatar widget which lives here (section 5).
- **Desktop glue**: `focus-or-launch` jumps to an app's existing window instead of starting a second copy,
  `browser-open` puts new links in a browser window on the workspace you are actually on, and `luks-boot-setup` makes
  the disk unlock fast, touch-only and styled like the rest of the desktop (sections 8, 9 and 11).

## Rebuilding the desktop

Arch Linux, Hyprland (`~/.config/hypr/hyprland.lua`) and DankMaterialShell (DMS) as the bar, launcher, lock screen and
notification shell. HyprPanel was retired in September 2026; its files under `~/.config/hyprpanel/` stay tracked until
sign-off and nothing starts them.

1. **Packages**: `pkglist/native.txt` and `pkglist/aur.txt` are the explicitly installed packages (`pacman -Qqen` / `pacman -Qqem`).
   `sudo pacman -S --needed - < pkglist/native.txt` then `yay -S --needed - < pkglist/aur.txt`.
2. **System files**: `system/etc` and `system/usr` mirror the parts of `/` this setup depends on (GRUB defaults,
   `mkinitcpio.conf`, Plymouth config, a split-lock sysctl, the `mirror-refresh` timer). `sudo dotfiles-sync --apply`
   copies them back onto `/`; plain `dotfiles-sync` refreshes that mirror, `pkglist/` and `system/services-*.txt` so
   `git status` shows drift. Secrets and machine identity (`crypttab.initramfs`, the mirrorlist) are deliberately not mirrored.
3. **User services**: `systemctl --user enable dms.service cliphist.service ssh-agent.service theme-apply.path theme-sync-dconf.path theme-sync.timer hyprsunset-auto.timer hyprpolkitagent.service`.
   The full enabled set (including project daemons such as `aurisd`, `os3d`, `hermes-gateway` and `dsearch`, whose units
   live in their own repos) is in `system/services-user.txt`; system units are in `system/services-system.txt`.
4. **DMS**: settings live in `~/.config/DankMaterialShell/settings.json` and `plugin_settings.json`. `dms.service` runs through
   `~/.local/bin/dms-run-patched`, which uses a patched copy of the DMS shell built by `~/.local/bin/dms-shell-patch`:
   a wider launcher centred between the bar and the screen edge, a wider Spotlight bar, a compact notification popup card
   (`patches/notification-popup-card.qml`), palette and wallpaper fades that land on the same frame, the volume percentage
   at the head of the control-centre pill, a "Thu 10th Sept" bar date, a 1600px bottom-centred Notepad slideout, and a lock-screen crossfade (Super + Alt + L fades the
   lock screen in over the desktop and back out on unlock; `LOCK_FADE_IN`/`LOCK_FADE_OUT` set the durations, `LOCK_FADE=0`
   disables it). The patch rebuilds itself after a DMS upgrade. `~/.config/DankMaterialShell/README.md` has the full
   fresh-install sequence and the list of every file in the theme pipeline.
5. **DMS plugins**: `~/.config/DankMaterialShell/plugins/` holds symlinks to clones of
   [z89/auris](https://github.com/z89/auris) (AirPods) and [z89/ember](https://github.com/z89/ember) (night light).
   The `persona` avatar plugin lives in this repo at `~/.config/DankMaterialShell/plugins/persona`; `avatar-make` builds its picture.
6. **Colours**: DMS runs matugen on wallpaper change. User templates are in `~/.config/matugen/`; `theme-apply.path` fires
   `~/.local/bin/theme-apply` to fade kitty, GTK (via a Matugen-A/B theme flip, with `GTK_THEME=Matugen-A` pinned in
   `environment.d`), Spotify, Notion, Hyprland borders and the portal to the new palette. `palette-gen` derives the terminal
   palette from the wallpaper accent, `papirus-dank-build` creates the recolourable Papirus-Dank icon overlays, and the
   `theme-sync` timer and dconf path repair the GTK theme pointer if DMS resets it. `theme-switch` picks a wallpaper
   (Super + Shift + W cycles); `app-relaunch` restarts an app that only reads colours at startup. Tracked wallpapers are in
   `~/Pictures/wallpapers/`.
7. **Fonts**: Inter (UI) and JetBrainsMono Nerd Font (mono). `~/.config/fontconfig/fonts.conf` sets the fallbacks and
   `~/.config/gtk-{3,4}.0/settings.ini` the GTK fallback. On Wayland GTK reads dconf, so load the tracked keyfile once:
   `dconf load /org/gnome/desktop/interface/ < ~/.config/gsettings/interface.ini` (fonts, cursor and dark scheme;
   theme and icon names are left to `theme-apply`).
8. **Single-window apps jump to their window**: user entries in `~/.local/share/applications/` override the package
   entries for Claude, Spotify, Discord, Notion, Mullvad, Telegram, ChatGPT, OBS, qBittorrent and Resources so Super + D runs
   `~/.local/bin/focus-or-launch <app> -- <exec>`. If the app has a window it is focused and Hyprland follows it to whatever
   workspace it is actually on; otherwise the app is started and followed once its window appears. Apps pinned by a
   `N silent` rule in `hyprland.lua` still land on their workspace (boot autostart stays silent, the wrapper does the
   following). Claude has no rule and opens where you are. Add an app: one line in the script's class table plus a copy of
   its desktop entry with Exec prefixed. Entries must use the script's full path, since `dms.service` has no `~/.local/bin`
   on its PATH. Revert one app by deleting its override; revert all by deleting them and the script.
9. **Links open where you are**: `browser-open.desktop` is the `http`/`https` handler in `~/.config/mimeapps.list` and runs
   `~/.local/bin/browser-open`. Chromium is single-instance and would otherwise put the new tab in whichever window it last
   saw focused, often on another workspace. The script opens the link in a Chromium window on the active workspace if one
   exists, and in a new window there if not. Revert with
   `xdg-mime default chromium.desktop x-scheme-handler/http x-scheme-handler/https`.
10. **Desktop helpers** in `~/.local/bin/`, bound in `hyprland.lua`: `screenshot` (grim + slurp + satty; Print copies an area,
    Shift + Print opens it for annotation, satty config in `~/.config/satty/`), `workspace-switch` (Super + comma / period,
    no wrapping; its `--move` window carry is now only the fallback for `carry.lua` above), `keybind-cheatsheet` (Super + slash, lists the bindings in rofi) and
    `hyprsunset-auto` (night light via hyprsunset and sunwait, checked by its timer every 15 minutes).
11. **Boot and login**: `sudo luks-boot-setup` makes the LUKS unlock fast and DMS-styled: a 2 s FIDO2 wait before the
    passphrase prompt, no root-device timeout while typing, the passphrase keyslot tried first, and the `dank-unlock`
    Plymouth theme that `plymouth-dank-theme` generates from the live palette and wallpaper. The `fido2-smart` and
    `windows-escape` mkinitcpio hooks it installs live in `~/.local/share/initcpio/`. Login is greetd with DankGreeter
    (the DMS lock-screen look), set up by `greeter-setup`. `system-tune` trims measured boot-time waste.
12. **Editors and tooling**: nvim config in `~/.config/nvim/`, VS Code settings and keybindings in `~/.config/Code/User/`,
    kitty in `~/.config/kitty/` (starship prompt from `~/.config/starship.template.toml`), Chromium/Notion/Spotify launch
    flags in `~/.config/*-flags.conf`. `~/.claude/` holds the Claude Code setup: `CLAUDE.md`, `settings.json`, guard hooks
    (terraform, AWS, git secret scan, hyprpanel) and the skills that document this machine. `agent-run` launches a coding
    agent under a GitHub App identity instead of the personal one, `mint-agent-token` issues its short-lived token, and
    `claude-prune-settings` keeps project-specific permission rules out of the tracked settings file.

Generated files are deliberately untracked and are recreated on first start: `~/.config/hypr/dms/`, `~/.config/hypr/colors.*`,
kitty `dank-tabs.conf` / `matugen-theme*.conf`, GTK `dank-colors.css` / `dank-vars.css` / `palette-colors.css`, and DMS `firefox.css`.
