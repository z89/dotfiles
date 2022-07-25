export GPG_TTY=$(tty)
export ZSH="/home/archie/.oh-my-zsh"
export EDITOR='vim'

# use gpg-agent instead of ssh-agent
unset SSH_AGENT_PID

if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
  export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
fi

gpg-connect-agent updatestartuptty /bye >/dev/null

autoload -Uz compinit
compinit

# prompt themes
autoload -Uz promptinit
promptinit

ZSH_THEME="custom-z89"

# Uncomment the following line to use case-sensitive completion.
CASE_SENSITIVE="false"

# Uncomment the following line if pasting URLs and other text is messed up.
DISABLE_MAGIC_FUNCTIONS="true"

# disable autocorrect 
ENABLE_CORRECTION="false"

COMPLETION_WAITING_DOTS="true"

plugins=(
	git
	zsh-autosuggestions
	zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh


# remove ls highlight color
_ls_colors=":ow=01;33"
zstyle ':completion:*:default' list-colors "${(s.:.)_ls_colors}"
LS_COLORS+=$_ls_colors

# wpg sequences
(cat $HOME/.config/wpg/sequences &)

# don't verify history (eg. execute sudo !! immediately)
unsetopt HIST_VERIFY

typeset -g -A key

bindkey -v
