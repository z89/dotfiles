# Chromium launch speed on this desktop

Reference for any "chromium is slow to open / laggy after opening" report. Measured 2026-09-06
on ungoogled-chromium-bin 152, RX 6600 (radeonsi), Hyprland + DMS. Read this before touching
flags, the profile, or the launcher.

## What is installed and what runs

- `ungoogled-chromium-bin` owns `/usr/bin/chromium`. That file is Arch's small launcher: it reads
  `~/.config/chromium-flags.conf`, sets `CHROME_DESKTOP=chromium.desktop`, then execs
  `/usr/lib/chromium/chromium`. Terminal and DMS launches hit the same binary and profile.
- `google-chrome` is also installed and shows as "Google Chrome" in the launcher. Its flags file is
  `~/.config/chrome-flags.conf` (absent), so it runs under XWayland. Nothing uses it.
- `Super + D` opens the DMS spotlight (`dms ipc call spotlight toggle`); DMS launches through
  `Quickshell.execDetached` → `systemd-run --user --scope`. That hop costs 6 to 20 ms.
- The `app-org.chromium.Chromium-<pid>.scope` unit that appears ~490 ms after exec is created by
  Chromium itself (D-Bus `StartTransientUnit`). It is a startup milestone, not launcher latency.

## Measured baseline (profile on tmpfs, so a floor)

| Launch | exec → Hyprland `openwindow` |
|---|---|
| Real profile, 10 extensions | ~950 ms |
| Real profile, `--disable-extensions` | 790 ms |
| Fresh empty profile | 515 ms |

The 515 ms floor is GPU process init (232 ms) + GTK toolkit init (102 ms) + browser init. A cold
start cannot beat it. After the window appears, extension renderers spawn at +1.3 s and burn
~9.5 CPU-seconds over 4 s; that is the "lag after opening". MetaMask alone was 4.76 CPU-s.

## Ordered checklist when it feels slow

1. **Is the machine busy?** Launches took 1.7 to 3.3 s instead of ~1 s while DMS was being
   relaunched (42 times in one day by patch cycles), `theme-sync-dconf.path` was firing on every
   `settings.json` edit, an agent kept spawning `nautilus --new-window ~` (60 to 94 % CPU), and
   ollama's `llama-server` ran on CPU. Check:
   `journalctl --user -o short-precise --since '1 hour ago' | grep -E 'Started \[systemd-run\] /usr/bin/chromium|Chromium-.*Consumed'`
   for the start → "Consumed" wall time, `ps -eo pcpu,comm --sort=-pcpu | head`, and
   `cat /proc/pressure/cpu`. Fix the hog, not the browser.
2. **Extensions.** `chrome://extensions`: disable wallets and anything with a heavy service
   worker. Or keep them in a second profile opened on demand. This is the biggest lever.
3. **Profile weight.** History sqlite at 38 MB cost ~314 ms of DB tasks; Service Worker
   CacheStorage was 1.6 GB (x.com, Gmail, MS Loop); IndexedDB 376 MB. Clear site data for the
   heavy origins and clear history. `du -sh ~/.config/chromium/Default/* | sort -rh | head`.
4. **Unclean exits.** `profile.exit_type` in `Default/Preferences` should be `Normal` or
   `SessionEnded`. `Crashed` with a high `variations_crash_streak` in `Local State` means
   something kills the browser (agents' `kill -9`, session teardown). Every start then does
   crash-recovery work. Close it properly; SIGTERM to the browser pid is fine, SIGKILL is not.
5. **Near-instant open.** Keep one warm instance (`chromium --no-startup-window` at login); a
   later `chromium` or `chromium <url>` opens a window in the running instance in ~50 ms.

## Things that are not the problem (do not re-investigate)

- GPU: hardware accel on `/dev/dri/renderD128`, no blocklist, no swiftshader fallback, VA-API
  H264 decode + encode present. A one-off `GPU process launch failed: error_code=1002` /
  `GPU process isn't usable. Goodbye.` SIGTRAP came from a throwaway secondary `chromium <url>`
  invocation, not the main browser.
- `chromium-flags.conf`: `--ozone-platform=wayland` is required (152 ignores the
  `ozone-platform-hint` pref). `UseOzonePlatform` and `AcceleratedVideoDecodeLinuxZeroCopyGL`
  are unknown to 152 (checked against the binary's string table) and were removed.
- Unpacked extensions whose folder was deleted are hidden from `chrome://extensions` but stay in
  `Preferences` under `extensions.settings` with `location: 4`. They cost a failed stat per start,
  nothing more. Clean them only with the browser closed, or Chromium rewrites the file.
- Measuring: copying the 2.5 GB profile to tmpfs to benchmark triggers swap-out and looks like
  memory pressure. It is not. Measure with the Hyprland event socket, never by eye.

## The "set as default browser" bar

`~/.zshrc` exports `BROWSER=chromium`. `xdg-settings` short-circuits on `$BROWSER`, resolves the
binary back to the first desktop file whose `Exec` matches, and lands on a PWA entry, so
`xdg-settings check default-web-browser chromium.desktop` says "no" in terminals only. The
infobar appears for terminal launches, never for DMS launches, and clicking it is a no-op because
`set_browser_generic` refuses while `$BROWSER` is set. `xdg-mime query default
x-scheme-handler/https` is the truth (`chromium.desktop`). Drop the export to silence the bar.
