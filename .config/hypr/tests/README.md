<h1 align="center">hyprland tests</h1>

offline tests for `carry.lua`, the window carry animation, and `notify-focus.lua`, which focuses the kitty window behind a clicked notification. they run against a virtual compositor and never connect to hyprland or move a live window.

## 🧪 run

it needs lua 5.5. run it from the dotfiles root.

```sh
bash .config/hypr/tests/run.sh
```

## 📋 suites

| suite | covers |
| --- | --- |
| 🪟 `test_carry.lua` | basic carry behaviour |
| ⏱ `test_carry_inertia.lua` | input cadence, chained presses and reversals |
| 🖱 `test_carry_manual.lua` | handing control back on a Super drag or resize |
| 🗂 `test_carry_navigation.lua` | workspace ownership and stack order |
| 🎞 `test_carry_render.lua` | the rendered workspace slide and when the pin is released |
| 🎯 `test_clock_landing.lua` | adaptive timing and landing corrections |
| 🔔 `test_notify_focus.lua` | pairing a DankMaterialShell notification click with kitty's urgent window |

`test_carry_render.lua` models the workspace slide separately from the carry physics, matching the `gentle` spring in `hyprland.lua` and how hyprland 0.56.2 renders pinned windows. window coordinates alone cannot show the snap that comes from releasing the pin before the slide settles.

## ⚙️ options

| variable | effect |
| --- | --- |
| `CARRY=/abs/path/carry.lua` | test another copy of the carry module |
| `NOTIFY_FOCUS=/abs/path/notify-focus.lua` | test another copy of the notification module |
| `DUMP=1` | the core suite writes trajectory CSVs to the current directory |

a single suite runs on its own, for example `lua5.5 .config/hypr/tests/test_carry_render.lua`. live visual testing is separate and needs desktop control approval.
