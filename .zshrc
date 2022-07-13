export GPG_TTY=$(tty)

export ZSH="/home/archie/.oh-my-zsh"

autoload -Uz compinit
compinit

# prompt themes
autoload -Uz promptinit
promptinit

ZSH_THEME="custom-z89"

# Uncomment the following line to use case-sensitive completion.
CASE_SENSITIVE="true"

# Uncomment the following line if pasting URLs and other text is messed up.
DISABLE_MAGIC_FUNCTIONS="true"


# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

COMPLETION_WAITING_DOTS="true"


plugins=(
	git
	zsh-autosuggestions
	zsh-syntax-highlighting
)

#ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=13'

source $ZSH/oh-my-zsh.sh

export EDITOR='vim'

# wpg sequences
(cat $HOME/.config/wpg/sequences &)

# don't verify history (eg. execute sudo !! immediately)
unsetopt HIST_VERIFY

typeset -g -A key

# move forward & back by a words length
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word

# delete at a words length
bindkey '^H' backward-kill-word

