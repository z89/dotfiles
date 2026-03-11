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

# ── Options ──────────────────────────────────────────────────────────────────
unsetopt HIST_VERIFY
setopt no_auto_remove_slash

bindkey -v
typeset -g -A key

# ── Aliases ──────────────────────────────────────────────────────────────────
alias vim="nvim"

# ── Plugins ──────────────────────────────────────────────────────────────────
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# fzf
source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ── Starship ─────────────────────────────────────────────────────────────────
eval "$(starship init zsh)"
