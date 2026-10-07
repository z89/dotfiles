<h1 align="center">DMS on this machine</h1>

[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS) replaced HyprPanel as the bar, launcher, lock screen and notification shell in September 2026. this directory holds its settings and the pieces that make a wallpaper switch recolour the whole desktop in one motion.

everything generated (themes, palettes, thumbnails, the patched shell tree and icon overlays) is rebuilt from the tracked files below. the patch and bundle tools have one source under `tooling/`, with links for the builder, patcher, runner, bundle selector and shims at their existing `~/.local/bin` paths. nothing under `~/.themes`, `~/.cache` or `~/.local/share` is tracked.

## 📦 install

it needs `dms-shell-git` (AUR), `quickshell`, `matugen`, `imagemagick`, `glib2-devel` (for `gresource`), `libadwaita`, `adw-gtk-theme`, `papirus-icon-theme`, `papirus-folders`, `kitty`, `jq`, `git`, `go`, `make`, `nodejs`, `python` and `util-linux`. the build tools are only for the network patch and never run in the background. `grim` is only for measuring.

1. clone the dotfiles into `$HOME` and log in to a hyprland session.
2. `papirus-dank-build` makes the user-writable `Papirus-Dank` and `Papirus-Dank-B` icon overlays that theme-apply recolours and flips between.
3. run `~/.local/bin/dms-network-build` as the desktop user from `$HOME`. it downloads the exact commit recorded by the installed `dms-shell-git` package, applies and tests the network patches, builds the backend and applies the visual patches.
4. run `systemctl --user daemon-reload` and then `systemctl --user enable --now dms.service theme-apply.path theme-sync.timer theme-sync-dconf.path`. the service's `dms-run-patched` wrapper starts a verified local bundle from step 3. startup never downloads or builds. after an upgrade or patch change, run the builder explicitly before activation. if no valid bundle matches the installed binary, startup uses stock DMS and records the reason in the journal. no builder restarts the desktop.
5. log out and in once so `environment.d/60-gtk-theme.conf` (`GTK_THEME=Matugen-A`) reaches every process. to apply it to the running session instead, run `systemctl --user set-environment GTK_THEME=Matugen-A`, `systemctl --user restart dms.service` and `hyprctl eval 'hl.env("GTK_THEME", "Matugen-A")'`.
6. pick a wallpaper with `theme-switch <image>` or the DMS picker. the first switch generates `~/.themes/Matugen-A` and `-B`, the kitty palette, the GTK palette files and everything else.

## 🎨 how a switch works

`dms ipc call wallpaper set` starts it. DMS loads the image and runs matugen on a cached 640px thumbnail (`scripts/dms-matugen-thumb`, copied from `tooling/bin/` by the builder). the DMS command shim uses the same helper, so an already cached thumbnail stays unchanged. the full 5120x1440 image took 300ms and the thumbnail 45ms, with an identical palette. matugen writes the templates, including `~/.config/gtk-3.0/dank-colors.css`, which fires `theme-apply.path`.

theme-apply prepares everything without showing it. it generates both Matugen themes, the kitty palette, the recoloured folder icons and the hyprland border colours, then tells DMS it is ready with `dms ipc call theme consumerReady`. DMS holds the new palette until the wallpaper is decoded, theme-apply is ready and every bar window has a snapshot of itself. then the wallpaper crossfades, the bar crossfades its old snapshot over the new colours, and the first presented frame is stamped to `~/.cache/DankMaterialShell/palette-applied.stamp`. theme-apply starts the kitty fade and the GTK flip from that stamp, so terminals, GTK apps, the bar and the wallpaper move together (about 400ms after the click, with a 500ms fade).

GTK has a few traps to know before changing anything.

- GTK never re-reads `~/.config/gtk-*/gtk.css` in a running process, but it reloads the theme whenever the gtk-theme setting changes. theme-apply bakes the palette into two identical themes, Matugen-A and Matugen-B, and flips the setting between them on every switch.
- libadwaita apps (Nautilus, Settings) ignore the gtk-theme setting. when `GTK_THEME` is set in the environment, libadwaita skips its built-in stylesheet and GTK loads that theme instead, re-reading it from disk on every flip. so the Matugen gtk-4.0 theme imports libadwaita's own compiled stylesheet, which theme-apply extracts from `libadwaita-1.so` into the theme dir (`adwaita.css` and `assets/`) whenever the library is newer. this is why the user `gtk-4.0/gtk.css` must import nothing. a user stylesheet outranks the theme and is read once, so any import there pins old colours.
- GTK4 apps on wayland get their settings through xdg-desktop-portal. don't restart the portal backend during a switch, it delayed libadwaita reloads by one to two seconds.
- DMS's own worker writes `gtk-theme`, `icon-theme` and `accent-color` through gsettings after every matugen run, which restyles apps ahead of the fade. `dms-run-patched` puts `tooling/shim/` first on PATH, and its `gsettings` drops those three writes and passes everything else through. theme-apply owns them.
- the hyprland config loads the matugen colour files at config load only. theme-apply pushes the border colours with `hyprctl keyword` and never `hyprctl reload`, since a reload recreated the headless output and stalled the shell.

## 📶 multiple Wi-Fi adapters

`patches/network-core.patch` and `patches/network-shell.patch` fix the single global Wi-Fi status DMS shows when more than one radio is connected. the backend follows the adapter a pending connection is actually on, clears the pending state when that adapter is removed, and otherwise keeps the adapter already connected. picking a device in the panel shows that device's status and networks, and connect, disconnect and scan act on the device shown, Auto mode included. a connection only counts as done on its own device, so another adapter on the same SSID can't complete it. no interface names, SSIDs or MAC addresses are hardcoded in the patches.

the network-type preference keeps IPv4 and IPv6 Wi-Fi route metrics that were set by hand (0 included) and only assigns metrics that are automatic or missing. the non-Wi-Fi behaviour is unchanged. set adapter priorities in networkmanager when both adapters are meant to carry traffic, since picking a device in DMS doesn't change routing or disconnect the other adapter.

### build and activate

run these in order as the desktop user from `$HOME`.

```sh
cd "$HOME"
~/.local/bin/dms-network-build
systemctl --user restart dms.service
systemctl --user is-active dms.service
```

the build prints a bundle directory under `~/.cache/dms-network/<hash>` when it works, and its tests and build output go to stderr. stop if it fails. the restart changes the live desktop, so an agent needs a desktop guard approval right before it. the last command should print `active`. keep old bundles until a new one has been tested live.

the cache key covers the packaged binary, build scripts, shared thumbnail helper and every patch template. builds run one at a time and are only published after the tests and build pass, and an existing bundle is never rewritten. `dms-bundle-state` records the completed binary and shell hashes and selects the release atomically. startup verifies the selected release and tries the previous verified release if needed. a changed patch does not cause a login-time build. a package upgrade requires a new matching build. the service and its `dms` shim use the same patched binary.

the builder runs the whole network test package with `-race`, the new shell logic tests and a distro and embedded shell build. each bundle keeps the patched source in `source/` for auditing. run `go test -race ./internal/server/network` and `go vet ./internal/server/network` from `<bundle>/source/core`, and `python3 quickshell/tests/run-qml.py` from `<bundle>/source`. the full QML runner also needs Xvfb and niri, and `make lint-qml` needs a quickshell tooling VFS. don't start an extra live shell just to get that VFS.

### spare USB adapter

the spare Realtek `2357:010c` is set to connect only by hand. only its own saved profile is changed, Wi-Fi stays on and other USB radios stay managed. this is specific to this machine and isn't applied on a fresh install.

find the profile's UUID with `nmcli connection show` and check it is the spare adapter before changing it.

```sh
nmcli connection modify uuid <uuid> connection.autoconnect no
nmcli -g connection.id,connection.interface-name,connection.autoconnect connection show uuid <uuid>
```

the second command should print the spare adapter's connection, its interface and `no`. stop if it names anything else. this only changes future auto-connection, not a connection that is already up. use the device picker in the panel to connect it when wanted. no Wi-Fi passwords are stored here.

### recovery

if activation fails, switch to stock DMS as the desktop user from `$HOME`. it leaves out the local patches until it's switched back.

```sh
systemctl --user set-environment DMS_NETWORK_STOCK=1
systemctl --user restart dms.service
systemctl --user is-active dms.service
```

an agent needs a desktop guard approval for each of these live actions. to go back once the patches are fixed and build again, run this.

```sh
~/.local/bin/dms-network-build
systemctl --user unset-environment DMS_NETWORK_STOCK
systemctl --user restart dms.service
```

to undo only the USB auto-connection change, run `nmcli connection modify uuid <uuid> connection.autoconnect yes`. never delete or change a bundle that a running process is using.

## 🛠 rules

- never edit a running shell tree. change the tracked patches or builders and run `dms-network-build`, which makes a new bundle that is never changed afterwards. switching to it is a separate service restart that needs approval. `dms-shell-patch` is the inner visual builder, and its old default output `~/.local/share/dms-shell-patched` is no longer used by the service wrapper.
- the builder needs the stock DMS QML. it uses the runtime extraction when there is one and falls back to `~/.cache/dms-shell-stock/<rev>`. the script header explains how to refill that cache from the upstream tarball after an upgrade if the extraction is gone.
- measure, never eyeball. add `log.info` lines to the QML and read `journalctl --user -u dms.service`, sample frames with `grim -t ppm`, and run `dconf watch /org/gnome/desktop/interface/` to see who restyles GTK. theme-apply logs each step's timing to `~/.local/state/theme-apply/log`.

## 📁 layout

| area | files |
|---|---|
| DMS config | `settings.json`, `plugin_settings.json`, `plugins/persona/`, `plugins/cpumon/`, `plugins/memmon/`, `plugins/gpumon/`, `patches/notification-popup-card.qml`, `patches/keybinds-content.qml` |
| patched shell | `tooling/bin/` holds the builder, patcher, bundle selector, runner and thumbnail helper. `tooling/shim/` holds the DMS command and gsettings shims. `tooling/tests/` holds the headless checks. `patches/` holds the network and visual patches. the builder, patcher, runner, selector and shim paths under `~/.local/bin/` link to these sources |
| theme pipeline | `~/.local/bin/theme-apply`, `~/.local/bin/palette-gen`, `~/.local/bin/theme-switch`, `~/.local/bin/papirus-dank-build`, `~/.local/bin/app-relaunch` |
| matugen | `~/.config/matugen/config.toml` and `templates/` (gtk, hypr colours and borders, satty, kitty and others) |
| systemd user | `dms.service.d/override.conf`, `theme-apply.path` and `.service`, `theme-sync.timer` and `.service`, `theme-sync-dconf.path` |
| GTK | `~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/gtk.css` (both import nothing on purpose), `~/.config/environment.d/60-gtk-theme.conf` |
| hyprland | `~/.config/hypr/hyprland.lua` (loads `dms/colors.lua` and `borders.lua`, both matugen output) |
| boot cover | `~/.local/bin/desktop-stage`, `desktop-gate` and `boot-cover` coordinate startup. `~/.config/quickshell/boot-cover/` draws the plymouth-matching cover |
