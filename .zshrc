# ── Environment ───────────────────────────────────────────────────────────────
export GPG_TTY=$(tty)
export TERMINAL=kitty
export VISUAL='nvim'
export EDITOR='nvim'
export BROWSER=chromium
export CHROME_EXECUTABLE=/usr/bin/chromium
export ROCM_PATH=/opt/rocm

# SSH agent (systemd-managed)
export SSH_AUTH_SOCK="/run/user/1000/ssh-agent.socket"
ssh-add -l &>/dev/null || ssh-add ~/.ssh/id_ed25519 &>/dev/null

# pnpm
export PNPM_HOME="/home/archie/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# ── History ──────────────────────────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# ── Completion ───────────────────────────────────────────────────────────────
autoload -Uz compinit
compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}" "ma=48;2;31;32;34"

# ── Options ──────────────────────────────────────────────────────────────────
unsetopt HIST_VERIFY
setopt no_auto_remove_slash

bindkey -v
export KEYTIMEOUT=1

# Fix backspace/delete in vi mode
bindkey '^?' backward-delete-char
bindkey '^H' backward-delete-char
bindkey '^W' backward-kill-word
bindkey '^U' backward-kill-line

typeset -g -A key

# ── Aliases ──────────────────────────────────────────────────────────────────
alias vim="nvim"
alias vlc='QT_QPA_PLATFORM=xcb vlc'

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# ── Functions ────────────────────────────────────────────────────────────────
asp() { local p=$(aws configure list-profiles | fzf) && [ -n "$p" ] && export AWS_PROFILE=$p }

# ── Plugins ──────────────────────────────────────────────────────────────────
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH_HIGHLIGHT_STYLES[command]='fg=magenta'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=magenta'
ZSH_HIGHLIGHT_STYLES[alias]='fg=magenta'

# fzf
source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ── Starship ─────────────────────────────────────────────────────────────────
eval "$(starship init zsh)"

# ── Android SDK (Flutter dev) ─────────────────────────────────────────────────
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
# Android tooling (sdkmanager/avdmanager) + Gradle need JDK 17, not the system default 26
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"

# ── Coding agents run as the GitHub App, never as me ──────────────────────────
# APPENDED, not prepended: ~/.local/bin also holds `flask`, `golangci-lint` and
# `hyprpanel`, all of which exist in /usr/bin too. Putting it first would silently
# switch those three — and the local `hyprpanel` execs the STOCK hyprpanel-app,
# which skips every JS patch and breaks the theme switcher.
export PATH="$PATH:$HOME/.local/bin"

# agent-run takes the command directly. It cannot take `command`, which is a shell
# builtin with no binary on this system — agent-run ends in `exec env … "$@"`, and
# env only resolves real executables.
#
# No recursion: agent-run is a separate process, zsh functions are not exported to
# it, so `claude` inside it resolves to /usr/bin/claude.
#
# To run one as YOURSELF, bypass the function:  command claude
claude() { agent-run claude "$@"; }
codex()  { agent-run codex  "$@"; }

