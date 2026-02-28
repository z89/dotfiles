export GPG_TTY=$(tty)
export ZSH="$HOME/.oh-my-zsh"
export TERMINAL=kitty
export VISUAL='nvim'
export EDITOR='nvim'
export BROWSER=chromium.desktop
export PINENTRY=/usr/bin/pinetry-gtk-2
#export PATH=$HOME/bin:/usr/local/bin:$PATH
#export PATH=/opt/hipSYCL/ROCm/bin:$PATH
#export PATH="$PATH:/home/archie/.yarn/bin"
source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh

export ROCM_PATH=/opt/rocm
export CHROME_EXECUTABLE=/usr/bin/chromium

eval "$(starship init zsh)"


#export CPATH=$ROCM_PATH/include:$CPATH
#export LIBRARY_PATH=$ROCM_PATH/lib:$LIBRARY_PATH
#export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

show_hostname() {
    if [[ "$HOST" != "archbox" ]]; then
        echo "%m "
    fi
}

alias vim=\"nvim\"

ZSH_THEME="custom-z89"

plugins=(
	git
	zsh-autosuggestions
	zsh-syntax-highlighting
  zsh-vi-mode
)

source $ZSH/oh-my-zsh.sh


# use gpg-agent instead of ssh-agent
#unset SSH_AGENT_PID

#if [ "${gnupg_SSH_AUTH_SOCK_by:-0}" -ne $$ ]; then
#  export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
#fi
# Start ssh-agent silently for GitHub
eval "$(ssh-agent -s | sed '/^echo Agent pid/d')"

# exit ranger on S command
ranger() {
    if [ -z "$RANGER_LEVEL" ]; then
        /usr/bin/ranger "$@"
    else
        exit
    fi
}

# gpg-connect-agent updatestartuptty /bye >/dev/null

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

# wpg sequences
(cat $HOME/.config/wpg/sequences &)

# don't verify history (eg. execute sudo !! immediately)
unsetopt HIST_VERIFY

typeset -g -A key

bindkey -v

source /home/archie/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
setopt no_auto_remove_slash

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# pnpm
export PNPM_HOME="/home/archie/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
