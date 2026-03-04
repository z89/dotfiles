# ── Environment ───────────────────────────────────────────────────────────────
export GPG_TTY=$(tty)
export ZSH="$HOME/.oh-my-zsh"
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

# ── Oh My Zsh ─────────────────────────────────────────────────────────────────
ZSH_THEME="custom-z89"

plugins=(
	git
	zsh-autosuggestions
	zsh-syntax-highlighting
	zsh-vi-mode
)

DISABLE_MAGIC_FUNCTIONS="true"
COMPLETION_WAITING_DOTS="true"

source $ZSH/oh-my-zsh.sh

# ── Completion ────────────────────────────────────────────────────────────────
autoload -Uz compinit
compinit

autoload -Uz promptinit
promptinit

# ── Options ───────────────────────────────────────────────────────────────────
unsetopt HIST_VERIFY
setopt no_auto_remove_slash

bindkey -v
typeset -g -A key

# ── Aliases ───────────────────────────────────────────────────────────────────
alias vim="nvim"

# ── Functions ─────────────────────────────────────────────────────────────────
show_hostname() {
    if [[ "$HOST" != "archbox" ]]; then
        echo "%m "
    fi
}

# ── Plugins / Tools ───────────────────────────────────────────────────────────
# fzf
source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# wpg colour sequences
(cat $HOME/.config/wpg/sequences &)

# i3kit: error capture for Claude Code context
[ -f ~/Documents/Github-Projects/i3kit/zsh/i3kit.zsh ] && source ~/Documents/Github-Projects/i3kit/zsh/i3kit.zsh
