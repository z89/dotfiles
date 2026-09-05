# DankMaterialShell on this machine

DMS replaced HyprPanel as the bar/launcher/lock/notification shell in September 2026. This
directory holds its settings plus the pieces that make a wallpaper switch recolour the whole
desktop in one motion. Everything generated (themes, palettes, thumbnails, the patched shell
tree, icon overlays) is rebuilt from the tracked files below; nothing under `~/.themes`,
`~/.cache` or `~/.local/share` is tracked.

## What is tracked

| Area | Files |
|---|---|
| DMS config | `settings.json`, `plugin_settings.json`, `plugins/persona/`, `patches/notification-popup-card.qml` |
| Patched shell | `~/.local/bin/dms-shell-patch` (builder), `~/.local/bin/dms-run-patched` (ExecStart wrapper), `~/.local/bin/dms-shim/gsettings` |
| Theme pipeline | `~/.local/bin/theme-apply`, `~/.local/bin/palette-gen`, `~/.local/bin/theme-switch`, `~/.local/bin/papirus-dank-build`, `~/.local/bin/app-relaunch` |
| matugen | `~/.config/matugen/config.toml` and `templates/` (gtk, hypr colours and borders, satty, kitty and friends) |
| systemd user | `dms.service.d/override.conf`, `theme-apply.path` + `.service`, `theme-sync.timer` + `.service`, `theme-sync-dconf.path` |
| GTK | `~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/gtk.css` (both import nothing, on purpose), `~/.config/environment.d/60-gtk-theme.conf` |
| Hyprland | `~/.config/hypr/hyprland.lua` (loads `dms/colors.lua` and `borders.lua`, both matugen output) |

## Fresh install

Packages: `dms-shell-git` (AUR), `quickshell`, `matugen`, `imagemagick`, `glib2-devel` (for
`gresource`), `libadwaita`, `adw-gtk-theme`, `papirus-icon-theme`, `papirus-folders`, `kitty`,
`jq`. `grim` is only needed for measuring.

1. Clone the dotfiles into `$HOME` and log in to a Hyprland session.
2. `papirus-dank-build` creates the user-writable `Papirus-Dank` / `Papirus-Dank-B` icon overlays
   that theme-apply recolours and flips between.
3. `systemctl --user daemon-reload` then
   `systemctl --user enable --now dms.service theme-apply.path theme-sync.timer theme-sync-dconf.path`.
   The `dms.service` override runs `dms-run-patched`: on a fresh machine it starts stock DMS,
   builds the patched shell from the installed binary's embedded QML in the background, and
   restarts itself once so the patched UI takes over. After every `dms-shell-git` upgrade it does
   the same again.
4. Log out and in once so `environment.d/60-gtk-theme.conf` (`GTK_THEME=Matugen-A`) reaches
   every process. To apply it to the running session instead:
   `systemctl --user set-environment GTK_THEME=Matugen-A`, `systemctl --user restart dms.service`
   and `hyprctl eval 'hl.env("GTK_THEME", "Matugen-A")'`.
5. Pick a wallpaper (`theme-switch <image>` or the DMS picker). That first switch generates
   `~/.themes/Matugen-A` and `-B`, the kitty palette, the GTK palette files and everything else.

## How a switch works

`dms ipc call wallpaper set` starts it. DMS loads the image and runs matugen on a cached 640px
thumbnail (`scripts/dms-matugen-thumb`, written by the builder; the full 5120x1440 image took
300ms, the thumbnail 45ms with an identical palette). matugen writes the templates, including
`~/.config/gtk-3.0/dank-colors.css`, which fires `theme-apply.path`.

theme-apply prepares everything without showing it: generates both Matugen themes, the kitty
palette, the recoloured folder icons, the Hyprland border colours, then tells DMS it is ready
(`dms ipc call theme consumerReady`). DMS holds the new palette until the wallpaper is decoded,
theme-apply is ready and every bar window has snapshotted itself, then releases it: the
wallpaper crossfades, the bar crossfades a snapshot of its old self over the new colours, and the
first presented frame is stamped to `~/.cache/DankMaterialShell/palette-applied.stamp`.
theme-apply anchors the kitty fade and the GTK flip on that stamp, so terminals, GTK apps, bar and
wallpaper move together (about 400ms after the click, 500ms fade).

GTK details worth knowing before changing anything:

- GTK never re-reads `~/.config/gtk-*/gtk.css` in a running process, but it reloads the *theme*
  whenever the gtk-theme setting changes. theme-apply therefore bakes the palette into two
  identical themes, Matugen-A and Matugen-B, and flips the setting between them every switch.
- libadwaita apps (Nautilus, Settings) ignore the gtk-theme setting, but when `GTK_THEME` is set
  in the environment libadwaita skips its built-in stylesheet and GTK loads that theme instead,
  and re-reads it from disk on every flip like any other GTK process. So the Matugen gtk-4.0
  theme imports libadwaita's own compiled stylesheet, which theme-apply extracts from
  `libadwaita-1.so` into the theme dir (`adwaita.css` + `assets/`) whenever the library is newer.
  This is why the user `gtk-4.0/gtk.css` must import nothing: a user stylesheet outranks the
  theme and is read once, so any import there pins old colours.
- GTK4 apps on Wayland receive settings through xdg-desktop-portal. Do not restart the portal
  backend during a switch; it delayed libadwaita reloads by one to two seconds.
- DMS's own worker writes `gtk-theme`, `icon-theme` and `accent-color` through gsettings after
  every matugen run, restyling apps ahead of the fade. `dms-run-patched` prepends
  `~/.local/bin/dms-shim` to PATH; its `gsettings` drops those three writes and passes everything
  else through. theme-apply owns them.
- The Hyprland config loads the matugen colour files at config load only; theme-apply pushes the
  border colours with `hyprctl keyword`, never `hyprctl reload` (a reload recreated the headless
  output and stalled the shell).

## Rules

- Never edit `~/.local/share/dms-shell-patched` by hand. Change `dms-shell-patch`, run it, then
  `systemctl --user restart dms.service` immediately. Quickshell hot-reloads changed files and
  aborts on a half-built tree, which is why the builder rename-swaps the directory.
- The builder needs DMS's stock QML. It uses the runtime extraction when present and falls back to
  `~/.cache/dms-shell-stock/<rev>`; the script header explains how to repopulate that cache from
  the upstream tarball after an upgrade if the extraction is gone.
- Measure, never eyeball: add `log.info` lines to the QML and read `journalctl --user -u dms.service`,
  sample frames with `grim -t ppm`, and watch `dconf watch /org/gnome/desktop/interface/` to see
  who restyles GTK. theme-apply logs each step's timing to `~/.local/state/theme-apply/log`.
