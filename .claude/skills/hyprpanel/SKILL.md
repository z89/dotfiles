---
name: hyprpanel
description: Context and rules for any task involving hyprpanel — patched launcher, custom SCSS, theme switcher, and color interpolation engine
argument-hint: [task description]
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# HyprPanel Custom Setup

Load this before any task that touches hyprpanel config, SCSS, JS patches, theming, or the launch chain.

---

## Critical: Always Use the Patched Launcher

**Never start hyprpanel with `hyprpanel`, `hyprpanel -q`, or `/usr/share/hyprpanel/hyprpanel-app` directly.** A PreToolUse hook (`~/.claude/hooks/hyprpanel-guard.py`) hard-blocks these and direct `gjs -m … dmFyIF-ags.js` launches.

The stock binary skips all JS patches (modules stretch to bar height, menus misposition, notification images mis-align).

| Action | Correct command |
|--------|----------------|
| Start / restart | `~/.config/hyprpanel/bin/hyprpanel-launch` |
| Kill only | `pkill -f "gjs.*dmFyIF-ags.js"` |
| CLI to running instance | `hyprpanel <cmd>` (rc, cfc, applyTheme, toggleWindow …) — allowed |

`hyprpanel-launch` is the **single source of truth** for the start sequence and is theme-switcher aware. In order it: two-stage kills any running instance (SIGTERM → SIGKILL, since a frozen main loop ignores the graceful SIGTERM), removes a stale Astal D-Bus socket, persists the last theme colors (`colors-new.json`) into `config.json`, rotates diagnostic logs, then starts `hyprpanel-patched` with stderr captured to `/tmp/hyprpanel-stderr.log`. Add new start-time logic **here only** — never in a parallel path.

---

## Launch Chain

```
hyprland.lua  hl.on("hyprland.start", ...)
  └─ ~/.config/hyprpanel/bin/hyprpanel-watchdog   (owns lifecycle; sole parent)
       └─ ~/.config/hyprpanel/bin/hyprpanel-launch  (called on start + every restart)
            └─ ~/.config/hyprpanel/bin/hyprpanel-patched
                 1. Runs stock hyprpanel-app with gjs launch line stripped (sed '/gjs /d')
                    → decodes JS bundle to $XDG_RUNTIME_DIR/dmFyIF-ags.js without executing it
                 2. Applies sed/python patches to decoded JS (incl. diagnostic instrumentation)
                 3. Runs: gjs -m $XDG_RUNTIME_DIR/dmFyIF-ags.js
```

The **watchdog** is the `exec-once` target (not `hyprpanel-launch` directly). It monitors `/tmp/hyprpanel-heartbeat` and restarts on freeze/death — always by calling `hyprpanel-launch`, so the theme-switcher-aware start path is never bypassed. See **Freeze Watchdog & Diagnostics** below.

**Update risk:** If a HyprPanel package update changes the gjs invocation line in the stock script, the sed filter `/gjs /d` may stop matching. Symptom: modules stretch to bar height (valign patch not applied). Check the stock script at `/usr/share/hyprpanel/hyprpanel-app` if this happens.

---

## Freeze Watchdog & Diagnostics

The GJS main loop occasionally freezes (bar renders but clock stops, clicks/hover dead). `hyprpanel-watchdog` detects and recovers from this, and the `hyprpanel-patched` bundle is instrumented to diagnose the cause.

**Instrumentation** (injected by `hyprpanel-patched` at the end of the bundle):
- **Heartbeat:** a `GLib.timeout_add` writes `/tmp/hyprpanel-heartbeat` every 2 s and logs `HEARTBEAT` to `/tmp/hyprpanel-diag.log`. When it stalls, the main loop is blocked.
- **Command trace:** the Astal `vfunc_request` handler logs `CMD_START`/`CMD_END <ms>` per CLI call. A `CMD_START` with no `CMD_END` = the hung command.
- **themeManager wrappers:** `applyCss`, `applyColorOverrides`, `_compileSass`, `_applyCss` log `_START`/`_END <ms>`/`_THROW`/`_REJECT`, so a freeze during theming shows the exact stage. (Boot's first `applyCss` runs during module eval, before wrappers install, so it isn't traced — expected.)

**Watchdog** (`hyprpanel-watchdog`):
- Polls the heartbeat; on >8 s stale (freeze) or no gjs process (death) it captures a freeze set to `~/.local/state/hyprpanel-freezes/` — `freeze-<ts>.log` (per-thread wchan/syscall, gdb backtraces if Yama allows, log tails), `freeze-<ts>.events.log` (all non-HEARTBEAT diag lines: CMD_*/theme stages/errors), and `freeze-<ts>.stderr.log`. This dir is **persistent (survives reboot)** unlike the `/tmp` live logs; pruned to the newest 100 sets. It then sends **SIGABRT** to trigger a `systemd-coredump` for postmortem (`coredumpctl gdb <pid>`, also reboot-safe), and restarts via `hyprpanel-launch`.
- **Circuit breaker:** ≥3 restarts within 180 s pauses restarts for 15 min and sends a critical `notify-send`, preventing a restart spin-loop.
- Diagnostic logs auto-rotate at 5 MB (`.1` segment) inside `hyprpanel-launch`.

**If gdb attach in the report says "Operation not permitted":** that's `ptrace_scope=1` (Yama). Use the coredump instead — `coredumpctl gdb` then `thread apply all bt`.

---

## JS Bundle Patches

### 1. Bar module vertical alignment

`valign: FILL` on the bar's three box containers (`box-left`, `box-center`, `box-right`) stretches all modules to full bar height. The patch injects `valign: Gtk4.Align.CENTER` on each so modules stay at their natural height and are vertically centered within the taller bar set in `modules.scss`.

### 2. Notification image centering

Adds `valign: Gtk4.Align.CENTER` to `notification-card-image-container`.

### 3. Dropdown menu positioning

On an ultrawide with large `theme.bar.margin_sides`, `hyprpanel toggleWindow` positions menus at the wrong X offset. A Python patch intercepts the `toggleWindow` handler, reads `theme.bar.margin_sides` and `theme.bar.outer_spacing` from live config, and sets correct left/right margins on the dropdown event box before toggling.

---

## Custom SCSS (`~/.config/hyprpanel/modules.scss`)

HyprPanel's SCSS pipeline (in `/usr/share/hyprpanel/src/style/index.ts`):

1. Writes theme variables to `/tmp/hyprpanel/variables.scss`
2. Loads `/usr/share/hyprpanel/src/style/main.scss`
3. Prepends the variables `@import`
4. **Appends `modules.scss` content verbatim at the end**
5. Compiles with: `sass --load-path=/usr/share/hyprpanel/src/style /tmp/hyprpanel/entry.scss /tmp/hyprpanel/main.css`

Because `modules.scss` is concatenated (not imported), standard SCSS variables like `$notification-label` from HyprPanel's own SCSS are available. `@import` with an absolute path also works.

### Current rules

| Rule | Purpose |
|------|---------|
| `.bar .bar-panel { min-height: 60px }` | Bar height |
| `.bar_item_box_visible { min-height: 25px }` | Module height (combined with valign CENTER patch gives ~17px padding above/below) |
| `.event-top-padding * { margin-top: 40px }` | Pushes dropdown content below bar |
| `.close-notification-button` | Transparent close button, top-aligned, uses `$notification-label` / `$notification-text` |
| `.notification-card-header-label` | Removes left padding from notification title |
| `.notification-icon` | Fully collapses redundant title icon |

**Do not add `@import` statements at the top of `modules.scss` — they get appended after the full compiled stylesheet and can interfere with sass's import ordering.** If SCSS variables from an external file are needed, either use absolute paths and test compilation manually first, or pre-compute the values in the matugen template and output them as plain CSS.

---

## Theme Switcher (`~/.config/hyprkit/theme-switch/`)

### `theme-switch` (orchestrator)

```
theme-switch [<wallpaper>|--random]   # apply wallpaper + regenerate all colors
theme-switch                          # open rofi wallpaper picker
```

On invocation:
1. Gets cursor position from `hyprctl cursorpos` for circle reveal origin
2. Saves current colors to `/tmp/*-old.*` (kitty, hyprland, gtk3, gtk4, spicetify)
3. Runs `hyprpanel-colors <wallpaper>` in background (computes old/new hyprpanel JSON)
4. Runs `matugen image <wallpaper>` (writes all registered templates)
5. Maps primary color to nearest GNOME accent + Papirus folder color
6. Changes Papirus folder icon color via `papirus-color` (~0.3s, symlinks only, no cache rebuild)
7. Starts swww wallpaper transition (circle grow from cursor, 1.5s, 60fps)
8. Reloads swaync CSS (`swaync-client --reload-css`)
9. Starts `color-fade kitty hyprland hyprpanel gtk3 nautilus spotify` in background
10. CDP hot-reloads Notion (port 9223) if running
11. Restarts xdg-desktop-portal-gtk after 2s delay (GTK file chooser color pickup)

### `color-fade` (interpolation engine)

A Python engine that drives all color targets through one synchronized animation loop.

- **Duration:** 0.4s default, ease-in-out cubic easing
- **Global frame rate:** 60fps base, per-target `max_fps` caps (30fps for heavier targets)

#### Targets

| Target | Method | FPS | Description |
|--------|--------|-----|-------------|
| `kitty` | Persistent Unix socket, kitty remote protocol | 60 | Terminal palette colors |
| `hyprland` | Persistent IPC socket, one `eval hl.config({...})` per frame | 60 | Border/shadow/glow colors |
| `hyprpanel` | CSS string splice + persistent `CssProvider` reload via Astal socket | 30 | All 400+ theme colors in compiled CSS |
| `gtk3` | CSS offset splice, write to `~/.config/gtk-3.0/gtk.css` | 30 | Blueman and other GTK3 apps |
| `nautilus` | CSS offset splice, write to `~/.config/gtk-4.0/gtk.css` | 30 | Nautilus via mtime-polling extension |
| `spotify` | CDP WebSocket, `Runtime.evaluate` sets CSS variables | 30 | Spicetify color properties |

All targets share one frame loop and use the same easing curve so colors transition in lockstep.

#### Performance optimizations

- **Pre-flattened RGB arrays:** Old/new colors separated into parallel `old_r[]`, `old_g[]`, `old_b[]`, `new_r[]`, `new_g[]`, `new_b[]` lists. Per-frame interpolation uses direct index access, no tuple allocation.
- **Hex lookup table:** `_HEX = [f"{i:02x}" for i in range(256)]` eliminates per-channel f-string formatting.
- **Persistent socket connections:** Kitty, hyprland, and spotify open connections once in `*_init()` and reuse across all frames. Eliminates connect/close overhead per frame.
- **Hyprland eval IPC:** Direct Unix socket instead of spawning `hyprctl` processes (was 120 process spawns/sec). A Lua config rejects `keyword` outright ("keyword can't work with non-legacy parsers. Use eval."), so all three colors go in a single `eval hl.config({...})` — one round trip per frame, replacing the old three-command `[[BATCH]]`.
- **CSS splice maps:** GTK3/nautilus targets build byte-offset maps at init (`_css_build_splice_map`), then per-frame use string slicing instead of regex.
- **HyprPanel CSS splice:** Reads compiled CSS once at init, does string `.replace()` of old hex values with interpolated values per frame, writes to `/tmp/hyprpanel/main.css`, triggers `reloadCss` which reloads a persistent `CssProvider` (~17ms total vs 200ms for full `applyTheme`). Uses a bridge function to map theme keys to unique old hex values for CSS replacement.

#### HyprPanel target deep dive

The key insight: `applyTheme` triggers `_compileSass()` which runs the system `sass` compiler (~200ms per call, far too slow for 30fps). The `reloadCss` command (added via JS patch) uses a persistent `CssProvider` that is created once and reloaded each frame via `load_from_path()`, avoiding both SCSS recompilation and CSS provider accumulation (~17ms per frame including file write + socket round-trip).

**Key mapping (bridge function):** The old/new JSON files use theme keys (`theme.bar.background`) as keys and `#hex` as values. Since the old and new themes have entirely different hex values, you can't find "common" entries by hex. The `hyprpanel_bridge` function finds common theme keys between old and new, then re-keys both to unique old hex values (preserving original case for CSS string matching). This produces ~30 interpolation keys instead of 380+ theme keys, and the output `{old_hex: interpolated_hex}` can be used directly for CSS replacement.

Flow per frame:
1. Interpolate ~30 unique hex values using ease-in-out cubic easing
2. Read the CSS template (captured at init from `/tmp/hyprpanel/main.css`)
3. String-replace each old `#hex` with its interpolated `#hex`
4. Write the result back to `/tmp/hyprpanel/main.css` via low-level `os.open`/`os.write`
5. Send `reloadCss` to the Astal socket — reloads the persistent `CssProvider` in-place

After the fade completes, `hyprpanel_finalize()` sends `applyTheme /tmp/hyprpanel-colors-new.json` to sync `config.json` state with the final colors, then sends `clearFadeCss` to remove the persistent fade provider (so it doesn't override future theme updates).

**If it breaks:** The most likely failure is `reloadCss` not being recognized (HyprPanel update overwrites JS bundle). Restart with `hyprpanel-launch` to re-apply all patches including the reloadCss command injection. Check `hyprpanel rc` manually to verify.

### `hyprpanel-colors` (color mapper)

Python script that:
1. Reads current `/tmp/hyprpanel/variables.scss` hex values → saves as `/tmp/hyprpanel-colors-old.json`
2. Runs `matugen image <wallpaper> --dry-run --json hex` to get new Material Design palette
3. Maps each Catppuccin default hex → catppuccin name → matugen variation token → new hex
4. Writes `/tmp/hyprpanel-colors-new.json`

Both JSON files use `{theme_key: "#hex"}` format. `color-fade` finds common theme keys, then uses `hyprpanel_bridge` to re-key to unique old hex values for CSS replacement.

### Nautilus live-reload extension

A Nautilus extension at `~/.local/share/nautilus-python/extensions/matugen-css-reload.py` handles two things:

**1. CSS live-reload (color fade)**
- Registers a `Gtk.CssProvider` at priority 10000 (overrides libadwaita defaults)
- Polls `~/.config/gtk-4.0/gtk.css` mtime every 100ms via `GLib.timeout_add`
- When mtime changes, reloads the CSS via `_provider.load_from_path()`
- `color-fade`'s `nautilus` target writes interpolated CSS to that path every frame

GFileMonitor was tried but events don't reliably dispatch inside nautilus-python. Mtime polling at 100ms is reliable and low overhead.

**2. Papirus folder icon refresh**
- Polls `/tmp/papirus-icons-changed` mtime every 100ms
- When the signal file is touched (by `theme-switch` after `papirus-color` runs), cycles `Gtk.Settings` `gtk-icon-theme-name` from "Papirus-Dark" → "hicolor" → "Papirus-Dark"
- Both property changes happen synchronously in one callback, so no frame renders the intermediate "hicolor" state (no flash)
- This triggers Nautilus's internal `notify::gtk-icon-theme-name` handler which invalidates icon caches and re-renders folder icons

### Papirus folder icon colors

`papirus-color` at `~/.local/bin/papirus-color` is a fast replacement for `papirus-folders` that only changes symlinks (~0.3s) without rebuilding icon caches (~3s). The stock `papirus-folders` rebuilds caches for all 3 Papirus variants via `gtk-update-icon-cache`, which is unnecessary since the Nautilus extension forces icon refresh via `GtkSettings` toggle.

- Sudoers NOPASSWD entry at `/etc/sudoers.d/papirus-color` for `sudo /home/archie/.local/bin/papirus-color`
- Called with full path in theme-switch: `sudo /home/archie/.local/bin/papirus-color <color>`
- After symlinks change, theme-switch touches `/tmp/papirus-icons-changed` to signal the Nautilus extension

---

## Matugen Integration

### Registered templates (in `~/.config/matugen/config.toml`)

| Template | Output | Notes |
|----------|--------|-------|
| `hyprpanel-colors` | `~/.config/hyprpanel/matugen-colors.scss` | SCSS variables for HyprPanel |
| `hyprpanel-modules` | `~/.config/hyprpanel/modules.scss` | Custom SCSS overrides |
| `kitty-colors` | `~/.config/kitty/colors.conf` | Live path (kitty watches it) |
| `hyprland-colors` | `~/.cache/matugen/hyprland-colors.lua` | Cache path, copied to `~/.config/hypr/colors.lua` after fade |
| `gtk3-colors` | `~/.cache/matugen/gtk3-colors.css` | Cache path, copied to live after fade |
| `gtk4-colors` | `~/.cache/matugen/gtk4-colors.css` | Cache path, copied to live after fade |
| `spicetify-colors` | `~/.config/spicetify/Themes/matugen/color.ini` | |
| `vscode-colors` | `~/.vscode/extensions/matugen-theme/themes/matugen.json` | |
| `discord-colors` | `~/.config/BetterDiscord/themes/matugen.theme.css` | BetterDiscord watches via fs.watch |
| `notion-colors` | `~/.cache/matugen/notion-colors.css` | Applied via CDP hot-reload |
| `rofi-colors` | `~/.config/rofi/colors/matugen.rasi` | |
| `swaync-colors` | `~/.config/swaync/style.css` | Hot-reloaded via swaync-client |
| `starship-colors` | `~/.config/starship.toml` | |

**Cache vs live paths:** Templates that feed into `color-fade` targets write to cache paths. The `color-fade` engine reads new colors from cache, interpolates to the live path each frame, then `*_finalize()` copies the final cache file to the live path. This prevents matugen from writing final colors to the live path before the fade starts.

### `matugen-colors.scss`

Generated to `~/.config/hyprpanel/matugen-colors.scss` on every theme switch. Contains Material Design 3 color variables (`$matugen-primary`, `$matugen-surface-container`, etc.). **Never edit this file directly — it is overwritten by matugen.** Edit the template at `~/.config/matugen/templates/hyprpanel-colors` instead.

---

## Key File Paths

| File | Purpose |
|------|---------|
| `~/.config/hyprpanel/bin/hyprpanel-watchdog` | Lifecycle owner: hyprland exec-once target, monitors heartbeat, restarts on freeze via hyprpanel-launch |
| `~/.config/hyprpanel/bin/hyprpanel-launch` | Safe restart script — single source of truth for the start sequence; always use this |
| `~/.config/hyprpanel/bin/hyprpanel-patched` | Patched launcher (decodes + patches JS bundle, injects diagnostic instrumentation) |
| `~/.claude/hooks/hyprpanel-guard.py` | PreToolUse hook: blocks stock-binary starts + edits to regenerated/stock files |
| `/tmp/hyprpanel-diag.log` | Heartbeat + CLI command trace + themeManager stage trace |
| `/tmp/hyprpanel-stderr.log` | gjs stderr (GJS warnings/exceptions) |
| `~/.local/state/hyprpanel-freezes/` | Per-freeze reports + `.events.log` + `.stderr.log` — persistent (survives reboot), pruned to newest 100 |
| `/tmp/hyprpanel-heartbeat` | Liveness file (mtime updated every 2s); watchdog watches it |
| `~/.config/hyprpanel/modules.scss` | Custom SCSS overrides (appended to compiled stylesheet) |
| `~/.config/hyprpanel/matugen-colors.scss` | Generated matugen SCSS variables — do not edit |
| `~/.config/hyprpanel/config.json` | HyprPanel settings + 400+ theme color overrides |
| `~/.config/hyprpanel/README.md` | Detailed patch documentation |
| `~/.config/hyprkit/theme-switch/theme-switch` | Theme switch orchestrator |
| `~/.config/hyprkit/theme-switch/color-fade` | Color interpolation engine (Python) |
| `~/.config/hyprkit/theme-switch/hyprpanel-colors` | HyprPanel color mapper (Catppuccin → Material Design) |
| `~/.config/matugen/config.toml` | Matugen template registry |
| `~/.config/matugen/templates/hyprpanel-colors` | SCSS variable template source |
| `~/.local/share/nautilus-python/extensions/matugen-css-reload.py` | Nautilus CSS + icon live-reload extension |
| `~/.local/bin/papirus-color` | Fast Papirus folder symlink changer (no cache rebuild) |
| `/etc/sudoers.d/papirus-color` | NOPASSWD entry for papirus-color |

### IPC sockets used by color-fade

| Socket | Purpose |
|--------|---------|
| `/tmp/kitty-*` | Kitty remote control (persistent, reused across frames) |
| `/run/user/1000/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock` | Hyprland IPC (persistent, `eval` commands) |
| `/run/user/1000/astal/hyprpanel.sock` | Astal/HyprPanel socket (new connection per frame for `reloadCss`) |
| `localhost:9222` | Spotify CDP WebSocket (persistent, `Runtime.evaluate`) |
| `localhost:9223` | Notion CDP (used by theme-switch, not color-fade) |
