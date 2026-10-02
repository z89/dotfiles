---
name: terminal
description: Context and rules for any task involving kitty, zsh, starship or fastfetch, covering fonts, prompt layout, colour generation, plugins and how the config files relate
argument-hint: [task description]
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# terminal setup

load this before any task touching kitty, zsh, the starship prompt, fastfetch or terminal colours.

## 🐱 kitty

the config is `~/.config/kitty/kitty.conf`.

| setting | value |
| --- | --- |
| font | `JetBrainsMono Nerd Font` |
| font size | `10.4` |
| window padding | `14 18` |
| remote control | `allow_remote_control yes` |
| remote socket | `unix:/tmp/kitty-{kitty_pid}` |
| close confirmation | `confirm_os_window_close 0` |
| colour include | `matugen-theme.conf`, then `dank-tabs.conf` |

### colour generation

`~/.config/kitty/matugen-theme.conf` is generated, never edit it. `~/.local/bin/palette-gen` builds an OKLCH palette from the wallpaper accent hue and writes it to `matugen-theme.next.conf`. `theme-apply` then fades every open kitty window to it over its remote control socket and promotes the file to `matugen-theme.conf`.

the generated file fills these slots.

| slots | holds |
| --- | --- |
| `color0` to `color15` | the terminal colours, with uniform lightness and chroma |
| `color64` to `color90` | the 27 matugen roles from `MD_ROLES` in `palette-gen` |
| `color91` to `color95` | the prompt colours, accent, accent bright, accent dim, muted and fg |

the matugen roles come from the `--md-*` properties that the `gtk4-vars` matugen template writes into `~/.config/gtk-4.0/dank-vars.css`. before that template has rendered once, `palette-gen` falls back to DMS's `~/.cache/DankMaterialShell/dms-colors.json`.

### why slots

text printed with a truecolor hex value keeps that colour forever. text printed with a 256 colour index points at kitty's palette, so it changes colour on the same frame as the background when the fade moves that slot. anything that should recolour while already on screen must print palette indexes (`38;5;N`), never hex. keep `MD_ROLES` order, the fastfetch config and these slot numbers in step.

## 🐚 zsh

the config is `~/.zshrc`.

| setting | value |
| --- | --- |
| vi mode | `bindkey -v` |
| key timeout | `KEYTIMEOUT=1` |
| history file | `~/.zsh_history` |
| history size | `10000` in memory and on disk |
| history options | `SHARE_HISTORY`, `HIST_IGNORE_DUPS`, `HIST_IGNORE_SPACE` |

### vi mode fixes

backspace and the common kill bindings are rebound so they work in vi insert mode.

```
^?  → backward-delete-char
^H  → backward-delete-char
^W  → backward-kill-word
^U  → backward-kill-line
```

### plugins

| plugin | source | purpose |
| --- | --- | --- |
| zsh-autosuggestions | `/usr/share/zsh/plugins/zsh-autosuggestions/` | inline suggestions from history |
| zsh-syntax-highlighting | `/usr/share/zsh/plugins/zsh-syntax-highlighting/` | live command colouring |
| fzf key bindings | `/usr/share/fzf/key-bindings.zsh` | history search on `Control + R`, file search on `Control + T`, directory jump on `Alt + C` |
| fzf completion | `/usr/share/fzf/completion.zsh` | fzf tab completion |

syntax highlighting colours commands, builtins and aliases `magenta`, which is `color5` and follows the theme.

### custom functions

`asp` switches the AWS profile.

```zsh
asp() { local p=$(aws configure list-profiles | fzf) && [ -n "$p" ] && export AWS_PROFILE=$p }
```

it opens an fzf picker of the configured profiles and exports the choice as `AWS_PROFILE`. the prompt shows the change straight away.

### completion

completion uses a menu (`zstyle ':completion:*' menu select`). list colours come from `LS_COLORS`, and the selected entry uses the fixed background `ma=48;2;31;32;34`, which does not follow the theme.

### prompt

starship starts at the end of `.zshrc` with `eval "$(starship init zsh)"`.

## 🚀 starship

| file | role |
| --- | --- |
| `~/.config/starship.template.toml` | the source, tracked in dotfiles |
| `~/.config/starship.toml` | the live config, rendered by `palette-gen` on every theme switch |
| `~/.config/starship.local.toml` | untracked machine fragment, appended verbatim after the template |

never edit `starship.toml`, the next theme switch overwrites it. edit the template, then run `palette-gen` to render it again.

### prompt layout

the prompt is one line. the left side is a custom `format` and the right side is `right_format = '$aws'` (zsh `RPROMPT`).

```
$username $hostname $directory
$git_branch $git_commit $git_state $git_metrics
$docker_context $package
$c $cmake $dart $deno $dotnet $elixir $elm $erlang $fennel $fortran $golang $gradle
$haskell $haxe $java $julia $kotlin $lua $nim $nodejs $ocaml $perl $php $python
$rlang $ruby $rust $scala $swift $zig $buf $bun
$nix_shell $conda $meson $memory_usage
$cmd_duration
$jobs $status $character
```

`git_status` is disabled.

### AWS module

the AWS module sits on the right with no icon (`symbol = ""`) and the `muted` colour. the `default` profile shows nothing, any other profile shows its alias. the aliases live in `starship.local.toml` and carry the region in the alias string.

### colour theming

the template names colours with `{{palette.<name>}}`, and `palette-gen` fills them with kitty slot numbers rather than hex values, so prompts already on screen fade with the theme.

| template name | rendered as |
| --- | --- |
| `red`, `green`, `yellow`, `blue`, `magenta`, `cyan` | `1` to `6` |
| `accent`, `accent_bright`, `accent_dim`, `muted`, `fg` | `91` to `95` |

the template's `[palettes.dank]` table redefines the standard names, so `bold purple` and the other module styles resolve to those slots too. a hex value written straight into the template stays fixed after it is printed.

### nerd font symbols

module symbols use nerd fonts v3 codepoints (`ttf-jetbrains-mono-nerd`). symbols that look like spaces in a plain editor are private use area characters, not missing ones. take correct values from `starship preset nerd-font-symbols` and apply them with a python script, since editors and linters tend to strip these characters.

## 📊 fastfetch

`~/.config/fastfetch/config.jsonc` is static and tracked. every colour in it is a kitty slot (`38;5;64` to `38;5;90`), so a printed fetch recolours with the fade. the `Monitor` line reads the first monitor from `hyprctl monitors -j`. the palette section labels each matugen role and the sixteen terminal colours.

## 📁 key files

| file | editable |
| --- | --- |
| `~/.config/kitty/kitty.conf` | yes |
| `~/.config/kitty/matugen-theme.conf` | no, generated by `palette-gen` |
| `~/.local/bin/palette-gen` | yes, owns the kitty palette and the starship render |
| `~/.config/matugen/templates/gtk4-vars` | yes, source of the `--md-*` roles |
| `~/.zshrc` | yes |
| `~/.config/starship.template.toml` | yes |
| `~/.config/starship.toml` | no, generated by `palette-gen` |
| `~/.config/fastfetch/config.jsonc` | yes, keep it on slot codes |

## 📏 rules

- never edit `starship.toml` or `matugen-theme.conf`, the next theme switch overwrites both.
- colours that must follow the theme on screen use kitty slot indexes, never hex.
- a new slot needs a free index. `fzf` uses some 256 colour indexes by default (108, 109, 110, 135, 144, 161, 168, 236 and 254), so keep clear of those.
- `asp` needs `fzf` and the AWS CLI.
