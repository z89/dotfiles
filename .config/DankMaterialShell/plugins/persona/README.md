<h1 align="center">persona</h1>

persona is a profile picture widget for the [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS) bar. it shows the same picture DMS uses on the lock screen, the control center header and the greeter, inside a ring and a disc drawn in live theme colours, with initials when there is no picture.

left click opens a small user panel with the name, host, uptime and lock, sleep, power and dash buttons. right click opens the power menu. both are configurable.

## ✨ highlights

- 🖼 **one picture** is read from AccountsService through DMS, so nothing is stored twice.
- 🎨 **a themed ring and disc**, the ring in a theme colour and the disc behind the picture, are both recoloured on every theme switch.
- 🔤 **the user's initials** sit in the disc when no picture is set.
- 🖱 **click actions** open the user panel, control center, dash, power menu or lock, picked per button.

## 📦 install

persona lives in the dotfiles at `~/.config/DankMaterialShell/plugins/persona`.

```sh
dms ipc call plugins enable persona
```

then add `persona` to a bar under settings, bar, widgets.

## 🖼 setting the picture

all three end up in the same place.

- `avatar-make photo.jpg`
- settings, profile in DMS
- `dms ipc call profile setImage /path/to/picture.png`

`avatar-make` turns a photo into a 512px square png framed for a circle, removes the background when [rembg](https://github.com/danielgatis/rembg) is installed, writes it to `~/.face` and registers it with DMS.

## ⚙️ settings

| key | default | effect |
| --- | --- | --- |
| `ringColor` | `primary` | ring colour, one of `primary`, `secondary`, `tertiary`, `outline` or `none` |
| `ringWidth` | `2` | ring thickness in px |
| `inset` | `3` | gap between the picture and the bar edge |
| `themedBackdrop` | `true` | theme-coloured disc behind the picture |
| `clickAction` | `popout` | `popout`, `controlcenter`, `dash`, `powermenu` or `lock` |
| `rightClickAction` | `powermenu` | `powermenu`, `controlcenter`, `lock` or `none` |

## 🔣 ascii avatars

`tools/ascii-avatar.py` turns a pixel-art sprite into coloured ascii art sized for an avatar. each sprite pixel becomes two glyphs side by side to match a monospace cell, and glyphs are picked by region, such as `@@` for the outline, `##` for hair and `()` for eyes. `--hair-hue` recolours the hair, `--underlay 0.4` puts a faint copy of the sprite under the glyphs so the face still reads at 24px, and `--pixel out.png` also writes the plain sprite.

```sh
tools/ascii-avatar.py sprite.png out --crop 9,0,26,23 --hair-hue 330 --underlay 0.4
avatar-make out.png --keep-bg
```

## 📄 license

MIT
