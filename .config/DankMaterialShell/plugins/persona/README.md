# Persona

Your profile picture on the [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bar.

- Shows the same picture DMS uses on the lock screen, the control centre header and the greeter (AccountsService via `PortalService.profileImage`). Nothing is stored twice.
- A ring in a live theme colour (primary, secondary, tertiary, outline, or none).
- A theme-coloured disc behind the picture. A picture with a transparent background is recoloured on every theme switch without touching the file.
- Initials in the disc when there is no picture.
- Left click opens a small user panel (name, host, uptime, Lock / Sleep / Power / Dash). Right click opens the power menu. Both are configurable.

## Install

```sh
git clone https://github.com/z89/persona ~/.config/DankMaterialShell/plugins/persona
dms ipc call plugin-scan scan
```

Then add `persona` to a bar section in Settings > Bar > Widgets.

## Setting the picture

Any of these work, they all end up in the same place:

- `avatar-make photo.jpg` (script in this repo's companion dotfiles, see below)
- Settings > Profile in DMS
- `dms ipc call profile setImage /path/to/picture.png`

`avatar-make` turns a photo into a 512px square PNG framed for a circle, removes the background when [rembg](https://github.com/danielgatis/rembg) is installed, writes it to `~/.face` and registers it with DMS.

## Settings

| Key | Default | Meaning |
|---|---|---|
| `ringColor` | `primary` | theme colour of the ring |
| `ringWidth` | `2` | ring thickness in px |
| `inset` | `3` | gap between avatar and bar edge |
| `themedBackdrop` | `true` | primary container fill behind the picture |
| `clickAction` | `popout` | `popout`, `controlcenter`, `dash`, `powermenu`, `lock` |
| `rightClickAction` | `powermenu` | `powermenu`, `controlcenter`, `lock`, `none` |

MIT.

## tools/ascii-avatar.py

Turns a pixel-art sprite into sharp, coloured ASCII art sized for an avatar. Every sprite pixel becomes a 2-wide, 1-tall run of glyphs (matching the 1:2 monospace cell), so the sprite's geometry is kept exactly. Glyphs are picked by region (`@@` outline, `##`/`%%` hair, `::`/`..` skin, `()` eyes, `vv` mouth) and coloured with the pixel's own colour; hair can be re-hued with `--hair-hue`. `--underlay 0.4` puts a faint nearest-neighbour copy of the sprite under the glyphs so the face still reads at 24px, and `--pixel out.png` also writes the plain recoloured sprite.

```sh
tools/ascii-avatar.py sprite.png out --crop 9,0,26,23 --hair-hue 330 --underlay 0.4
avatar-make out.png --keep-bg
```
