export GPG_TTY=$(tty)
export ZSH="$HOME/.oh-my-zsh"
export TERMINAL=kitty
export BROWSER=chromium.desktop
ZSH_THEME="custom-z89"

plugins=(
	git
	zsh-autosuggestions
	zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

export EDITOR='vim'
export TERM=termite
export PATH=$HOME/bin:/usr/local/bin:$PATH
export PATH=/opt/hipSYCL/ROCm/bin:$PATH
export PATH="$PATH:/home/archie/.yarn/bin"

# use gpg-agent instead of ssh-agent
unset SSH_AGENT_PID

if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
  export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
fi

# exit ranger on S command
ranger() {
    if [ -z "$RANGER_LEVEL" ]; then
        /usr/bin/ranger "$@"
    else
        exit
    fi
}

gpg-connect-agent updatestartuptty /bye >/dev/null

autoload -Uz compinit
compinit

# prompt themes
autoload -Uz promptinit
promptinit

# Uncomment the following line to use case-sensitive completion.
CASE_SENSITIVE="false"

# Uncomment the following line if pasting URLs and other text is messed up.
DISABLE_MAGIC_FUNCTIONS="true"

# disable autocorrect 
ENABLE_CORRECTION="true"

COMPLETION_WAITING_DOTS="true"

# remove ls highlight color
#_ls_colors=":ow=01;33"
#zstyle ':completion:*:default' list-colors "${(s.:.)_ls_colors}"
#LS_COLORS+=$_ls_colors

# wpg sequences
(cat $HOME/.config/wpg/sequences &)

# don't verify history (eg. execute sudo !! immediately)
unsetopt HIST_VERIFY

typeset -g -A key

bindkey -v

source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# bun completions
[ -s "/home/archie/.bun/_bun" ] && source "/home/archie/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
