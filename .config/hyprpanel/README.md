# HyprPanel Custom Config

This directory contains a patched HyprPanel setup that fixes several stock behaviors.
HyprPanel is launched through a custom wrapper instead of the stock binary.

## Launch Chain

hyprland.conf `exec-once` calls:

1. **`swaync`** — Starts the swaync notification daemon. Must start before HyprPanel so it claims the `org.freedesktop.Notifications` DBus name first.

2. **`bin/hyprpanel-launch`** — Kills any running HyprPanel instance, then starts `hyprpanel-patched` in the background. Used as the `exec` target so hyprland reloads get a clean restart.

3. **`bin/hyprpanel-patched`** — The actual launcher. Decodes the stock JS bundle from `/usr/share/hyprpanel/hyprpanel-app`, applies runtime patches to the decoded JS, then starts gjs with the patched bundle.

### How the patched launcher works

The stock `hyprpanel-app` is a bash script that base64-decodes a JS bundle into `$XDG_RUNTIME_DIR/dmFyIF-ags.js` and immediately runs it with gjs. The patched launcher intercepts this by:

1. Running the stock script with the gjs launch line stripped out (`sed '/gjs /d'`), so the bundle gets decoded but not executed.
2. Applying sed patches to the decoded JS file.
3. Running gjs on the patched file.

**Important:** The sed pattern must match however the stock script invokes gjs. As of March 2026 the stock line is `LD_PRELOAD="" /usr/bin/gjs -m $file $@`. The filter uses `/gjs /d` (no `^` anchor) to handle this. If a HyprPanel update changes this line, the filter may need updating — the symptom will be hyprpanel launching unpatched (modules stretching to bar height, menus mispositioned).

## JS Bundle Patches

### 1. Bar module vertical alignment (valign: CENTER)

**Problem:** HyprPanel's bar containers (`box-left`, `box-center`, `box-right`) default to `valign: FILL`, which stretches all child modules to the full height of the bar. When the bar has a custom `min-height` (set in `modules.scss`), this removes the visual padding between modules and the bar edges.

**Fix:** Injects `valign: Gtk4.Align.CENTER` into the three box containers so modules stay at their natural height and are vertically centered within the taller bar.

Patched properties:
- `box-left`: adds `valign: Gtk4.Align.CENTER`
- `box-center`: adds `valign: Gtk4.Align.CENTER`
- `box-right`: adds `valign: Gtk4.Align.CENTER`

### 2. Notification image vertical centering

**Problem:** The notification card image container stretches to the full height of the notification card.

**Fix:** Adds `valign: Gtk4.Align.CENTER` to the `notification-card-image-container` element.

### 3. Dropdown menu positioning

**Problem:** When toggling dropdown menus via the CLI (`hyprpanel toggleWindow`), the menu position isn't calculated relative to the bar's margin and spacing settings. On an ultrawide monitor with large `margin_sides`, menus appear in the wrong location.

**Fix:** A python patch intercepts the `toggleWindow` handler to compute correct horizontal margins before toggling. It reads `theme.bar.margin_sides` and `theme.bar.outer_spacing` from the live config, calculates the anchor position, and sets left/right margins on the dropdown event box so the menu appears aligned with the bar.

### 4. swaync notification integration

**Problem:** HyprPanel's built-in notification panel (list, clear-all, scrolling) is extremely slow due to full list re-renders on every change, sequential notification dismissal with 100ms delays, and no DOM virtualization.

**Fix:** Three patches replace HyprPanel's notification system with swaync:

1. **Click handler** — The notification bar button's primary click runs `swaync-client -t` (toggle swaync panel) instead of `openDropdownMenu("notificationsmenu")`.

2. **Notification count** — The bar icon's count badge polls `swaync-client -c` every 2 seconds via a `GLib.timeout_add` and a `Variable` binding, replacing the stock `AstalNotifd.notifications` binding. The bell icon updates between empty/has-notifications states based on the swaync count.

3. **Popup tracking disabled** — `trackPopupNotifications(popupNotifications)` is commented out so HyprPanel doesn't show its own popup notifications (swaync handles all popups).

**DBus ownership:** swaync starts before HyprPanel (via `exec-once` ordering in hyprland.conf) and claims `org.freedesktop.Notifications`. HyprPanel's AstalNotifd initializes but doesn't receive notifications since it lost the DBus name race. The notification count is read from swaync's client API instead.

### 5. CSS flash fix (_applyCss reset parameter)

**Problem:** During `color-fade` theme transitions, `_applyCss()` calls `app_default.apply_css(path, true)` which wipes all CSS providers before re-applying. This causes a blank-CSS flash on every animation frame.

**Fix:** Adds a `reset` parameter to `_applyCss(reset = true)`. The `applyColorOverrides` call site passes `reset=false` so animation frames layer CSS without clearing existing providers. Full reloads still use `reset=true`.

### 6. reloadCss CLI command

Adds a `reloadCss` (alias: `rc`) command to the HyprPanel CLI. This is the critical patch that enables smooth 30fps HyprPanel color transitions during theme switching.

**What it does:** Re-reads `/tmp/hyprpanel/main.css` and applies it via `app_default.apply_css(path, false)` without triggering SCSS recompilation.

**Why it matters:** The stock `applyTheme` command triggers `_compileSass()` which runs the system `sass` compiler at ~200ms per call. The `reloadCss` command bypasses SCSS entirely and just loads the pre-compiled CSS file, completing in ~17ms (file write + socket round-trip). This makes 30fps color updates feasible.

**How color-fade uses it:**
1. At init, color-fade reads `/tmp/hyprpanel/main.css` as a template
2. Each frame, it string-replaces old hex values with interpolated values and writes the result back
3. It sends `reloadCss` to the Astal socket at `/run/user/1000/astal/hyprpanel.sock`
4. HyprPanel picks up the new CSS without any SCSS compilation

**Testing:** Run `hyprpanel rc` (or `hyprpanel reloadCss`) manually. If it returns "ok", the patch is working. If it returns an error or "Unknown command", the JS patch was not applied (restart with `hyprpanel-launch`).

**If it breaks after a HyprPanel update:** The patch targets a specific string in the decoded JS bundle (the `applyTheme` command block followed by `setLayout`). If HyprPanel restructures its CLI commands, the string match in `hyprpanel-patched` may fail silently. Check `hyprpanel rc` after updates.

### 7. modules.scss hot-reload monitor removal

**Problem:** HyprPanel watches `modules.scss` for changes and calls `applyCss(reset=true)` when it fires. During theme switching, matugen writes `modules.scss` and the GFileMonitor fires (with ~200-500ms delay) after color-fade has already started accumulating CSS providers. The `reset=true` wipes all animation providers, snapping colors back to the old theme mid-animation.

**Fix:** Removes `modules.scss` from the HotReload monitor file list. The new `modules.scss` content is still picked up on the first color-fade compilation frame since `_compileSass` reads it fresh.

## Custom SCSS (modules.scss)

Appended after HyprPanel's main SCSS during compilation, so these rules override stock styles. Generated by matugen from `~/.config/matugen/templates/hyprpanel-modules`.

### Bar height and module padding

```scss
.bar .bar-panel {
    min-height: 48px;
}
.bar_item_box_visible {
    min-height: 25px;
}
```

Sets a 48px bar with 25px modules. Combined with the valign: CENTER JS patch, this creates visual padding above and below each module.

### Event top padding

```scss
.event-top-padding * {
    margin-top: 40px;
}
```

Pushes dropdown menu content below the bar area.

### Notification close button

Strips the default close button styling and top-aligns it within the notification card. Uses theme SCSS variables (`$notification-label`, `$notification-text`) for colors.

### Notification card header

Removes left spacing from the notification title label and fully collapses the redundant title icon element (the small icon next to the app name, not the main notification icon).

## swaync Configuration

HyprPanel's notification panel is replaced by swaync. The notification bar icon remains in HyprPanel (bell + count badge) but clicking it toggles the swaync control center.

### Files

| File | Purpose |
|------|---------|
| `~/.config/swaync/config.json` | swaync settings (position, margins, widgets) |
| `~/.config/swaync/style.css` | Generated by matugen — do not edit directly |
| `~/.config/matugen/templates/swaync-colors` | Matugen template source for swaync CSS |

### Theme integration

swaync colors are generated by matugen using Material Design 3 tokens. The template at `~/.config/matugen/templates/swaync-colors` outputs `~/.config/swaync/style.css`. Colors update automatically on theme switch when matugen runs. After matugen writes the new CSS, run `swaync-client --reload-css` to hot-reload styles.

### Control flow

```
Bar notification icon click
  → swaync-client -t (toggle panel)

Bar notification count
  → GLib.timeout_add polls swaync-client -c every 2s
  → Updates bell icon (empty/has-notifications) and count label

Notification popups
  → Handled entirely by swaync (HyprPanel popup tracking disabled)

Theme switch
  → matugen generates ~/.config/swaync/style.css
  → swaync-client --reload-css applies new colors
```

## Color-Fade Integration

The `color-fade` engine at `~/.config/hyprkit/theme-switch/color-fade` drives smooth HyprPanel color transitions at 30fps. This section documents the full mechanism so it can be rebuilt if anything breaks.

### Architecture

```
theme-switch
  ├─ hyprpanel-colors <wallpaper>    → /tmp/hyprpanel-colors-{old,new}.json
  ├─ matugen image <wallpaper>       → writes all templates
  └─ color-fade ... hyprpanel ...    → reads JSON, splices CSS, sends reloadCss
```

### Per-frame flow (hyprpanel target)

1. **Init:** Reads `/tmp/hyprpanel/main.css` as a template string. Parses `/tmp/hyprpanel-colors-old.json` and `/tmp/hyprpanel-colors-new.json` to get unique hex → RGB mappings. Stores old hex keys in context for string replacement.

2. **Each frame (30fps):**
   - Interpolate all unique hex values using ease-in-out cubic easing
   - Take the CSS template and `.replace()` each old `#hex` with its interpolated `#hex`
   - Write the result to `/tmp/hyprpanel/main.css` via `os.open` + `os.write` (low-level, no buffering)
   - Open a new Unix socket to `/run/user/1000/astal/hyprpanel.sock`
   - Send `reloadCss`, call `shutdown(SHUT_WR)`, read response, close
   - Total per-frame cost: ~17ms

3. **Finalize:** After the fade completes, sends `applyTheme /tmp/hyprpanel-colors-new.json` via the Astal socket. This triggers a full SCSS recompile and syncs `config.json` with the final colors, so the next theme switch reads correct "old" values.

### Dependencies

The hyprpanel color-fade target depends on three things being present:

1. **`/tmp/hyprpanel-colors-old.json` and `/tmp/hyprpanel-colors-new.json`** — Generated by `hyprpanel-colors` script before color-fade starts. Contains `{"theme_key": "#hex", ...}` mappings.

2. **`/tmp/hyprpanel/main.css`** — The compiled CSS from HyprPanel's SCSS pipeline. Must exist before color-fade reads it as a template.

3. **The `reloadCss` JS patch** — Injected by `hyprpanel-patched` into the decoded JS bundle. Without it, there's no way to hot-reload CSS without triggering a 200ms SCSS recompile.

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| HyprPanel colors jump instead of fading | `reloadCss` patch missing | Restart with `~/.config/hyprpanel/bin/hyprpanel-launch` |
| Colors snap back mid-fade then re-animate | `modules.scss` hot-reload firing | Check that modules.scss monitor removal patch is applied |
| Colors flash white mid-fade | `_applyCss` called with `reset=true` | Check that `applyColorOverrides` passes `reset=false` |
| No color change at all | Missing old/new JSON files | Check that `hyprpanel-colors` ran before color-fade started |
| Colors end at wrong values | `hyprpanel_finalize` not running | Check that `applyTheme` call at end succeeds (Astal socket available) |

## Nautilus Extension

A Nautilus extension handles both smooth CSS color transitions and folder icon color updates during theme switches.

**File:** `~/.local/share/nautilus-python/extensions/matugen-css-reload.py`

### CSS live-reload

1. On Nautilus startup, registers a `Gtk.CssProvider` on the default `GdkDisplay` at priority 10000 (overrides libadwaita defaults)
2. Loads `~/.config/gtk-4.0/gtk.css` initially
3. Polls the file's mtime every 100ms via `GLib.timeout_add`
4. When mtime changes (color-fade wrote a new interpolated frame), reloads the CSS

GFileMonitor events don't reliably dispatch within the nautilus-python extension context. Both file and directory monitors were tested and neither fired callbacks. Mtime polling at 100ms is reliable and has negligible overhead.

### Papirus folder icon refresh

1. Polls `/tmp/papirus-icons-changed` mtime every 100ms
2. When the signal file is touched (by `theme-switch` after `papirus-color` completes), cycles `Gtk.Settings` `gtk-icon-theme-name`: "Papirus-Dark" → "hicolor" → "Papirus-Dark"
3. Both `set_property` calls are synchronous within one callback, so no frame renders the intermediate "hicolor" state (no visible flash)
4. The property change triggers Nautilus's `notify::gtk-icon-theme-name` handler, which invalidates its internal icon caches and re-renders all folder icons

**Why not `papirus-folders`?** Stock `papirus-folders` rebuilds `gtk-update-icon-cache` for all 3 Papirus variants (~3s). The custom `papirus-color` script at `~/.local/bin/papirus-color` only changes symlinks (~0.3s) and skips cache rebuilds entirely. The icon cache rebuild is unnecessary because the extension forces GTK to re-scan directories via the `GtkSettings` toggle.

**Why not `Gtk.IconTheme.set_theme_name()`?** Nautilus doesn't listen for changes on the `Gtk.IconTheme` object directly. It listens for `notify::gtk-icon-theme-name` on `Gtk.Settings`, which is what triggers its internal icon cache invalidation.

**Sudoers:** `/etc/sudoers.d/papirus-color` grants NOPASSWD for `sudo /home/archie/.local/bin/papirus-color`. The full path must be used because sudo's `secure_path` doesn't include `~/.local/bin`.

### Requirements

- `python-nautilus` package (provides `gi.repository.Nautilus`)
- Must use `gi.require_version("Nautilus", "4.1")` on this system
- Class must inherit from both `GObject.GObject` and a `Nautilus.*Provider` interface
- CSS priority must be 10000+ to override libadwaita styles

## Other Files

- **`config.json`** — HyprPanel settings (bar layout, module config, theme colors). Modified by both manual edits and the theme-switch system in `~/.config/hyprkit/`.
- **`modules.json`** — Module-specific JSON overrides (currently empty `{}`).
- **`matugen-colors.scss`** — Generated by matugen during theme switches.
